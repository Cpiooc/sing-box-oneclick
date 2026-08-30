#!/usr/bin/env bash
# shellcheck shell=bash

# v1.7 hardening layer: masked node views, one-time reveal after deployment,
# bounded backups and redacted backup diffs.

BACKUP_KEEP_DEFAULT="${SB_BACKUP_KEEP:-30}"

mask_secret() {
  local value=${1:-} n
  [[ -n "$value" ]] || { printf '%s' '-'; return 0; }
  n=${#value}
  if (( n <= 8 )); then
    printf '%s' '••••••••'
  else
    printf '%s••••••••%s' "${value:0:4}" "${value:n-4:4}"
  fi
}

# Override state_set_node so a freshly created/rebuilt node can reveal its
# credentials once without making `sb nodes` permanently disclose secrets.
state_set_node() {
  local key=$1 json=$2 tmp
  ensure_state
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg key "$key" --argjson value "$json" '.nodes[$key]=$value' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  render_node_info
  SB_NODE_JUST_CHANGED=true
}

show_nodes_cards() {
  local reveal=${1:-false}
  ensure_state
  render_node_info
  local keys key name type address port proto tls_mode uri secret uuid password method detail
  mapfile -t keys < <(jq -r '.nodes | keys[]' "$STATE_FILE")

  echo
  if [[ "$reveal" == true ]]; then
    headmsg "完整节点信息 · 敏感"
    warn "下方内容包含可直接连接节点的凭据。请勿截图公开或粘贴到不可信网站。"
  else
    headmsg "节点概览 · 已隐藏敏感信息"
    note "分享链接、UUID、密码默认打码。需要完整信息时运行：sb reveal"
  fi

  if (( ${#keys[@]} == 0 )); then
    warn "尚未创建脚本管理的节点。"
    return 0
  fi

  for key in "${keys[@]}"; do
    name=$(jq -r --arg k "$key" '.nodes[$k].name // $k' "$STATE_FILE")
    type=$(jq -r --arg k "$key" '.nodes[$k].type // "unknown"' "$STATE_FILE")
    address=$(jq -r --arg k "$key" '.nodes[$k].address // "-"' "$STATE_FILE")
    port=$(jq -r --arg k "$key" '.nodes[$k].port // "-"' "$STATE_FILE")
    proto=$(jq -r --arg k "$key" '.nodes[$k].firewall // "-"' "$STATE_FILE" | tr '[:lower:]' '[:upper:]')
    tls_mode=$(jq -r --arg k "$key" '.nodes[$k].certificate_mode // (if .nodes[$k].tls_enabled == false then "off" elif .nodes[$k].certificate == true then "tls" else "-" end)' "$STATE_FILE")
    uuid=$(jq -r --arg k "$key" '.nodes[$k].uuid // empty' "$STATE_FILE")
    password=$(jq -r --arg k "$key" '.nodes[$k].password // empty' "$STATE_FILE")
    uri=$(jq -r --arg k "$key" '.nodes[$k].uri // empty' "$STATE_FILE")

    echo
    echo -e "  ${C_CYAN}╭────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_GREEN}●${C_RESET} ${C_BOLD}${name}${C_RESET}  ${C_DIM}[${key}]${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}${type}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}入口${C_RESET}  ${C_WHITE}${address}:${port}${C_RESET}  ${C_DIM}${proto}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}TLS ${C_RESET}  ${tls_mode}"

    case "$key" in
      reality)
        detail=$(jq -r '.nodes.reality.reality_sni // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· Vision + Reality${C_RESET}"
        ;;
      hy2)
        detail=$(jq -r '.nodes.hy2.domain // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· QUIC + Salamander${C_RESET}"
        if [[ $(jq -r '.nodes.hy2.port_hopping.enabled // false' "$STATE_FILE") == true ]]; then
          echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}Hop ${C_RESET}  $(jq -r '.nodes.hy2.port_hopping.range // "-"' "$STATE_FILE")  ${C_DIM}· 30s${C_RESET}"
        fi
        ;;
      tuic)
        detail=$(jq -r '.nodes.tuic.domain // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}CC  ${C_RESET}  $(jq -r '.nodes.tuic.congestion_control // "-"' "$STATE_FILE")"
        ;;
      ws)
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}Path${C_RESET}  $(jq -r '.nodes.ws.path // "-"' "$STATE_FILE")  ${C_DIM}· Cloudflare${C_RESET}"
        ;;
      anytls|trojan)
        detail=$(jq -r --arg k "$key" '.nodes[$k].domain // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}"
        ;;
      ss)
        method=$(jq -r '.nodes.ss.method // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}Cipher${C_RESET} ${method}  ${C_DIM}· TCP + UDP${C_RESET}"
        ;;
    esac

    if [[ -n "$uuid" ]]; then
      secret=$uuid
      [[ "$reveal" == true ]] || secret=$(mask_secret "$uuid")
      echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}UUID${C_RESET}  ${secret}"
    fi
    if [[ -n "$password" ]]; then
      secret=$password
      [[ "$reveal" == true ]] || secret=$(mask_secret "$password")
      echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}密码${C_RESET}  ${secret}"
    fi

    echo -e "  ${C_CYAN}│${C_RESET}"
    if [[ "$reveal" == true && -n "$uri" ]]; then
      echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}分享链接${C_RESET}"
      echo -e "  ${C_CYAN}│${C_RESET} ${C_WHITE}${uri}${C_RESET}"
    else
      echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}分享链接  已隐藏 · sb reveal / sb qr${C_RESET}"
    fi
    echo -e "  ${C_CYAN}╰────────────────────────────────────────────────────────────╯${C_RESET}"
  done

  echo
  note "完整节点信息文件：$NODE_INFO（权限 600）。"
}

show_nodes() {
  if [[ ${SB_NODE_JUST_CHANGED:-false} == true ]]; then
    SB_NODE_JUST_CHANGED=false
    info "节点已创建/重建。为方便首次导入，下面仅本次显示完整连接信息。"
    show_nodes_cards true
  else
    show_nodes_cards false
  fi
}

show_nodes_full() {
  show_nodes_cards true
}

show_qr_codes() {
  ensure_state
  have qrencode || apt-get install -y qrencode
  local keys key uri name
  mapfile -t keys < <(jq -r '.nodes | keys[]' "$STATE_FILE")
  if (( ${#keys[@]} == 0 )); then
    warn "没有节点。"
    return 0
  fi
  warn "二维码包含完整节点凭据，只在可信环境中展示。"
  for key in "${keys[@]}"; do
    uri=$(jq -r --arg key "$key" '.nodes[$key].uri // empty' "$STATE_FILE")
    name=$(jq -r --arg key "$key" '.nodes[$key].name // $key' "$STATE_FILE")
    [[ -n "$uri" ]] || continue
    echo
    headmsg "$name"
    qrencode -t ANSIUTF8 "$uri" || true
  done
}

backup_dirs_newest() {
  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | cut -d' ' -f2-
}

backup_prune() {
  ensure_dirs
  local keep=${1:-$BACKUP_KEEP_DEFAULT} dirs=() i removed=0
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=30
  (( keep >= 5 )) || keep=5
  mapfile -t dirs < <(backup_dirs_newest)
  for (( i=keep; i<${#dirs[@]}; i++ )); do
    rm -rf -- "${dirs[$i]}"
    ((removed+=1))
  done
  if (( removed > 0 )); then
    info "已自动清理 ${removed} 个旧备份；默认保留最近 ${keep} 个。"
  fi
}

# Override the original backup function: same contents, collision-safe directory
# names, then bounded retention so long-running VPSes do not accumulate forever.
backup_all() {
  ensure_state
  local stamp dir n=0
  stamp=$(date +%Y%m%d-%H%M%S)
  dir="${BACKUP_DIR}/${stamp}"
  while [[ -e "$dir" ]]; do
    ((n+=1))
    dir="${BACKUP_DIR}/${stamp}-${n}"
  done
  install -d -m 700 "$dir"
  [[ -f "$CONFIG_FILE" ]] && cp -a "$CONFIG_FILE" "$dir/config.json"
  [[ -f "$STATE_FILE" ]] && cp -a "$STATE_FILE" "$dir/state.json"
  [[ -f "$NODE_INFO" ]] && cp -a "$NODE_INFO" "$dir/node-info.txt"
  LAST_BACKUP_DIR="$dir"
  info "已创建备份：$dir"
  backup_prune "$BACKUP_KEEP_DEFAULT"
}

redact_json_file() {
  local src=$1
  jq '
    walk(
      if type == "object" then
        with_entries(
          if (.key | ascii_downcase | test("^(password|uuid|private_key|short_id|token|uri|obfs_password)$"))
          then .value = "***REDACTED***"
          else .
          end
        )
      else . end
    )
  ' "$src" 2>/dev/null
}

backup_list() {
  ensure_dirs
  local dirs=() i
  mapfile -t dirs < <(backup_dirs_newest)
  echo
  headmsg "配置备份"
  if (( ${#dirs[@]} == 0 )); then
    warn "暂无备份。"
    return 0
  fi
  for i in "${!dirs[@]}"; do
    printf '  %2d  %s\n' "$((i+1))" "$(basename "${dirs[$i]}")"
  done
  note "自动保留最近 ${BACKUP_KEEP_DEFAULT} 个；可通过 SB_BACKUP_KEEP 调整。"
}

backup_diff_latest() {
  ensure_dirs
  local dirs=() latest tmp_old tmp_new label
  mapfile -t dirs < <(backup_dirs_newest)
  (( ${#dirs[@]} > 0 )) || { warn "暂无备份可比较。"; return 0; }
  latest=${dirs[0]}
  echo
  headmsg "最新备份 vs 当前配置 · 已脱敏"
  note "比较：$(basename "$latest") → current"

  for label in config state; do
    [[ -f "$latest/${label}.json" && -f "${label/config/$CONFIG_FILE}" ]] || true
  done

  if [[ -f "$latest/config.json" && -f "$CONFIG_FILE" ]]; then
    tmp_old=$(mktemp); tmp_new=$(mktemp)
    cleanup_files+=("$tmp_old" "$tmp_new")
    redact_json_file "$latest/config.json" > "$tmp_old"
    redact_json_file "$CONFIG_FILE" > "$tmp_new"
    echo
    echo -e "  ${C_BOLD}config.json${C_RESET}"
    diff -u "$tmp_old" "$tmp_new" || true
  fi

  if [[ -f "$latest/state.json" && -f "$STATE_FILE" ]]; then
    tmp_old=$(mktemp); tmp_new=$(mktemp)
    cleanup_files+=("$tmp_old" "$tmp_new")
    redact_json_file "$latest/state.json" > "$tmp_old"
    redact_json_file "$STATE_FILE" > "$tmp_new"
    echo
    echo -e "  ${C_BOLD}state.json${C_RESET}"
    diff -u "$tmp_old" "$tmp_new" || true
  fi
  note "Diff 默认隐藏 UUID、密码、Token、URI 等秘密。"
}

backup_manager() {
  local n
  while true; do
    echo
    headmsg "备份管理"
    ui_item 1 "查看备份" "最近 ${BACKUP_KEEP_DEFAULT} 个"
    ui_item 2 "比较最新备份与当前配置" "默认脱敏"
    ui_item 3 "恢复备份" "恢复前会再自动备份"
    ui_item 4 "立即清理旧备份" "保留最近 ${BACKUP_KEEP_DEFAULT} 个"
    echo -e "  ${C_CYAN} 0${C_RESET}  返回"
    read -r -p "  请选择 › " n
    case "$n" in
      1) backup_list ;;
      2) backup_diff_latest ;;
      3) restore_backup ;;
      4) backup_prune "$BACKUP_KEEP_DEFAULT"; backup_list ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}
