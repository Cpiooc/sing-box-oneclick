#!/usr/bin/env bash
# shellcheck shell=bash

DOCTOR_OK=0
DOCTOR_WARN=0
DOCTOR_FAIL=0

doctor_ok() {
  ((DOCTOR_OK+=1))
  echo -e "  ${C_GREEN}✓${C_RESET} $*"
}

doctor_warn() {
  ((DOCTOR_WARN+=1))
  echo -e "  ${C_YELLOW}!${C_RESET} $*"
}

doctor_fail() {
  ((DOCTOR_FAIL+=1))
  echo -e "  ${C_RED}✗${C_RESET} $*"
}

doctor_file_permission() {
  local path=$1 expected=$2 label=$3 mode
  if [[ ! -e "$path" ]]; then
    doctor_warn "$label 不存在：$path"
    return 0
  fi
  mode=$(stat -c '%a' "$path" 2>/dev/null || echo unknown)
  if [[ "$mode" == "$expected" ]]; then
    doctor_ok "$label 权限 $mode"
  else
    doctor_warn "$label 权限为 $mode，建议为 $expected"
  fi
}

doctor_check_core() {
  headmsg "核心服务"
  if have sing-box; then
    doctor_ok "$(sing-box version 2>/dev/null | head -n1 || echo sing-box 已安装)"
  else
    doctor_fail "sing-box 未安装"
    return 0
  fi

  if systemctl is-active --quiet sing-box 2>/dev/null; then
    doctor_ok "sing-box 服务 active"
  else
    doctor_fail "sing-box 服务不是 active"
  fi

  if systemctl is-enabled --quiet sing-box 2>/dev/null; then
    doctor_ok "sing-box 已设置开机启动"
  else
    doctor_warn "sing-box 未设置开机启动"
  fi

  if [[ -f "$CONFIG_FILE" ]] && sing-box check -c "$CONFIG_FILE" >/dev/null 2>&1; then
    doctor_ok "配置通过 sing-box check"
  else
    doctor_fail "配置缺失或 sing-box check 失败"
  fi

  if singbox_can_reload; then
    doctor_ok "systemd 支持 SIGHUP reload"
  else
    doctor_warn "当前 systemd unit 不支持 reload，变更时会使用 restart"
  fi
}

doctor_check_state() {
  echo
  headmsg "状态与配置一致性"
  if jq -e '.version and (.nodes | type=="object")' "$STATE_FILE" >/dev/null 2>&1; then
    doctor_ok "state.json 结构有效"
  else
    doctor_fail "state.json 损坏或结构无效"
    return 0
  fi

  local key tag state_port config_port found=0
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    if ! tag=$(node_tag_for_key "$key" 2>/dev/null); then
      doctor_warn "未知管理节点 key：$key"
      continue
    fi
    state_port=$(jq -r --arg k "$key" '.nodes[$k].port // empty' "$STATE_FILE")
    config_port=$(jq -r --arg tag "$tag" '.inbounds[]? | select(.tag==$tag) | .listen_port // empty' "$CONFIG_FILE" 2>/dev/null | head -n1)
    if [[ -z "$config_port" ]]; then
      doctor_fail "${key}: state 有记录，但 config 缺少入站 ${tag}"
    elif [[ "$state_port" != "$config_port" ]]; then
      doctor_fail "${key}: 端口漂移 state=${state_port} / config=${config_port}"
    else
      doctor_ok "${key}: state/config 同步，端口 ${state_port}"
    fi
    found=1
  done < <(jq -r '.nodes | keys[]' "$STATE_FILE" 2>/dev/null)
  (( found == 1 )) || doctor_warn "当前没有脚本管理节点"
}

doctor_check_listeners() {
  echo
  headmsg "监听端口"
  local key p fw missing
  while IFS=$'\t' read -r key p fw; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    missing=0
    case "$fw" in
      tcp)
        ss -H -lnt "sport = :$p" 2>/dev/null | grep -q . || missing=1
        ;;
      udp)
        ss -H -lnu "sport = :$p" 2>/dev/null | grep -q . || missing=1
        ;;
      both)
        ss -H -lnt "sport = :$p" 2>/dev/null | grep -q . || missing=1
        ss -H -lnu "sport = :$p" 2>/dev/null | grep -q . || missing=1
        ;;
    esac
    if (( missing == 0 )); then
      doctor_ok "${key}: ${fw^^}/${p} 监听正常"
    else
      doctor_warn "${key}: 预期 ${fw^^}/${p}，但未观察到完整监听"
    fi
  done < <(jq -r '.nodes | to_entries[] | [.key, (.value.port // ""), (.value.firewall // "")] | @tsv' "$STATE_FILE" 2>/dev/null)
}

doctor_check_firewall() {
  echo
  headmsg "防火墙"
  if ! have ufw; then
    doctor_warn "UFW 未安装；如果使用云防火墙，请自行确认端口"
    return 0
  fi
  if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    doctor_warn "UFW 未启用"
    return 0
  fi
  doctor_ok "UFW active"

  local status key p fw
  status=$(ufw status 2>/dev/null || true)
  while IFS=$'\t' read -r key p fw; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    case "$fw" in
      tcp)
        grep -Eq "(^|[[:space:]])${p}/tcp([[:space:]]|$)" <<< "$status" \
          && doctor_ok "${key}: UFW 包含 TCP/${p}" \
          || doctor_warn "${key}: 未明确找到 TCP/${p} UFW 规则"
        ;;
      udp)
        grep -Eq "(^|[[:space:]])${p}/udp([[:space:]]|$)" <<< "$status" \
          && doctor_ok "${key}: UFW 包含 UDP/${p}" \
          || doctor_warn "${key}: 未明确找到 UDP/${p} UFW 规则"
        ;;
      both)
        if grep -Eq "(^|[[:space:]])${p}/tcp([[:space:]]|$)" <<< "$status" \
            && grep -Eq "(^|[[:space:]])${p}/udp([[:space:]]|$)" <<< "$status"; then
          doctor_ok "${key}: UFW 同时包含 TCP/UDP/${p}"
        else
          doctor_fail "${key}: TCP/UDP/${p} 至少缺少一条 UFW 规则"
        fi
        ;;
    esac
  done < <(jq -r '.nodes | to_entries[] | [.key, (.value.port // ""), (.value.firewall // "")] | @tsv' "$STATE_FILE" 2>/dev/null)

  if hy2_hop_enabled; then
    local range
    range=$(jq -r '.nodes.hy2.port_hopping.range' "$STATE_FILE")
    grep -Fq "${range}/udp" <<< "$status" \
      && doctor_ok "HY2 跳跃范围 UDP/${range} 已加入 UFW" \
      || doctor_warn "HY2 跳跃范围 UDP/${range} 未明确出现在 UFW"
  fi
}

doctor_check_tls() {
  echo
  headmsg "TLS 证书"
  local key cert mode days end_epoch now found=0
  now=$(date +%s)
  while IFS=$'\t' read -r key cert mode; do
    [[ -n "$cert" ]] || continue
    found=1
    if [[ ! -r "$cert" ]]; then
      doctor_fail "${key}: 证书不可读：$cert"
      continue
    fi
    end_epoch=$(date -d "$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2-)" +%s 2>/dev/null || echo 0)
    if (( end_epoch <= 0 )); then
      doctor_warn "${key}: 无法解析证书到期时间"
      continue
    fi
    days=$(( (end_epoch - now) / 86400 ))
    if (( days < 0 )); then
      doctor_fail "${key}: 证书已过期"
    elif (( days < 15 )); then
      doctor_warn "${key}: 证书约 ${days} 天后到期 (${mode})"
    else
      doctor_ok "${key}: 证书剩余约 ${days} 天 (${mode})"
    fi
  done < <(jq -r '.nodes | to_entries[] | select(.value.tls_enabled==true and (.value.certificate_path // "") != "") | [.key,.value.certificate_path,(.value.certificate_mode // "unknown")] | @tsv' "$STATE_FILE" 2>/dev/null)
  (( found == 1 )) || doctor_warn "当前没有脚本管理的普通 TLS 证书节点"
}

doctor_check_hopping() {
  echo
  headmsg "HY2 端口跳跃"
  if ! jq -e '.nodes.hy2 != null' "$STATE_FILE" >/dev/null 2>&1; then
    doctor_warn "未部署 Hysteria2"
    return 0
  fi
  if ! hy2_hop_enabled; then
    doctor_ok "端口跳跃关闭（推荐默认）"
    return 0
  fi
  local range target
  range=$(jq -r '.nodes.hy2.port_hopping.range' "$STATE_FILE")
  target=$(jq -r '.nodes.hy2.port' "$STATE_FILE")
  if systemctl is-active --quiet "$HY2_HOP_SERVICE" 2>/dev/null; then
    doctor_ok "端口跳跃服务 active：${range} → ${target}"
  else
    doctor_fail "state 显示已启用，但 ${HY2_HOP_SERVICE} 未运行"
  fi
  if have nft && nft list table inet "$HY2_HOP_TABLE" >/dev/null 2>&1; then
    doctor_ok "nftables 跳跃表存在"
  else
    doctor_fail "nftables 跳跃规则缺失"
  fi
}

doctor_check_subscription() {
  echo
  headmsg "HTTPS 私有订阅"
  if [[ $(jq -r '.subscription.enabled // false' "$STATE_FILE" 2>/dev/null) != true ]]; then
    doctor_ok "私有订阅关闭"
    return 0
  fi
  if systemctl is-active --quiet "${SUBSCRIPTION_SERVICE:-sing-box-oneclick-subscription.service}" 2>/dev/null; then
    doctor_ok "HTTPS 私有订阅服务 active"
  else
    doctor_fail "state 显示订阅开启，但订阅服务未运行"
  fi
  local token
  token=$(jq -r '.subscription.token // empty' "$STATE_FILE" 2>/dev/null)
  if (( ${#token} >= 48 )); then
    doctor_ok "订阅 Token 长度充足"
  else
    doctor_warn "订阅 Token 为空或长度偏短"
  fi
}

doctor_check_integrity() {
  echo
  headmsg "管理器完整性"
  doctor_file_permission "$CONFIG_FILE" 600 "config.json"
  doctor_file_permission "$STATE_FILE" 600 "state.json"
  [[ -e "$NODE_INFO" ]] && doctor_file_permission "$NODE_INFO" 600 "节点信息文件"

  if [[ -r "$MANAGER_DIR/CHECKSUMS.sha256" ]]; then
    if (cd "$MANAGER_DIR" && sha256sum -c CHECKSUMS.sha256 >/dev/null 2>&1); then
      doctor_ok "管理器 SHA256 校验通过"
    else
      doctor_fail "管理器 SHA256 校验失败；建议运行 sb update"
    fi
  else
    doctor_warn "当前安装来自旧版更新机制，尚无本地 CHECKSUMS.sha256"
  fi

  if [[ -r "$MANAGER_DIR/SOURCE_COMMIT" ]]; then
    doctor_ok "安装来源已锁定 commit：$(cut -c1-12 "$MANAGER_DIR/SOURCE_COMMIT")"
  else
    doctor_warn "没有 SOURCE_COMMIT（旧版安装升级后会自动补齐）"
  fi
}

doctor_check_system() {
  echo
  headmsg "系统基础"
  doctor_ok "系统：${PRETTY_NAME:-unknown}"
  if [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo false) == true ]]; then
    doctor_ok "系统时间已同步"
  else
    doctor_warn "系统时间未确认同步；TLS/Reality 对时间较敏感"
  fi
  if ip -4 route show default 2>/dev/null | grep -q .; then doctor_ok "IPv4 默认路由存在"; else doctor_warn "没有 IPv4 默认路由"; fi
  if ip -6 route show default 2>/dev/null | grep -q .; then doctor_ok "IPv6 默认路由存在"; else doctor_warn "没有 IPv6 默认路由"; fi
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true) == bbr ]]; then
    doctor_ok "TCP BBR 已启用"
  else
    doctor_warn "TCP BBR 未启用（不影响 HY2/TUIC 的 QUIC/UDP）"
  fi
}

run_doctor() {
  ensure_state
  DOCTOR_OK=0
  DOCTOR_WARN=0
  DOCTOR_FAIL=0
  echo
  ui_banner
  headmsg "sb doctor · 只读一键体检"
  note "不会自动改配置、重启服务或修改防火墙；适合先检查，再按提示处理。"
  echo

  doctor_check_system
  echo
  doctor_check_core
  doctor_check_state
  doctor_check_listeners
  doctor_check_firewall
  doctor_check_tls
  doctor_check_hopping
  doctor_check_subscription
  doctor_check_integrity

  echo
  ui_rule
  echo -e "  ${C_GREEN}通过 ${DOCTOR_OK}${C_RESET}    ${C_YELLOW}提醒 ${DOCTOR_WARN}${C_RESET}    ${C_RED}问题 ${DOCTOR_FAIL}${C_RESET}"
  if (( DOCTOR_FAIL > 0 )); then
    warn "发现需要处理的问题。建议先备份，再按上方红色项目逐项修复。"
    return 1
  elif (( DOCTOR_WARN > 0 )); then
    note "没有发现致命问题；黄色项目多数是可选优化或环境提示。"
  else
    info "体检全部通过。"
  fi
}
