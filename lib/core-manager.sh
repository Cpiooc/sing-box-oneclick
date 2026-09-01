#!/usr/bin/env bash
# shellcheck shell=bash

# sing-box core version manager.
# Official installer supports: --version <version>
# This layer adds beginner-friendly version selection, validation and rollback.

CORE_UPSTREAM_REPO="SagerNet/sing-box"
CORE_UPSTREAM_API="https://api.github.com/repos/${CORE_UPSTREAM_REPO}"
CORE_INSTALLER_URL="https://sing-box.app/install.sh"
CORE_STATE_DIR="${CORE_STATE_DIR:-${APP_DIR}/core-manager}"
CORE_BACKUP_DIR="${CORE_BACKUP_DIR:-${CORE_STATE_DIR}/backups}"
CORE_BACKUP_KEEP="${SB_CORE_BACKUP_KEEP:-5}"

core_current_version() {
  have sing-box || return 0
  sing-box version 2>/dev/null | head -n1 | sed -E 's/^sing-box version[[:space:]]+//; s/[[:space:]].*$//' || true
}

core_normalize_version() {
  local version=${1:-}
  version=${version#v}
  version=${version//[[:space:]]/}
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || return 1
  printf '%s' "$version"
}

core_api_get() {
  local path=$1
  curl -fsSL --proto '=https' --tlsv1.2 --max-time 15 \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: sing-box-oneclick' \
    "${CORE_UPSTREAM_API}${path}"
}

core_latest_stable_version() {
  local json tag
  json=$(core_api_get '/releases/latest') || return 1
  tag=$(jq -r '.tag_name // empty' <<< "$json")
  core_normalize_version "$tag"
}

core_release_json() {
  local version
  version=$(core_normalize_version "$1") || return 1
  core_api_get "/releases/tags/v${version}"
}

core_release_exists() {
  local version json
  version=$(core_normalize_version "$1") || return 1
  json=$(core_release_json "$version") || return 1
  [[ $(jq -r '(.draft == false) and ((.tag_name // "") != "")' <<< "$json") == true ]]
}

core_release_kind() {
  local json
  json=$(core_release_json "$1") || return 1
  if [[ $(jq -r '.prerelease // false' <<< "$json") == true ]]; then
    printf '%s' 'prerelease'
  else
    printf '%s' 'stable'
  fi
}

core_list_versions() {
  local json limit=${1:-12}
  json=$(core_api_get '/releases?per_page=40') || {
    warn "无法获取 sing-box 版本列表，请检查 GitHub 网络连接。"
    return 1
  }

  echo
  headmsg "可用稳定版本"
  jq -r --argjson limit "$limit" '
    [ .[] | select((.draft == false) and (.prerelease == false)) ][0:$limit][] |
    [(.tag_name | sub("^v"; "")), (.published_at[0:10] // "-")] | @tsv
  ' <<< "$json" | awk -F '\t' '{printf "  %-16s %s\n", $1, $2}'
  echo
  note "这里只展示最近的稳定版；如明确需要 RC/测试版，可用 sb core install <版本> 指定。"
}

core_binary_path() {
  command -v sing-box 2>/dev/null || true
}

core_snapshot_dirs_newest_first() {
  [[ -d "$CORE_BACKUP_DIR" ]] || return 0
  find "$CORE_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-
}

core_prune_snapshots() {
  local keep=$CORE_BACKUP_KEEP idx=0 dir
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=5
  (( keep >= 2 )) || keep=2
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    idx=$((idx + 1))
    (( idx <= keep )) && continue
    rm -rf -- "$dir"
  done < <(core_snapshot_dirs_newest_first)
}

core_capture_snapshot() {
  have sing-box || return 0
  local version bin stamp dir
  version=$(core_current_version)
  bin=$(core_binary_path)
  [[ -n "$version" && -x "$bin" ]] || return 1

  install -d -m 700 "$CORE_STATE_DIR" "$CORE_BACKUP_DIR"
  stamp=$(date +%Y%m%d-%H%M%S)
  dir="${CORE_BACKUP_DIR}/${stamp}-${version}"
  install -d -m 700 "$dir"
  cp -a "$bin" "$dir/sing-box.bin"
  chmod 700 "$dir/sing-box.bin"
  jq -n \
    --arg version "$version" \
    --arg binary_path "$bin" \
    --arg captured_at "$(date -Is 2>/dev/null || date)" \
    '{version:$version,binary_path:$binary_path,captured_at:$captured_at}' > "$dir/meta.json"
  chmod 600 "$dir/meta.json"
  core_prune_snapshots
  printf '%s' "$dir"
}

core_snapshot_version() {
  local dir=$1
  jq -r '.version // empty' "$dir/meta.json" 2>/dev/null || true
}

core_previous_snapshot() {
  local current dir version
  current=$(core_current_version)
  while IFS= read -r dir; do
    [[ -f "$dir/meta.json" && -f "$dir/sing-box.bin" ]] || continue
    version=$(core_snapshot_version "$dir")
    [[ -n "$version" && "$version" != "$current" ]] || continue
    printf '%s' "$dir"
    return 0
  done < <(core_snapshot_dirs_newest_first)
  return 1
}

core_download_installer() {
  local dst=$1
  download_checked_script "$CORE_INSTALLER_URL" "$dst"
}

core_run_official_installer() {
  local version=$1 installer
  installer=$(mktemp)
  cleanup_files+=("$installer")
  core_download_installer "$installer"
  bash "$installer" --version "$version"
}

core_config_check() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  sing-box check -c "$CONFIG_FILE"
}

core_restart_if_configured() {
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [[ ! -f "$CONFIG_FILE" ]]; then
    note "当前还没有服务端配置；核心已安装，创建第一个节点时再启动服务。"
    return 0
  fi

  core_config_check || return 1
  systemctl enable sing-box >/dev/null 2>&1 || true
  systemctl restart sing-box || return 1
  sleep 1
  systemctl is-active --quiet sing-box
}

core_restore_snapshot_binary() {
  local dir=$1 bin_path version
  [[ -f "$dir/meta.json" && -f "$dir/sing-box.bin" ]] || return 1
  bin_path=$(jq -r '.binary_path // empty' "$dir/meta.json")
  version=$(jq -r '.version // empty' "$dir/meta.json")
  [[ -n "$bin_path" && -n "$version" ]] || return 1

  install -m 0755 "$dir/sing-box.bin" "$bin_path" || return 1
  if [[ $(core_current_version) != "$version" ]]; then
    return 1
  fi
  core_restart_if_configured
}

core_restore_after_failure() {
  local dir=${1:-} old_version
  [[ -n "$dir" && -d "$dir" ]] || {
    warn "没有可恢复的旧 sing-box 快照。"
    return 1
  }

  old_version=$(core_snapshot_version "$dir")
  warn "版本切换失败，正在恢复 sing-box ${old_version:-旧版本}..."

  # Prefer restoring through the official installer so package metadata also
  # matches. If that fails, fall back to the exact saved binary.
  if [[ -n "$old_version" ]] && core_run_official_installer "$old_version" >/dev/null 2>&1; then
    if [[ $(core_current_version) == "$old_version" ]] && core_restart_if_configured; then
      info "已通过官方安装器恢复 sing-box $old_version。"
      return 0
    fi
  fi

  if core_restore_snapshot_binary "$dir"; then
    info "已从本地二进制快照恢复 sing-box $old_version。"
    warn "包管理器记录可能仍显示切换失败时的版本；下次成功执行版本安装会自动修正。"
    return 0
  fi

  err "自动恢复失败，请不要关闭当前 SSH 会话；运行 sb doctor 并检查 sing-box 日志。"
  return 1
}

core_is_downgrade() {
  local target=$1 current=${2:-$(core_current_version)}
  [[ -n "$current" ]] || return 1
  if have dpkg; then
    dpkg --compare-versions "$target" lt "$current"
  else
    [[ "$target" != "$current" ]]
  fi
}

core_confirm_version_change() {
  local target=$1 current=${2:-} kind=${3:-stable} ans
  [[ ${SB_CORE_ASSUME_YES:-0} == 1 ]] && return 0
  [[ -t 0 && -t 1 ]] || return 0

  echo
  if [[ "$kind" == prerelease ]]; then
    warn "目标 $target 是预发布版本，不建议小白作为长期主力使用。"
  fi
  if [[ -n "$current" ]] && core_is_downgrade "$target" "$current"; then
    warn "这是降级：$current → $target。旧版本可能不认识当前配置里的新字段。"
    note "脚本会先备份旧核心，安装后执行 sing-box check；不兼容会自动恢复。"
    read -r -p "  确认降级？[y/N] › " ans
    [[ ${ans,,} == y || ${ans,,} == yes ]]
  else
    read -r -p "  安装 sing-box $target？[Y/n] › " ans
    [[ -z "$ans" || ${ans,,} == y || ${ans,,} == yes ]]
  fi
}

core_install_version() {
  install_deps
  local requested=${1:-} target current kind snapshot="" actual
  target=$(core_normalize_version "$requested") || {
    err "版本格式无效：${requested:-空}。示例：1.13.19 或 1.14.0-rc.4"
    return 2
  }

  info "检查 sing-box v${target} 是否存在..."
  if ! core_release_exists "$target"; then
    err "没有找到官方发布版本 v${target}。"
    note "可运行 sb core list 查看最近稳定版本。"
    return 1
  fi
  kind=$(core_release_kind "$target" 2>/dev/null || echo stable)
  current=$(core_current_version)

  if [[ "$current" == "$target" ]]; then
    info "当前已经是 sing-box $target，无需重复安装。"
    core_status
    return 0
  fi

  core_confirm_version_change "$target" "$current" "$kind" || {
    warn "已取消版本切换。"
    return 0
  }

  if [[ -n "$current" ]]; then
    backup_all
    snapshot=$(core_capture_snapshot) || {
      err "无法保存当前 sing-box 二进制快照，已取消版本切换。"
      return 1
    }
    info "已备份当前核心：$current"
  fi

  info "通过官方安装器安装 sing-box $target..."
  if ! core_run_official_installer "$target"; then
    err "官方安装器执行失败。"
    [[ -n "$snapshot" ]] && core_restore_after_failure "$snapshot" || true
    return 1
  fi

  actual=$(core_current_version)
  if [[ "$actual" != "$target" ]]; then
    err "版本校验失败：期望 $target，实际 ${actual:-unknown}。"
    [[ -n "$snapshot" ]] && core_restore_after_failure "$snapshot" || true
    return 1
  fi

  if ! core_config_check; then
    err "sing-box $target 无法通过当前配置校验。"
    warn "这通常发生在降级后旧版本不认识新配置字段。"
    [[ -n "$snapshot" ]] && core_restore_after_failure "$snapshot" || true
    return 1
  fi

  if ! core_restart_if_configured; then
    err "sing-box $target 安装后服务未能正常运行。"
    [[ -n "$snapshot" ]] && core_restore_after_failure "$snapshot" || true
    return 1
  fi

  info "sing-box 已安全切换到 $target。"
  if [[ -n "$snapshot" ]]; then
    note "上一版本 $current 已保留，可用 sb core rollback 回退。"
  fi
  return 0
}

core_update_latest() {
  local latest current
  info "获取 sing-box 最新稳定版..."
  latest=$(core_latest_stable_version) || {
    err "无法获取最新稳定版本，请检查 GitHub 网络连接。"
    return 1
  }
  current=$(core_current_version)
  if [[ "$current" == "$latest" ]]; then
    info "当前已是最新稳定版：$latest"
    return 0
  fi
  note "当前：${current:-未安装}"
  note "最新稳定版：$latest"
  core_install_version "$latest"
}

core_rollback() {
  local snapshot target current ans
  snapshot=$(core_previous_snapshot) || {
    warn "没有找到可回退的上一版本核心快照。"
    return 0
  }
  target=$(core_snapshot_version "$snapshot")
  current=$(core_current_version)

  echo
  headmsg "回退 sing-box"
  ui_kv "当前版本" "${current:-未安装}"
  ui_kv "回退目标" "$target"
  note "回退仍会先备份当前核心，并校验现有配置；失败会恢复到当前版本。"

  if [[ -t 0 && -t 1 ]]; then
    read -r -p "  确认回退？[y/N] › " ans
    [[ ${ans,,} == y || ${ans,,} == yes ]] || { warn "已取消。"; return 0; }
  fi
  SB_CORE_ASSUME_YES=1 core_install_version "$target"
}

core_status() {
  local current latest previous="-" snapshot
  current=$(core_current_version)
  latest=$(core_latest_stable_version 2>/dev/null || echo unknown)
  snapshot=$(core_previous_snapshot 2>/dev/null || true)
  [[ -n "$snapshot" ]] && previous=$(core_snapshot_version "$snapshot")

  echo
  headmsg "sing-box 版本状态"
  ui_kv "当前版本" "${current:-未安装}"
  ui_kv "最新稳定版" "$latest"
  ui_kv "可回退版本" "$previous"
  if [[ -n "$current" && "$latest" != unknown && "$current" == "$latest" ]]; then
    info "当前已是最新稳定版。"
  elif [[ -n "$current" && "$latest" != unknown ]]; then
    note "有新稳定版可用：$current → $latest"
  fi
}

core_menu() {
  while true; do
    echo
    headmsg "sing-box 版本管理"
    core_status
    echo
    ui_group "版本操作" "小白推荐使用 1"
    ui_item 1 "更新到最新稳定版" "推荐 · 自动校验和失败恢复"
    ui_item 2 "安装指定版本" "高级 · 支持升级 / 降级"
    ui_item 3 "回退到上一个版本" "使用本地核心快照"
    ui_item 4 "查看可用版本" "最近稳定版"
    ui_item 0 "返回"
    ui_group_end
    read -r -p "  请选择 › " choice
    case "$choice" in
      1) core_update_latest || true ;;
      2)
        echo
        note "输入版本号即可，例如 1.13.19。一般不需要加 v。"
        note "降级可能遇到配置不兼容，脚本会自动检查并恢复。"
        read -r -p "  目标版本 › " version
        [[ -n "$version" ]] && core_install_version "$version" || warn "未输入版本。"
        ;;
      3) core_rollback || true ;;
      4) core_list_versions || true ;;
      0) return 0 ;;
      *) warn "无效选择：${choice:-空}" ;;
    esac
  done
}

core_cli() {
  case "${1:-menu}" in
    menu|"")
      if [[ -t 0 && -t 1 ]]; then core_menu; else core_status; fi
      ;;
    status|show) core_status ;;
    latest|update) core_update_latest ;;
    install) [[ -n ${2:-} ]] || { err "用法：sb core install <版本>"; return 2; }; core_install_version "$2" ;;
    downgrade) [[ -n ${2:-} ]] || { err "用法：sb core downgrade <版本>"; return 2; }; core_install_version "$2" ;;
    rollback) core_rollback ;;
    list|versions) core_list_versions ;;
    *)
      err "用法：sb core [status|latest|install <版本>|downgrade <版本>|rollback|list]"
      return 2
      ;;
  esac
}

# Preserve old entry points but route them through the safer version manager.
install_singbox_core() {
  SB_CORE_ASSUME_YES=1 core_update_latest
}

install_singbox() {
  if have sing-box; then
    core_menu
  else
    SB_CORE_ASSUME_YES=1 core_update_latest
  fi
}

safe_update_singbox() {
  core_update_latest
}
