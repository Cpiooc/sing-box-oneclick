#!/usr/bin/env bash
# shellcheck shell=bash

# Beginner-friendly BBR manager.
# - Saves the pre-BBR TCP congestion control + qdisc before this script changes them.
# - Restores the saved values when disabling.
# - Handles legacy installs that enabled BBR before baseline tracking existed.
# - Refuses to tear down BBR that appears to be managed by another tool.

BBR_STATE_FILE="${BBR_STATE_FILE:-${APP_DIR}/bbr-state.json}"

for _fn in enable_bbr bbr_status; do
  if declare -F "$_fn" >/dev/null 2>&1; then
    eval "$(declare -f "$_fn" | sed "1s/${_fn}/${_fn}_pre_manager/")"
  fi
done
unset _fn

bbr_current_cc() {
  sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true
}

bbr_current_qdisc() {
  sysctl -n net.core.default_qdisc 2>/dev/null || true
}

bbr_available_cc() {
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true
}

bbr_script_file_managed() {
  [[ -f "$BBR_SYSCTL" ]] || return 1
  grep -Fq 'Managed by Cpiooc/sing-box-oneclick' "$BBR_SYSCTL" 2>/dev/null
}

bbr_script_file_enables_bbr() {
  bbr_script_file_managed || return 1
  grep -Eq '^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=[[:space:]]*bbr([[:space:]]|$)' "$BBR_SYSCTL" 2>/dev/null
}

bbr_state_valid() {
  [[ -f "$BBR_STATE_FILE" ]] || return 1
  jq -e '.previous_cc and .previous_qdisc and (.baseline_known | type == "boolean")' "$BBR_STATE_FILE" >/dev/null 2>&1
}

bbr_save_baseline() {
  bbr_state_valid && return 0

  local cc qdisc baseline_known=true legacy=false tmp
  cc=$(bbr_current_cc)
  qdisc=$(bbr_current_qdisc)
  [[ -n "$cc" ]] || cc="unknown"
  [[ -n "$qdisc" ]] || qdisc="unknown"

  # Old sing-box-oneclick releases may already have enabled BBR without saving
  # the previous values. Do not pretend that bbr/fq were the original settings.
  if bbr_script_file_enables_bbr && [[ "$cc" == "bbr" ]]; then
    baseline_known=false
    legacy=true
  fi

  install -d -m 700 "$APP_DIR"
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq -n \
    --arg cc "$cc" \
    --arg qdisc "$qdisc" \
    --argjson baseline_known "$baseline_known" \
    --argjson legacy "$legacy" \
    --arg captured_at "$(date -Is 2>/dev/null || date)" \
    '{previous_cc:$cc,previous_qdisc:$qdisc,baseline_known:$baseline_known,legacy_detected:$legacy,captured_at:$captured_at}' > "$tmp"
  install -m 600 "$tmp" "$BBR_STATE_FILE"
}

bbr_choose_fallback_cc() {
  local available cc
  available=$(bbr_available_cc)
  for cc in cubic reno; do
    if grep -qw "$cc" <<< "$available"; then
      printf '%s' "$cc"
      return 0
    fi
  done
  for cc in $available; do
    [[ "$cc" == bbr ]] && continue
    printf '%s' "$cc"
    return 0
  done
  return 1
}

bbr_apply_runtime_value() {
  local key=$1 value=$2
  [[ -n "$value" && "$value" != unknown ]] || return 0
  sysctl -w "${key}=${value}" >/dev/null 2>&1
}

enable_bbr() {
  install_deps
  bbr_save_baseline

  enable_bbr_pre_manager "$@"

  local cc tmp
  cc=$(bbr_current_cc)
  if [[ "$cc" == bbr ]]; then
    tmp=$(mktemp)
    cleanup_files+=("$tmp")
    jq --arg enabled_at "$(date -Is 2>/dev/null || date)" '.enabled_by_script=true | .enabled_at=$enabled_at' "$BBR_STATE_FILE" > "$tmp"
    install -m 600 "$tmp" "$BBR_STATE_FILE"
    info "BBR 开启前的 TCP 设置已安全保存，可随时使用 sb bbr off 恢复。"
  else
    warn "BBR 没有成功启用；已保留原设置记录，不会自动替换内核。"
  fi
}

disable_bbr() {
  install_deps
  local cc qdisc target_cc target_qdisc baseline_known=false legacy=false
  cc=$(bbr_current_cc)
  qdisc=$(bbr_current_qdisc)

  if bbr_state_valid; then
    baseline_known=$(jq -r '.baseline_known // false' "$BBR_STATE_FILE")
    legacy=$(jq -r '.legacy_detected // false' "$BBR_STATE_FILE")
  fi

  if ! bbr_state_valid && ! bbr_script_file_managed; then
    if [[ "$cc" == bbr ]]; then
      warn "检测到 BBR 正在运行，但不是本脚本管理的配置。为避免破坏其他工具设置，本脚本不会自动关闭。"
      note "如果确认要交给本脚本管理，可先运行 sb bbr on，再使用 sb bbr off。"
    else
      note "BBR 当前已经关闭，无需操作。"
    fi
    return 0
  fi

  if bbr_script_file_managed; then
    rm -f "$BBR_SYSCTL"
  else
    warn "没有删除 $BBR_SYSCTL：文件不是本脚本创建的。"
  fi

  # Reload remaining sysctl files first. Removing a sysctl file does not always
  # reset the current runtime value, so the saved baseline is applied below.
  sysctl --system >/dev/null 2>&1 || true

  if bbr_state_valid && [[ "$baseline_known" == true ]]; then
    target_cc=$(jq -r '.previous_cc' "$BBR_STATE_FILE")
    target_qdisc=$(jq -r '.previous_qdisc' "$BBR_STATE_FILE")

    if ! grep -qw "$target_cc" <<< "$(bbr_available_cc)"; then
      warn "原拥塞控制算法 ${target_cc} 当前不可用，将选择安全的非 BBR 回退。"
      target_cc=$(bbr_choose_fallback_cc) || die "找不到可用的非 BBR 拥塞控制算法。"
    fi

    bbr_apply_runtime_value net.ipv4.tcp_congestion_control "$target_cc" \
      || die "无法恢复 TCP 拥塞控制算法：$target_cc"
    if ! bbr_apply_runtime_value net.core.default_qdisc "$target_qdisc"; then
      warn "原 qdisc ${target_qdisc} 当前无法恢复，保留系统当前值 $(bbr_current_qdisc)。"
    fi
    info "已关闭脚本管理的 BBR，并恢复开启前设置：${target_cc} / $(bbr_current_qdisc)。"
  else
    target_cc=$(bbr_choose_fallback_cc) || die "找不到可用的非 BBR 拥塞控制算法。"
    bbr_apply_runtime_value net.ipv4.tcp_congestion_control "$target_cc" \
      || die "无法切换到非 BBR 拥塞控制算法：$target_cc"
    warn "这是旧版 BBR 配置，脚本没有保存当时的原始 qdisc；已安全切换为 ${target_cc}，qdisc 保持 ${qdisc:-当前值}。"
  fi

  rm -f "$BBR_STATE_FILE"
  bbr_status
}

bbr_status() {
  bbr_status_pre_manager "$@"
  echo
  headmsg "脚本管理状态"
  if bbr_state_valid; then
    local known prev_cc prev_qdisc
    known=$(jq -r '.baseline_known // false' "$BBR_STATE_FILE")
    prev_cc=$(jq -r '.previous_cc // "-"' "$BBR_STATE_FILE")
    prev_qdisc=$(jq -r '.previous_qdisc // "-"' "$BBR_STATE_FILE")
    ui_kv "管理" "已记录"
    if [[ "$known" == true ]]; then
      ui_kv "关闭时恢复" "${prev_cc} / ${prev_qdisc}"
    else
      ui_kv "关闭时恢复" "旧版无历史记录，将安全退回非 BBR"
    fi
  elif bbr_script_file_enables_bbr; then
    ui_kv "管理" "旧版脚本配置"
    ui_kv "关闭时恢复" "原设置未知，将优先退回 cubic"
  elif [[ $(bbr_current_cc) == bbr ]]; then
    ui_kv "管理" "外部配置"
    ui_kv "安全策略" "默认不自动关闭其他工具配置的 BBR"
  else
    ui_kv "管理" "未启用"
  fi
}

bbr_menu() {
  while true; do
    echo
    headmsg "TCP BBR 管理"
    note "BBR 只影响 TCP；Hysteria2 / TUIC 的 QUIC/UDP 不使用这里的 TCP BBR。"
    bbr_status
    echo
    ui_group "操作" "小白直接按需要选择开 / 关"
    ui_item 1 "开启 BBR + fq" "首次开启会记录原设置"
    ui_item 2 "关闭 BBR" "优先恢复开启前设置"
    ui_item 3 "刷新详细状态"
    ui_item 0 "返回"
    ui_group_end
    read -r -p "  请选择 › " choice
    case "$choice" in
      1) enable_bbr || true ;;
      2) disable_bbr || true ;;
      3) ;;
      0) return 0 ;;
      *) warn "无效选择：${choice:-空}" ;;
    esac
  done
}

bbr_cli() {
  case "${1:-menu}" in
    menu|"")
      if [[ -t 0 && -t 1 ]]; then
        bbr_menu
      else
        bbr_status
      fi
      ;;
    on|enable|start) enable_bbr ;;
    off|disable|stop) disable_bbr ;;
    status|show) bbr_status ;;
    *)
      err "用法：sb bbr [on|off|status]"
      return 2
      ;;
  esac
}
