#!/usr/bin/env bash
# shellcheck shell=bash

is_uuid_value() {
  [[ ${1:-} =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

node_tag_for_key() {
  case "$1" in
    reality) printf '%s' 'vless-reality-in' ;;
    hy2) printf '%s' 'hysteria2-in' ;;
    tuic) printf '%s' 'tuic-in' ;;
    ws) printf '%s' 'vless-ws-tls-in' ;;
    *) return 1 ;;
  esac
}

node_proto_for_key() {
  case "$1" in
    reality|ws) printf '%s' 'tcp' ;;
    hy2|tuic) printf '%s' 'udp' ;;
    *) return 1 ;;
  esac
}

node_label_for_key() {
  case "$1" in
    reality) printf '%s' 'VLESS Reality' ;;
    hy2) printf '%s' 'Hysteria2' ;;
    tuic) printf '%s' 'TUIC v5' ;;
    ws) printf '%s' 'Cloudflare VLESS WS' ;;
    *) printf '%s' "$1" ;;
  esac
}

select_managed_node_for_edit() {
  ensure_state
  local keys=() labels=() idx choice

  jq -e '.nodes.reality != null' "$STATE_FILE" >/dev/null 2>&1 && { keys+=(reality); labels+=("VLESS Reality"); }
  jq -e '.nodes.hy2 != null' "$STATE_FILE" >/dev/null 2>&1 && { keys+=(hy2); labels+=("Hysteria2"); }
  jq -e '.nodes.tuic != null' "$STATE_FILE" >/dev/null 2>&1 && { keys+=(tuic); labels+=("TUIC v5"); }
  jq -e '.nodes.ws != null' "$STATE_FILE" >/dev/null 2>&1 && { keys+=(ws); labels+=("Cloudflare VLESS WS"); }

  if (( ${#keys[@]} == 0 )); then
    warn "当前没有脚本管理的节点。"
    return 1
  fi

  echo
  headmsg "选择节点"
  for idx in "${!keys[@]}"; do
    ui_item "$((idx+1))" "${labels[$idx]}"
  done
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择节点 › " choice
  [[ "$choice" == 0 ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || { warn "无效选择。"; return 1; }
  (( choice >= 1 && choice <= ${#keys[@]} )) || { warn "无效选择。"; return 1; }

  SELECTED_NODE_KEY=${keys[$((choice-1))]}
  return 0
}

config_patch_apply() {
  local label=$1
  shift
  [[ -f "$CONFIG_FILE" ]] || die "当前没有 sing-box 配置。"

  local candidate
  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  jq "$@" "$CONFIG_FILE" > "$candidate" || die "生成候选配置失败。"
  apply_candidate "$candidate" "$label"
}

state_patch_apply() {
  local key=$1
  shift
  local tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg k "$key" "$@" "$STATE_FILE" > "$tmp" || die "更新节点状态失败。"
  install -m 600 "$tmp" "$STATE_FILE"
  rebuild_node_uri "$key" || true
  render_node_info
}

rebuild_node_uri() {
  local key=$1 address domain port name name_enc uuid password obfs congestion path host tls insecure uri sni pub sid
  address=$(jq -r --arg k "$key" '.nodes[$k].address // .nodes[$k].domain // empty' "$STATE_FILE")
  domain=$(jq -r --arg k "$key" '.nodes[$k].domain // empty' "$STATE_FILE")
  port=$(jq -r --arg k "$key" '.nodes[$k].port // empty' "$STATE_FILE")
  name=$(jq -r --arg k "$key" '.nodes[$k].name // $k' "$STATE_FILE")
  name_enc=$(uri_encode "$name")
  host=$(uri_host "$address")
  insecure=$(jq -r --arg k "$key" '.nodes[$k].insecure // false' "$STATE_FILE")

  case "$key" in
    reality)
      uuid=$(jq -r '.nodes.reality.uuid' "$STATE_FILE")
      sni=$(jq -r '.nodes.reality.reality_sni' "$STATE_FILE")
      pub=$(jq -r '.nodes.reality.public_key' "$STATE_FILE")
      sid=$(jq -r '.nodes.reality.short_id' "$STATE_FILE")
      uri="vless://${uuid}@${host}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(uri_encode "$sni")&fp=chrome&pbk=$(uri_encode "$pub")&sid=$(uri_encode "$sid")&type=tcp"
      ;;
    hy2)
      password=$(jq -r '.nodes.hy2.password' "$STATE_FILE")
      obfs=$(jq -r '.nodes.hy2.obfs_password' "$STATE_FILE")
      uri="hysteria2://$(uri_encode "$password")@${host}:${port}?sni=$(uri_encode "$domain")&obfs=salamander&obfs-password=$(uri_encode "$obfs")"
      [[ "$insecure" == true ]] && uri+="&insecure=1"
      ;;
    tuic)
      uuid=$(jq -r '.nodes.tuic.uuid' "$STATE_FILE")
      password=$(jq -r '.nodes.tuic.password' "$STATE_FILE")
      congestion=$(jq -r '.nodes.tuic.congestion_control // "bbr"' "$STATE_FILE")
      uri="tuic://${uuid}:$(uri_encode "$password")@${host}:${port}?sni=$(uri_encode "$domain")&alpn=h3&congestion_control=$(uri_encode "$congestion")&udp_relay_mode=native&zero_rtt_handshake=0"
      [[ "$insecure" == true ]] && uri+="&allow_insecure=1"
      ;;
    ws)
      uuid=$(jq -r '.nodes.ws.uuid' "$STATE_FILE")
      path=$(jq -r '.nodes.ws.path' "$STATE_FILE")
      tls=$(jq -r '.nodes.ws.tls_enabled // true' "$STATE_FILE")
      if [[ "$tls" == true ]]; then
        uri="vless://${uuid}@${host}:${port}?encryption=none&security=tls&sni=$(uri_encode "$domain")&type=ws&host=$(uri_encode "$domain")&path=$(uri_encode "$path")"
      else
        uri="vless://${uuid}@${host}:${port}?encryption=none&security=none&type=ws&host=$(uri_encode "$domain")&path=$(uri_encode "$path")"
      fi
      ;;
    *) return 1 ;;
  esac

  uri+="#${name_enc}"
  local tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg k "$key" --arg uri "$uri" '.nodes[$k].uri=$uri' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  return 0
}

post_parameter_change() {
  local key=$1 old_port=${2:-} new_port=${3:-}
  rebuild_node_uri "$key" || true
  render_node_info

  if [[ -n "$new_port" && "$new_port" != "$old_port" ]]; then
    local proto
    proto=$(node_proto_for_key "$key")
    if [[ "$key" == ws ]] && have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
      ufw_allow_cloudflare_only "$new_port"
    else
      allow_if_ufw_active "$new_port" "$proto"
    fi
    if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
      note "为避免误删其他服务规则，旧端口 ${old_port}/${proto} 的 UFW 规则不会自动删除；确认不再使用后可手工清理。"
    fi
  fi

  if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then
    refresh_client_exports_if_present || true
  fi
}

edit_client_address() {
  local key=$1 current new mode
  current=$(jq -r --arg k "$key" '.nodes[$k].address // empty' "$STATE_FILE")
  read -r -p "节点地址 [${current}]: " new
  new=${new:-$current}
  [[ -n "$new" ]] || die "节点地址不能为空。"

  case "$key" in
    ws) mode=cloudflare ;;
    *) mode=direct ;;
  esac

  if is_hostname "$new"; then
    check_domain "$new" "$mode"
  elif ! is_ipv4 "$new" && ! is_ipv6 "$new"; then
    die "节点地址必须是有效域名或 IP。"
  fi

  [[ "$new" == "$current" ]] && { note "地址未变化。"; return 0; }
  backup_all
  state_patch_apply "$key" --arg value "$new" '.nodes[$k].address=$value'
  post_parameter_change "$key"
  info "节点地址已原地修改；服务端监听参数未改变。"
}

edit_node_port() {
  local key=$1 tag proto old new tls
  tag=$(node_tag_for_key "$key")
  proto=$(node_proto_for_key "$key")
  old=$(jq -r --arg k "$key" '.nodes[$k].port' "$STATE_FILE")

  read -r -p "新端口 [${old}]: " new
  new=${new:-$old}
  validate_port "$new" || die "端口必须为 1-65535。"
  [[ "$new" == "$old" ]] && { note "端口未变化。"; return 0; }

  if [[ "$key" == ws ]]; then
    tls=$(jq -r '.nodes.ws.tls_enabled // true' "$STATE_FILE")
    if [[ "$tls" == true ]]; then
      cloudflare_https_port "$new" || die "WS 开启 TLS 时 Cloudflare 端口仅支持 443/2053/2083/2087/2096/8443。"
    else
      cloudflare_http_port "$new" || die "WS 关闭 TLS 时 Cloudflare 端口仅支持 80/8080/8880/2052/2082/2086/2095。"
    fi
  fi

  if port_in_use_by_other "$proto" "$new" "$tag"; then
    warn "${proto^^}/$new 已被占用："
    show_port_owner "$proto" "$new"
    die "请选择其他端口。"
  fi

  config_patch_apply "修改 $(node_label_for_key "$key") 端口" \
    --arg tag "$tag" --argjson port "$new" \
    '.inbounds |= map(if .tag==$tag then .listen_port=$port else . end)'
  state_patch_apply "$key" --argjson port "$new" '.nodes[$k].port=$port'
  post_parameter_change "$key" "$old" "$new"
  info "端口已从 $old 原地修改为 $new。"
}

edit_reality_sni() {
  local current new
  current=$(jq -r '.nodes.reality.reality_sni' "$STATE_FILE")
  read -r -p "Reality SNI [${current}]: " new
  new=${new:-$current}
  is_hostname "$new" || die "Reality SNI 必须是有效域名。"
  [[ "$new" == "$current" ]] && { note "SNI 未变化。"; return 0; }
  check_reality_target "$new"

  config_patch_apply "修改 Reality SNI" \
    --arg tag "vless-reality-in" --arg sni "$new" \
    '.inbounds |= map(if .tag==$tag then .tls.server_name=$sni | .tls.reality.handshake.server=$sni else . end)'
  state_patch_apply reality --arg value "$new" '.nodes[$k].reality_sni=$value'
  post_parameter_change reality
  info "Reality SNI 已原地修改。"
}

edit_reality_uuid() {
  local current new
  current=$(jq -r '.nodes.reality.uuid' "$STATE_FILE")
  read -r -p "新 UUID（留空自动生成；输入 keep 保持当前）: " new
  if [[ ${new,,} == keep ]]; then note "UUID 未变化。"; return 0; fi
  new=${new:-$(sing-box generate uuid)}
  is_uuid_value "$new" || die "UUID 格式无效。"
  [[ "$new" == "$current" ]] && { note "UUID 未变化。"; return 0; }

  config_patch_apply "修改 Reality UUID" \
    --arg tag "vless-reality-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .users[0].uuid=$value else . end)'
  state_patch_apply reality --arg value "$new" '.nodes[$k].uuid=$value'
  post_parameter_change reality
  info "Reality UUID 已原地修改。"
}

edit_reality_short_id() {
  local current new
  current=$(jq -r '.nodes.reality.short_id' "$STATE_FILE")
  read -r -p "新 Short ID（1-16 位十六进制；留空自动生成）: " new
  new=${new:-$(sing-box generate rand --hex 8)}
  [[ "$new" =~ ^[0-9A-Fa-f]{1,16}$ ]] || die "Short ID 必须是 1-16 位十六进制。"
  [[ "$new" == "$current" ]] && { note "Short ID 未变化。"; return 0; }

  config_patch_apply "修改 Reality Short ID" \
    --arg tag "vless-reality-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .tls.reality.short_id=[$value] else . end)'
  state_patch_apply reality --arg value "$new" '.nodes[$k].short_id=$value'
  post_parameter_change reality
  info "Reality Short ID 已原地修改。"
}

edit_hy2_password() {
  local new
  read -r -p "新 HY2 密码（留空自动生成）: " new
  new=${new:-$(random_hex 24)}
  [[ -n "$new" ]] || die "密码不能为空。"

  config_patch_apply "修改 Hysteria2 密码" \
    --arg tag "hysteria2-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .users[0].password=$value else . end)'
  state_patch_apply hy2 --arg value "$new" '.nodes[$k].password=$value'
  post_parameter_change hy2
  info "Hysteria2 密码已原地修改。"
}

edit_hy2_obfs_password() {
  local new
  read -r -p "新 Salamander 混淆密码（留空自动生成）: " new
  new=${new:-$(random_hex 20)}
  [[ -n "$new" ]] || die "混淆密码不能为空。"

  config_patch_apply "修改 Hysteria2 混淆密码" \
    --arg tag "hysteria2-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .obfs={type:"salamander",password:$value} else . end)'
  state_patch_apply hy2 --arg value "$new" '.nodes[$k].obfs_password=$value'
  post_parameter_change hy2
  info "Hysteria2 混淆密码已原地修改。"
}

edit_hy2_masquerade() {
  local current new
  current=$(jq -r '.inbounds[]? | select(.tag=="hysteria2-in") | .masquerade // "https://www.microsoft.com"' "$CONFIG_FILE" | head -n1)
  read -r -p "伪装网站 [${current}]: " new
  new=${new:-$current}
  [[ "$new" =~ ^https?:// ]] || die "伪装网站必须以 http:// 或 https:// 开头。"
  [[ "$new" == "$current" ]] && { note "伪装网站未变化。"; return 0; }

  config_patch_apply "修改 Hysteria2 伪装网站" \
    --arg tag "hysteria2-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .masquerade=$value else . end)'
  state_patch_apply hy2 --arg value "$new" '.nodes[$k].masquerade=$value'
  post_parameter_change hy2
  info "Hysteria2 伪装网站已原地修改。"
}

edit_tuic_password() {
  local new
  read -r -p "新 TUIC 密码（留空自动生成）: " new
  new=${new:-$(random_hex 24)}
  [[ -n "$new" ]] || die "密码不能为空。"

  config_patch_apply "修改 TUIC 密码" \
    --arg tag "tuic-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .users[0].password=$value else . end)'
  state_patch_apply tuic --arg value "$new" '.nodes[$k].password=$value'
  post_parameter_change tuic
  info "TUIC 密码已原地修改。"
}

edit_tuic_uuid() {
  local new
  read -r -p "新 TUIC UUID（留空自动生成）: " new
  new=${new:-$(sing-box generate uuid)}
  is_uuid_value "$new" || die "UUID 格式无效。"

  config_patch_apply "修改 TUIC UUID" \
    --arg tag "tuic-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .users[0].uuid=$value else . end)'
  state_patch_apply tuic --arg value "$new" '.nodes[$k].uuid=$value'
  post_parameter_change tuic
  info "TUIC UUID 已原地修改。"
}

edit_tuic_congestion() {
  local current new
  current=$(jq -r '.nodes.tuic.congestion_control // "bbr"' "$STATE_FILE")
  read -r -p "拥塞控制 [${current}]（bbr/cubic/new_reno）: " new
  new=${new:-$current}
  new=${new,,}
  case "$new" in bbr|cubic|new_reno) ;; *) die "只允许 bbr / cubic / new_reno。" ;; esac
  [[ "$new" == "$current" ]] && { note "拥塞控制未变化。"; return 0; }

  config_patch_apply "修改 TUIC 拥塞控制" \
    --arg tag "tuic-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .congestion_control=$value else . end)'
  state_patch_apply tuic --arg value "$new" '.nodes[$k].congestion_control=$value'
  post_parameter_change tuic
  info "TUIC 拥塞控制已切换为 $new。"
}

edit_ws_path() {
  local current new
  current=$(jq -r '.nodes.ws.path' "$STATE_FILE")
  read -r -p "WebSocket Path [${current}]: " new
  new=${new:-$current}
  [[ "$new" == /* ]] || new="/$new"
  [[ "$new" == "$current" ]] && { note "Path 未变化。"; return 0; }

  config_patch_apply "修改 WebSocket Path" \
    --arg tag "vless-ws-tls-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .transport.path=$value else . end)'
  state_patch_apply ws --arg value "$new" '.nodes[$k].path=$value'
  post_parameter_change ws
  info "WebSocket Path 已原地修改。"
}

edit_ws_uuid() {
  local new
  read -r -p "新 WS UUID（留空自动生成）: " new
  new=${new:-$(sing-box generate uuid)}
  is_uuid_value "$new" || die "UUID 格式无效。"

  config_patch_apply "修改 WebSocket UUID" \
    --arg tag "vless-ws-tls-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .users[0].uuid=$value else . end)'
  state_patch_apply ws --arg value "$new" '.nodes[$k].uuid=$value'
  post_parameter_change ws
  info "WebSocket UUID 已原地修改。"
}

edit_reality_menu() {
  echo
  headmsg "VLESS Reality · 原地修改"
  ui_item 1 "节点地址（仅客户端连接地址）"
  ui_item 2 "监听端口"
  ui_item 3 "Reality SNI / 握手域名"
  ui_item 4 "UUID"
  ui_item 5 "Short ID"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择参数 › " n
  case "$n" in
    1) edit_client_address reality ;;
    2) edit_node_port reality ;;
    3) edit_reality_sni ;;
    4) edit_reality_uuid ;;
    5) edit_reality_short_id ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

edit_hy2_menu() {
  echo
  headmsg "Hysteria2 · 原地修改"
  ui_item 1 "节点地址（域名 / IP）"
  ui_item 2 "UDP 监听端口"
  ui_item 3 "认证密码"
  ui_item 4 "Salamander 混淆密码"
  ui_item 5 "伪装网站"
  ui_item 6 "TLS SNI / 证书模式（进入证书管理）"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择参数 › " n
  case "$n" in
    1) edit_client_address hy2 ;;
    2) edit_node_port hy2 ;;
    3) edit_hy2_password ;;
    4) edit_hy2_obfs_password ;;
    5) edit_hy2_masquerade ;;
    6) switch_certificate_tls ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

edit_tuic_menu() {
  echo
  headmsg "TUIC v5 · 原地修改"
  ui_item 1 "节点地址（域名 / IP）"
  ui_item 2 "UDP 监听端口"
  ui_item 3 "密码"
  ui_item 4 "UUID"
  ui_item 5 "QUIC 拥塞控制（bbr / cubic / new_reno）"
  ui_item 6 "TLS SNI / 证书模式（进入证书管理）"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择参数 › " n
  case "$n" in
    1) edit_client_address tuic ;;
    2) edit_node_port tuic ;;
    3) edit_tuic_password ;;
    4) edit_tuic_uuid ;;
    5) edit_tuic_congestion ;;
    6) switch_certificate_tls ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

edit_ws_menu() {
  echo
  headmsg "Cloudflare VLESS WS · 原地修改"
  ui_item 1 "TCP 监听端口"
  ui_item 2 "WebSocket Path"
  ui_item 3 "UUID"
  ui_item 4 "TLS / 证书模式"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择参数 › " n
  case "$n" in
    1) edit_node_port ws ;;
    2) edit_ws_path ;;
    3) edit_ws_uuid ;;
    4) switch_certificate_tls ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

edit_node_parameters() {
  ensure_singbox
  ensure_state

  echo
  headmsg "节点参数原地修改"
  note "只修改所选字段；其他 UUID、密钥、密码和路径默认保持不变。"
  note "服务端参数变更继续执行 sing-box check、备份、热重载/重启兜底和失败回滚。"
  ui_node_overview

  select_managed_node_for_edit || return 0
  case "$SELECTED_NODE_KEY" in
    reality) edit_reality_menu ;;
    hy2) edit_hy2_menu ;;
    tuic) edit_tuic_menu ;;
    ws) edit_ws_menu ;;
  esac
}
