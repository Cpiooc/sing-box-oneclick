#!/usr/bin/env bash
# shellcheck shell=bash

# v1.7 usability + hardening layer. Loaded near the end so it can improve the
# presentation and maintenance behaviour without duplicating protocol modules.

BACKUP_KEEP_COUNT="${SB_BACKUP_KEEP_COUNT:-30}"

for _fn in select_certificate_mode show_qr_codes; do
  if declare -F "$_fn" >/dev/null 2>&1; then
    eval "$(declare -f "$_fn" | sed "1s/${_fn}/${_fn}_pre_usability/")"
  fi
done
unset _fn

mask_secret() {
  local value=${1:-} left=${2:-4} right=${3:-4} len
  [[ -n "$value" ]] || { printf '%s' '-'; return 0; }
  len=${#value}
  if (( len <= left + right + 3 )); then
    printf '%s' '••••••••'
  else
    printf '%s••••••••%s' "${value:0:left}" "${value:len-right:right}"
  fi
}

show_nodes() {
  ensure_state
  render_node_info
  local keys key name type address port proto tls_mode detail secret
  mapfile -t keys < <(jq -r '.nodes | keys[]' "$STATE_FILE")

  echo
  headmsg "节点安全视图"
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

    echo
    echo -e "  ${C_CYAN}╭────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_GREEN}●${C_RESET} ${C_BOLD}${name}${C_RESET}  ${C_DIM}[${key}]${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}${type}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}入口${C_RESET}  ${C_WHITE}${address}:${port}${C_RESET}  ${C_DIM}${proto}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}TLS ${C_RESET}  ${tls_mode}"

    case "$key" in
      reality)
        detail=$(jq -r '.nodes.reality.reality_sni // "-"' "$STATE_FILE")
        secret=$(jq -r '.nodes.reality.uuid // empty' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· Vision + Reality${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}UUID${C_RESET}  $(mask_secret "$secret")"
        ;;
      hy2)
        detail=$(jq -r '.nodes.hy2.domain // "-"' "$STATE_FILE")
        secret=$(jq -r '.nodes.hy2.password // empty' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· QUIC + Salamander${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}密码${C_RESET}  $(mask_secret "$secret")"
        if declare -F hy2_hop_enabled >/dev/null 2>&1 && hy2_hop_enabled; then
          echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}跳跃${C_RESET}  UDP/$(hy2_hop_range_dash) · $(hy2_hop_interval_seconds)s"
        fi
        ;;
      tuic)
        detail=$(jq -r '.nodes.tuic.domain // "-"' "$STATE_FILE")
        secret=$(jq -r '.nodes.tuic.uuid // empty' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}UUID${C_RESET}  $(mask_secret "$secret")"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}CC  ${C_RESET}  $(jq -r '.nodes.tuic.congestion_control // "-"' "$STATE_FILE")"
        ;;
      ws)
        secret=$(jq -r '.nodes.ws.uuid // empty' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}Path${C_RESET}  $(jq -r '.nodes.ws.path // "-"' "$STATE_FILE")  ${C_DIM}· Cloudflare${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}UUID${C_RESET}  $(mask_secret "$secret")"
        ;;
      anytls)
        detail=$(jq -r '.nodes.anytls.domain // "-"' "$STATE_FILE")
        secret=$(jq -r '.nodes.anytls.password // empty' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· native AnyTLS${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}密码${C_RESET}  $(mask_secret "$secret")"
        ;;
      trojan)
        detail=$(jq -r '.nodes.trojan.domain // "-"' "$STATE_FILE")
        secret=$(jq -r '.nodes.trojan.password // empty' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· native Trojan${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}密码${C_RESET}  $(mask_secret "$secret")"
        ;;
      ss)
        secret=$(jq -r '.nodes.ss.password // empty' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}Cipher${C_RESET} $(jq -r '.nodes.ss.method // "-"' "$STATE_FILE")  ${C_DIM}· TCP + UDP${C_RESET}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}密钥${C_RESET}  $(mask_secret "$secret")"
        ;;
    esac

    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}分享链接已隐藏 · 使用 sb qr 扫码，或 sb reveal 显示完整凭据${C_RESET}"
    echo -e "  ${C_CYAN}╰────────────────────────────────────────────────────────────╯${C_RESET}"
  done

  echo
  note "默认隐藏 UUID / 密码 / 密钥 / 分享链接，避免 SSH 截图或录屏泄露。"
  note "新手导入推荐：运行 sb qr 扫码；多设备推荐：运行 sb sub 配置 HTTPS 私有订阅。"
  note "完整节点信息仍保存在 $NODE_INFO（root-only，权限 600）。"
}

reveal_nodes() {
  ensure_state
  render_node_info
  echo
  headmsg "完整节点凭据"
  warn "以下内容包含 UUID、密码、密钥和完整分享链接。不要截图发到公开群、论坛或仓库。"
  echo
  cat "$NODE_INFO"
}

show_qr_codes() {
  warn "二维码包含完整节点凭据；只在自己的设备上扫码，不要公开截图。"
  show_qr_codes_pre_usability "$@"
}

# Keep TLS choices understandable for beginners while preserving every mode.
select_certificate_mode() {
  local server_name=$1 allow_off=${2:-false} choice default_choice
  CERT_MODE=""
  CERT_CLIENT_INSECURE=false
  TLS_ENABLED=true
  CERT_PATH=""
  KEY_PATH=""

  if is_hostname "$server_name"; then
    default_choice=1
  else
    default_choice=2
  fi

  while true; do
    echo
    headmsg "TLS 证书"
    if is_hostname "$server_name"; then
      note "检测到域名 ${server_name}。新手直接按 Enter，自动申请 Let's Encrypt 即可。"
    else
      note "当前使用 IP。公网 Let's Encrypt 不能直接给普通 IP 签发，默认使用自签证书。"
    fi
    ui_item 1 "自动申请 Let's Encrypt" "有域名时推荐 · 自动续期"
    ui_item 2 "自动生成自签证书" "无域名也能用 · 客户端需允许不安全证书"
    ui_item 3 "导入已有 PEM" "高级用户"
    if [[ "$allow_off" == true ]]; then
      ui_item 4 "关闭 TLS" "仅 VLESS WebSocket 可用"
    fi
    read -r -p "  请选择 [${default_choice}] › " choice
    choice=${choice:-$default_choice}

    case "$choice" in
      1)
        if ! is_hostname "$server_name"; then
          warn "当前是 IP，无法使用普通 ACME 域名证书；请选 2，或先准备一个解析到本机的域名。"
          continue
        fi
        ensure_acme_domain_certificate "$server_name"
        return 0
        ;;
      2) ensure_self_signed_certificate "$server_name"; return 0 ;;
      3) ensure_custom_certificate "$server_name"; return 0 ;;
      4)
        if [[ "$allow_off" == true ]]; then
          CERT_MODE="off"
          CERT_CLIENT_INSECURE=false
          TLS_ENABLED=false
          CERT_PATH=""
          KEY_PATH=""
          return 0
        fi
        ;;
    esac
    warn "无效选择。"
  done
}

backup_all() {
  ensure_state
  local stamp dir suffix=0
  stamp=$(date +%Y%m%d-%H%M%S)
  dir="${BACKUP_DIR}/${stamp}"
  while [[ -e "$dir" ]]; do
    suffix=$((suffix + 1))
    dir="${BACKUP_DIR}/${stamp}-${suffix}"
  done
  install -d -m 700 "$dir"
  [[ -f "$CONFIG_FILE" ]] && cp -a "$CONFIG_FILE" "$dir/config.json"
  [[ -f "$STATE_FILE" ]] && cp -a "$STATE_FILE" "$dir/state.json"
  [[ -f "$NODE_INFO" ]] && cp -a "$NODE_INFO" "$dir/node-info.txt"
  LAST_BACKUP_DIR="$dir"
  info "已创建备份：$dir"
  prune_backups true
}

backup_dirs_newest_first() {
  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-
}

prune_backups() {
  local quiet=${1:-false} keep=$BACKUP_KEEP_COUNT idx=0 dir removed=0
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=30
  (( keep >= 5 )) || keep=5
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    idx=$((idx + 1))
    if (( idx > keep )); then
      rm -rf -- "$dir"
      removed=$((removed + 1))
    fi
  done < <(backup_dirs_newest_first)
  if [[ "$quiet" != true ]]; then
    if (( removed > 0 )); then
      info "已清理 ${removed} 个旧备份；默认只保留最近 ${keep} 个。"
    else
      note "当前备份数量未超过 ${keep}，无需清理。"
    fi
  fi
}

backup_list() {
  local i=0 dir
  echo
  headmsg "配置备份"
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    i=$((i + 1))
    printf '  %2d  %s\n' "$i" "$(basename "$dir")"
  done < <(backup_dirs_newest_first)
  (( i > 0 )) || note "还没有备份。"
  echo
  note "自动保留最近 ${BACKUP_KEEP_COUNT} 个；每次安全配置变更前都会先备份。"
}

redact_json_for_diff() {
  local file=$1
  jq '
    walk(
      if type == "object" then
        with_entries(
          if (.key | ascii_downcase | test("password|uuid|private_key|public_key|short_id|token|uri"))
          then .value="***REDACTED***"
          else .
          end
        )
      else . end
    )
  ' "$file"
}

backup_pick_dir() {
  local prompt=$1 choice i=0 dir dirs=()
  mapfile -t dirs < <(backup_dirs_newest_first)
  (( ${#dirs[@]} > 0 )) || return 1
  for i in "${!dirs[@]}"; do
    printf '  %2d  %s\n' "$((i+1))" "$(basename "${dirs[$i]}")"
  done
  read -r -p "  ${prompt} › " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  (( choice >= 1 && choice <= ${#dirs[@]} )) || return 1
  printf '%s' "${dirs[$((choice-1))]}"
}

backup_diff() {
  ensure_dirs
  local a b ta tb
  if [[ $(backup_dirs_newest_first | wc -l) -lt 2 ]]; then
    warn "至少需要两个备份才能比较。"
    return 0
  fi
  echo
  headmsg "安全 Diff"
  note "为避免在终端泄露凭据，UUID、密码、密钥、Token 和分享链接会先打码再比较。"
  a=$(backup_pick_dir "选择旧版本序号") || { warn "无效选择。"; return 0; }
  b=$(backup_pick_dir "选择新版本序号") || { warn "无效选择。"; return 0; }
  [[ "$a" != "$b" ]] || { warn "请选择两个不同备份。"; return 0; }

  ta=$(mktemp -d)
  tb=$(mktemp -d)
  cleanup_files+=("$ta/config.json" "$ta/state.json" "$tb/config.json" "$tb/state.json")
  [[ -f "$a/config.json" ]] && redact_json_for_diff "$a/config.json" > "$ta/config.json"
  [[ -f "$b/config.json" ]] && redact_json_for_diff "$b/config.json" > "$tb/config.json"
  [[ -f "$a/state.json" ]] && redact_json_for_diff "$a/state.json" > "$ta/state.json"
  [[ -f "$b/state.json" ]] && redact_json_for_diff "$b/state.json" > "$tb/state.json"

  echo
  headmsg "config.json"
  diff -u --label "$(basename "$a")/config.json" --label "$(basename "$b")/config.json" "$ta/config.json" "$tb/config.json" || true
  echo
  headmsg "state.json"
  diff -u --label "$(basename "$a")/state.json" --label "$(basename "$b")/state.json" "$ta/state.json" "$tb/state.json" || true
  rm -rf "$ta" "$tb"
}

backup_menu() {
  while true; do
    backup_list
    ui_group "备份管理" "自动保留 + 安全 Diff"
    ui_item 1 "立即创建备份"
    ui_item 2 "恢复备份"
    ui_item 3 "比较两个备份" "敏感字段自动打码"
    ui_item 4 "立即清理旧备份" "默认保留最近 30 个"
    ui_group_end
    echo -e "  ${C_CYAN} 0${C_RESET}  返回"
    read -r -p "  请选择 › " choice
    case "$choice" in
      1) backup_all ;;
      2) restore_backup ;;
      3) backup_diff ;;
      4) prune_backups false ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

DOCTOR_OK=0
DOCTOR_WARN=0
DOCTOR_FAIL=0

doctor_ok() { DOCTOR_OK=$((DOCTOR_OK+1)); echo -e "  ${C_GREEN}✓${C_RESET} $*"; }
doctor_warn() { DOCTOR_WARN=$((DOCTOR_WARN+1)); echo -e "  ${C_YELLOW}!${C_RESET} $*"; }
doctor_fail() { DOCTOR_FAIL=$((DOCTOR_FAIL+1)); echo -e "  ${C_RED}✗${C_RESET} $*"; }

doctor_check_permissions() {
  local file=$1 expected=$2 label=$3 actual
  [[ -e "$file" ]] || { doctor_warn "$label 不存在：$file"; return 0; }
  actual=$(stat -c '%a' "$file" 2>/dev/null || echo '?')
  if [[ "$actual" == "$expected" ]]; then
    doctor_ok "$label 权限 $actual"
  else
    doctor_warn "$label 权限为 $actual，建议为 $expected"
  fi
}

doctor_check_state_config_drift() {
  local key tag state_port config_port drift=0
  [[ -f "$CONFIG_FILE" && -f "$STATE_FILE" ]] || return 0
  while IFS= read -r key; do
    tag=$(node_tag_for_key "$key" 2>/dev/null || true)
    [[ -n "$tag" ]] || continue
    state_port=$(jq -r --arg k "$key" '.nodes[$k].port // empty' "$STATE_FILE")
    config_port=$(jq -r --arg tag "$tag" '.inbounds[]? | select(.tag==$tag) | .listen_port // empty' "$CONFIG_FILE" | head -n1)
    if [[ "$state_port" != "$config_port" ]]; then
      doctor_fail "${key}: state 端口 ${state_port:-缺失} ≠ config 端口 ${config_port:-缺失}"
      drift=1
    fi
  done < <(jq -r '.nodes | keys[]' "$STATE_FILE")
  (( drift == 0 )) && doctor_ok "state.json 与 sing-box 管理入站端口一致"
}

doctor_check_certificates() {
  local key cert end end_epoch now days found=0
  now=$(date +%s)
  while IFS= read -r key; do
    found=1
    cert=$(jq -r --arg k "$key" '.nodes[$k].certificate_path // empty' "$STATE_FILE")
    if [[ -z "$cert" || ! -r "$cert" ]]; then
      doctor_fail "${key}: TLS 证书文件不存在或不可读"
      continue
    fi
    end=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2- || true)
    end_epoch=$(date -d "$end" +%s 2>/dev/null || echo 0)
    if (( end_epoch <= now )); then
      doctor_fail "${key}: TLS 证书已过期或无法解析"
    else
      days=$(( (end_epoch - now) / 86400 ))
      if (( days < 15 )); then
        doctor_warn "${key}: TLS 证书约 ${days} 天后到期"
      else
        doctor_ok "${key}: TLS 证书剩余约 ${days} 天"
      fi
    fi
  done < <(jq -r '.nodes | to_entries[] | select(.value.tls_enabled==true and .value.certificate==true) | .key' "$STATE_FILE")
  (( found == 1 )) || doctor_ok "没有需要检查的普通 TLS 证书节点"
}

doctor_check_firewall() {
  if ! have ufw; then
    doctor_warn "UFW 未安装（云防火墙仍需自行确认）"
    return 0
  fi
  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    doctor_warn "UFW 当前未启用"
    return 0
  fi
  doctor_ok "UFW 已启用"

  local key port mode status missing=0
  status=$(ufw status 2>/dev/null || true)
  while IFS= read -r key; do
    port=$(jq -r --arg k "$key" '.nodes[$k].port // empty' "$STATE_FILE")
    mode=$(jq -r --arg k "$key" '.nodes[$k].firewall // empty' "$STATE_FILE")
    validate_port "$port" || continue
    case "$mode" in
      tcp)
        grep -Eq "(^|[[:space:]])${port}/tcp([[:space:]]|$)" <<< "$status" || { doctor_warn "${key}: UFW 中未明确看到 TCP/${port}"; missing=1; }
        ;;
      udp)
        grep -Eq "(^|[[:space:]])${port}/udp([[:space:]]|$)" <<< "$status" || { doctor_warn "${key}: UFW 中未明确看到 UDP/${port}"; missing=1; }
        ;;
      both)
        grep -Eq "(^|[[:space:]])${port}/tcp([[:space:]]|$)" <<< "$status" || { doctor_warn "${key}: UFW 中未明确看到 TCP/${port}"; missing=1; }
        grep -Eq "(^|[[:space:]])${port}/udp([[:space:]]|$)" <<< "$status" || { doctor_warn "${key}: UFW 中未明确看到 UDP/${port}"; missing=1; }
        ;;
    esac
  done < <(jq -r '.nodes | keys[]' "$STATE_FILE")
  (( missing == 0 )) && doctor_ok "脚本管理节点的基础 UFW 端口检查通过"
}

doctor() {
  ensure_state
  DOCTOR_OK=0; DOCTOR_WARN=0; DOCTOR_FAIL=0
  echo
  headmsg "sb doctor · 一键体检"
  note "只检查，不会自动重启服务、改防火墙或改节点配置。"
  echo

  [[ ${EUID:-$(id -u)} -eq 0 ]] && doctor_ok "root 权限" || doctor_fail "当前不是 root"
  case "${ID:-}" in debian|ubuntu) doctor_ok "系统：${PRETTY_NAME:-$ID}" ;; *) doctor_fail "当前系统不在 Debian / Ubuntu 支持范围" ;; esac

  local cmd
  for cmd in curl jq openssl ip ss; do
    have "$cmd" && doctor_ok "依赖：$cmd" || doctor_fail "缺少依赖：$cmd"
  done
  if have sing-box; then
    doctor_ok "sing-box：$(sing-box version 2>/dev/null | head -n1 || echo installed)"
  else
    doctor_fail "sing-box 未安装"
  fi

  if systemctl is-active --quiet sing-box 2>/dev/null; then
    doctor_ok "sing-box 服务 active"
  else
    doctor_fail "sing-box 服务未运行；先看 sb logs"
  fi

  if [[ -f "$CONFIG_FILE" ]] && have sing-box && sing-box check -c "$CONFIG_FILE" >/dev/null 2>&1; then
    doctor_ok "sing-box 配置校验通过"
  else
    doctor_fail "sing-box 配置校验失败；可从备份恢复"
  fi

  if jq -e '.version and (.nodes | type=="object")' "$STATE_FILE" >/dev/null 2>&1; then
    doctor_ok "state.json 结构正常"
  else
    doctor_fail "state.json 损坏"
  fi

  doctor_check_permissions "$CONFIG_FILE" 600 "配置文件"
  doctor_check_permissions "$STATE_FILE" 600 "状态文件"
  [[ -f "$NODE_INFO" ]] && doctor_check_permissions "$NODE_INFO" 600 "节点信息文件"
  doctor_check_state_config_drift
  doctor_check_certificates
  doctor_check_firewall

  if [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no) == true ]]; then
    doctor_ok "系统时间已同步"
  else
    doctor_warn "系统时间未确认同步；Reality/TLS 可能受影响"
  fi

  if declare -F subscription_enabled >/dev/null 2>&1 && subscription_enabled; then
    if systemctl is-active --quiet sing-box-oneclick-subscription.service 2>/dev/null; then
      doctor_ok "HTTPS 私有订阅服务 active"
    else
      doctor_fail "状态显示订阅已开启，但订阅服务未运行"
    fi
  else
    doctor_ok "HTTPS 私有订阅未启用（可选功能）"
  fi

  if declare -F hy2_hop_enabled >/dev/null 2>&1 && hy2_hop_enabled; then
    if hy2_hop_rules_active; then
      doctor_ok "HY2 端口跳跃规则已生效"
    else
      doctor_fail "HY2 端口跳跃已开启但重定向规则丢失；运行 sb hy2-hop apply"
    fi
  fi

  local backup_count
  backup_count=$(backup_dirs_newest_first | wc -l)
  if (( backup_count <= BACKUP_KEEP_COUNT )); then
    doctor_ok "备份数量 ${backup_count}/${BACKUP_KEEP_COUNT}"
  else
    doctor_warn "备份数量 ${backup_count} 超过保留上限；运行 sb backup 后选择清理"
  fi

  if [[ -f "${MANAGER_DIR}/SHA256SUMS" ]]; then
    if (cd "$MANAGER_DIR" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
      doctor_ok "管理器文件 SHA256 校验通过"
    else
      doctor_fail "管理器文件 SHA256 校验失败；建议重新执行脚本更新"
    fi
  else
    doctor_warn "当前管理器没有 SHA256 清单（旧版安装结构）"
  fi

  echo
  ui_rule
  echo -e "  ${C_GREEN}PASS ${DOCTOR_OK}${C_RESET}   ${C_YELLOW}WARN ${DOCTOR_WARN}${C_RESET}   ${C_RED}FAIL ${DOCTOR_FAIL}${C_RESET}"
  if (( DOCTOR_FAIL > 0 )); then
    warn "存在需要处理的问题。优先修 FAIL；若配置异常，可进入“备份管理”比较或恢复。"
  elif (( DOCTOR_WARN > 0 )); then
    note "核心检查通过；WARN 多为可选安全项或环境提示。"
  else
    info "全部检查通过。"
  fi
  return 0
}

# Keep the existing safe UFW flow, then explicitly ensure Shadowsocks gets
# both protocols even on installations upgraded from older releases.
firewall_setup_v16() {
  firewall_setup
  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active' \
      && [[ -f "$STATE_FILE" ]] && jq -e '.nodes.ss != null' "$STATE_FILE" >/dev/null 2>&1; then
    local p
    p=$(jq -r '.nodes.ss.port // empty' "$STATE_FILE")
    if validate_port "$p"; then
      ufw allow "${p}/tcp" >/dev/null || true
      ufw allow "${p}/udp" >/dev/null || true
      info "Shadowsocks UFW 已确认同时放行 TCP/UDP/$p。"
    fi
  fi
}

self_update() {
  local ref remote ans short
  if declare -F resolve_repo_commit >/dev/null 2>&1; then
    ref=$(resolve_repo_commit) || die "无法锁定 GitHub main 的提交版本。"
    short=${ref:0:12}
    remote=$(curl -fsSL --max-time 10 "https://raw.githubusercontent.com/${REPO}/${ref}/VERSION" 2>/dev/null | tr -d '[:space:]' || true)
    echo
    headmsg "管理器安全更新"
    ui_kv "当前版本" "v${SCRIPT_VERSION}"
    ui_kv "远端版本" "v${remote:-unknown}"
    ui_kv "锁定提交" "$short"
    note "所有文件将从同一个 Git commit 下载，并按 SHA256SUMS 校验后再切换。"
    read -r -p "  确认更新？[y/N] › " ans
    [[ ${ans,,} == y || ${ans,,} == yes ]] || { note "已取消。"; return 0; }
    install_bundle_from_github "$ref"
  else
    warn "当前启动器不支持锁定提交；请重新运行最新一键安装命令完成升级。"
    return 1
  fi
  info "管理脚本已安全更新。退出后重新运行 sb 使用新版本。"
}

uninstall_all() {
  warn "此操作会停止 sing-box、HY2 端口跳跃和脚本管理的 HTTPS 订阅，并删除配置、状态、备份和 sb 命令。"
  warn "Let's Encrypt 证书、BBR、UFW、Fail2ban、Nginx 软件包和系统安全更新设置默认保留。"
  read -r -p "请输入 DELETE 确认完全卸载脚本管理内容: " ans
  [[ "$ans" == DELETE ]] || { warn "已取消。"; return 0; }

  if declare -F hy2_hop_cleanup_rules >/dev/null 2>&1; then hy2_hop_cleanup_rules; fi
  if declare -F hy2_hop_remove_unit >/dev/null 2>&1; then hy2_hop_remove_unit; fi

  local sub_service sub_unit sub_publish sub_hook
  sub_service=${SUBSCRIPTION_SERVICE:-sing-box-oneclick-subscription.service}
  sub_unit=${SUBSCRIPTION_UNIT:-/etc/systemd/system/sing-box-oneclick-subscription.service}
  sub_publish=${SUBSCRIPTION_PUBLISH_DIR:-/var/lib/sing-box-oneclick-subscription}
  sub_hook=${SUBSCRIPTION_CERTBOT_HOOK:-/etc/letsencrypt/renewal-hooks/deploy/sing-box-oneclick-subscription-reload.sh}

  systemctl stop "$sub_service" 2>/dev/null || true
  systemctl disable "$sub_service" 2>/dev/null || true
  rm -f "$sub_unit" "$sub_hook"
  rm -rf "$sub_publish"
  systemctl daemon-reload 2>/dev/null || true

  systemctl stop sing-box 2>/dev/null || true
  systemctl disable sing-box 2>/dev/null || true
  have apt-get && apt-get remove -y sing-box 2>/dev/null || true

  rm -rf "$CONFIG_DIR" "$APP_DIR" "$MANAGER_DIR"
  rm -f "$NODE_INFO" "$MANAGER_LINK"
  info "已删除 sing-box、脚本管理服务及 sing-box-oneclick 内容；系统级安全设置与证书默认保留。"
  exit 0
}

ui_cli_help() {
  ui_banner
  echo
  headmsg "快捷命令"
  cat <<'HELP'
  sb                 打开交互式管理控制台
  sb status          服务状态 + 配置校验
  sb doctor          一键体检（只检查，不自动改配置）
  sb nodes           查看节点安全视图（敏感信息打码）
  sb reveal          显示完整节点凭据 / 分享链接（敏感）
  sb qr              显示节点二维码（包含完整凭据）
  sb edit            原地修改节点参数
  sb export          本地生成 sing-box / Mihomo / v2rayN 配置
  sb sub             管理安全 HTTPS 私有订阅
  sb hy2-hop         管理 HY2 UDP 端口跳跃（高级，默认关闭）
  sb backup          备份管理 / 安全 Diff / 自动清理
  sb anytls          部署 / 重建 AnyTLS
  sb trojan          部署 / 重建 Trojan
  sb ss              部署 / 重建 Shadowsocks
  sb logs            查看最近日志
  sb audit           完整安全自检
  sb bbr             查看 TCP BBR 状态
  sb cert            查看证书状态
  sb version         显示脚本与 sing-box 版本
  sb help            显示此帮助
HELP
}
