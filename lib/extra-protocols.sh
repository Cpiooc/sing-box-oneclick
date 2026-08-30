#!/usr/bin/env bash
# shellcheck shell=bash

# AnyTLS / Trojan / Shadowsocks support plus v1.6 management integrations.
# Loaded after editor.sh so selected helper functions can extend the original
# four-protocol manager without duplicating the older modules.

singbox_version_number() {
  sing-box version 2>/dev/null | awk '/sing-box version/{print $3; exit}' | sed 's/^v//'
}

version_ge() {
  local current=$1 minimum=$2
  [[ -n "$current" ]] || return 1
  printf '%s\n%s\n' "$minimum" "$current" | sort -V -C
}

require_anytls_support() {
  local current
  current=$(singbox_version_number)
  if ! version_ge "$current" "1.12.0"; then
    die "AnyTLS 需要 sing-box >= 1.12.0；当前版本：${current:-unknown}。请先运行 sb -> 23 更新 sing-box。"
  fi
}

preferred_tls_tcp_port() {
  local tag=$1 fallback=$2
  if ! port_in_use_by_other tcp 443 "$tag"; then
    printf '%s' 443
  else
    printf '%s' "$fallback"
  fi
}

ss_password_for_method() {
  local method=$1
  case "$method" in
    2022-blake3-aes-128-gcm) sing-box generate rand --base64 16 ;;
    2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) sing-box generate rand --base64 32 ;;
    *) random_hex 24 ;;
  esac
}

select_ss_method() {
  local choice=${1:-}
  if [[ -z "$choice" ]]; then
    echo
    headmsg "Shadowsocks 加密方法"
    ui_item 1 "2022-blake3-aes-128-gcm" "推荐 · 16-byte key"
    ui_item 2 "2022-blake3-aes-256-gcm" "高强度 · 32-byte key"
    ui_item 3 "2022-blake3-chacha20-poly1305" "移动端友好 · 32-byte key"
    ui_item 4 "chacha20-ietf-poly1305" "兼容性好"
    ui_item 5 "aes-256-gcm" "兼容性好"
    read -r -p "  请选择 [1] › " choice
    choice=${choice:-1}
  fi
  case "$choice" in
    1|2022-blake3-aes-128-gcm) SS_METHOD="2022-blake3-aes-128-gcm" ;;
    2|2022-blake3-aes-256-gcm) SS_METHOD="2022-blake3-aes-256-gcm" ;;
    3|2022-blake3-chacha20-poly1305) SS_METHOD="2022-blake3-chacha20-poly1305" ;;
    4|chacha20-ietf-poly1305) SS_METHOD="chacha20-ietf-poly1305" ;;
    5|aes-256-gcm) SS_METHOD="aes-256-gcm" ;;
    *) die "不支持的 Shadowsocks 加密方法。" ;;
  esac
}

deploy_anytls() {
  ensure_singbox
  require_anytls_support
  install_deps
  sync_time

  local tag="anytls-in" node_addr server_name port default_port password host name name_enc uri inbound candidate state insecure_json

  echo
  headmsg "部署 / 重建 AnyTLS"
  note "AnyTLS 使用 TCP + TLS；当前实现使用 sing-box 原生 AnyTLS，不叠加 Reality。"
  note "普通 Cloudflare 橙云不能直接代理此 TCP 入站；请使用 DNS only（灰云）或直接 IP。"

  read -r -p "AnyTLS 节点地址（域名或 VPS IP）: " node_addr
  [[ -n "$node_addr" ]] || die "节点地址不能为空。"
  if is_hostname "$node_addr"; then
    check_domain "$node_addr" direct
  elif ! is_ipv4 "$node_addr" && ! is_ipv6 "$node_addr"; then
    die "节点地址必须是有效域名或 IP。"
  fi

  read -r -p "TLS SNI / 证书名称 [${node_addr}]: " server_name
  server_name=${server_name:-$node_addr}
  if ! is_hostname "$server_name" && ! is_ipv4 "$server_name" && ! is_ipv6 "$server_name"; then
    die "TLS 名称必须是有效域名或 IP。"
  fi
  select_certificate_mode "$server_name" false

  default_port=$(preferred_tls_tcp_port "$tag" 8444)
  [[ "$default_port" != 443 ]] && note "TCP/443 已占用，AnyTLS 默认改用 TCP/${default_port}。"
  read -r -p "TCP 监听端口 [${default_port}]: " port
  port=${port:-$default_port}
  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other tcp "$port" "$tag"; then
    show_port_owner tcp "$port"
    die "TCP/$port 已被其他服务占用。"
  fi

  password=$(random_hex 24)
  inbound=$(jq -n \
    --arg password "$password" --arg server_name "$server_name" \
    --arg cert "$CERT_PATH" --arg key "$KEY_PATH" --argjson port "$port" \
    '{type:"anytls",tag:"anytls-in",listen:"::",listen_port:$port,users:[{name:"main",password:$password}],tls:{enabled:true,server_name:$server_name,certificate_path:$cert,key_path:$key}}')

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "AnyTLS"

  host=$(uri_host "$node_addr")
  name="sing-box-AnyTLS"
  name_enc=$(uri_encode "$name")
  uri="anytls://$(uri_encode "$password")@${host}:${port}?security=tls&sni=$(uri_encode "$server_name")"
  [[ "$CERT_CLIENT_INSECURE" == true ]] && uri+="&insecure=1"
  uri+="#${name_enc}"
  insecure_json=false
  [[ "$CERT_CLIENT_INSECURE" == true ]] && insecure_json=true

  state=$(jq -n \
    --arg name "$name" --arg address "$node_addr" --arg domain "$server_name" \
    --argjson port "$port" --arg password "$password" --arg uri "$uri" \
    --arg cert_mode "$CERT_MODE" --arg cert_path "$CERT_PATH" --arg key_path "$KEY_PATH" \
    --argjson insecure "$insecure_json" \
    '{name:$name,type:"AnyTLS",address:$address,domain:$domain,port:$port,password:$password,uri:$uri,firewall:"tcp",certificate:true,tls_enabled:true,certificate_mode:$cert_mode,certificate_path:$cert_path,key_path:$key_path,insecure:$insecure}')
  state_set_node anytls "$state"
  allow_if_ufw_active "$port" tcp
  [[ "$CERT_CLIENT_INSECURE" == true ]] && warn "当前证书需要客户端跳过验证；长期使用建议切换到受信任证书。"
  echo
  show_nodes
}

deploy_trojan() {
  ensure_singbox
  install_deps
  sync_time

  local tag="trojan-in" node_addr server_name port default_port password host name name_enc uri inbound candidate state insecure_json

  echo
  headmsg "部署 / 重建 Trojan"
  note "Trojan 使用 TCP + TLS；本脚本不默认配置 HTTP fallback，减少额外监听和特征。"
  note "普通 Cloudflare 橙云不能直接代理原生 Trojan TCP；请使用 DNS only（灰云）或直接 IP。"

  read -r -p "Trojan 节点地址（域名或 VPS IP）: " node_addr
  [[ -n "$node_addr" ]] || die "节点地址不能为空。"
  if is_hostname "$node_addr"; then
    check_domain "$node_addr" direct
  elif ! is_ipv4 "$node_addr" && ! is_ipv6 "$node_addr"; then
    die "节点地址必须是有效域名或 IP。"
  fi

  read -r -p "TLS SNI / 证书名称 [${node_addr}]: " server_name
  server_name=${server_name:-$node_addr}
  if ! is_hostname "$server_name" && ! is_ipv4 "$server_name" && ! is_ipv6 "$server_name"; then
    die "TLS 名称必须是有效域名或 IP。"
  fi
  select_certificate_mode "$server_name" false

  default_port=$(preferred_tls_tcp_port "$tag" 8445)
  [[ "$default_port" != 443 ]] && note "TCP/443 已占用，Trojan 默认改用 TCP/${default_port}。"
  read -r -p "TCP 监听端口 [${default_port}]: " port
  port=${port:-$default_port}
  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other tcp "$port" "$tag"; then
    show_port_owner tcp "$port"
    die "TCP/$port 已被其他服务占用。"
  fi

  password=$(random_hex 24)
  inbound=$(jq -n \
    --arg password "$password" --arg server_name "$server_name" \
    --arg cert "$CERT_PATH" --arg key "$KEY_PATH" --argjson port "$port" \
    '{type:"trojan",tag:"trojan-in",listen:"::",listen_port:$port,users:[{name:"main",password:$password}],tls:{enabled:true,server_name:$server_name,certificate_path:$cert,key_path:$key}}')

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "Trojan"

  host=$(uri_host "$node_addr")
  name="sing-box-Trojan"
  name_enc=$(uri_encode "$name")
  uri="trojan://$(uri_encode "$password")@${host}:${port}?security=tls&sni=$(uri_encode "$server_name")"
  [[ "$CERT_CLIENT_INSECURE" == true ]] && uri+="&allowInsecure=1"
  uri+="#${name_enc}"
  insecure_json=false
  [[ "$CERT_CLIENT_INSECURE" == true ]] && insecure_json=true

  state=$(jq -n \
    --arg name "$name" --arg address "$node_addr" --arg domain "$server_name" \
    --argjson port "$port" --arg password "$password" --arg uri "$uri" \
    --arg cert_mode "$CERT_MODE" --arg cert_path "$CERT_PATH" --arg key_path "$KEY_PATH" \
    --argjson insecure "$insecure_json" \
    '{name:$name,type:"Trojan",address:$address,domain:$domain,port:$port,password:$password,uri:$uri,firewall:"tcp",certificate:true,tls_enabled:true,certificate_mode:$cert_mode,certificate_path:$cert_path,key_path:$key_path,insecure:$insecure}')
  state_set_node trojan "$state"
  allow_if_ufw_active "$port" tcp
  [[ "$CERT_CLIENT_INSECURE" == true ]] && warn "当前证书需要客户端跳过验证；长期使用建议切换到受信任证书。"
  echo
  show_nodes
}

deploy_shadowsocks() {
  ensure_singbox
  install_deps
  sync_time

  local tag="shadowsocks-in" node_addr port method password host name name_enc uri inbound candidate state

  echo
  headmsg "部署 / 重建 Shadowsocks"
  note "默认同时启用 TCP + UDP；推荐使用 Shadowsocks 2022-BLAKE3。"
  note "Shadowsocks 本身不提供普通 TLS 证书层，适合作为兼容/备用入口。"

  read -r -p "Shadowsocks 节点地址（域名或 VPS IP）: " node_addr
  [[ -n "$node_addr" ]] || die "节点地址不能为空。"
  if is_hostname "$node_addr"; then
    check_domain "$node_addr" direct
  elif ! is_ipv4 "$node_addr" && ! is_ipv6 "$node_addr"; then
    die "节点地址必须是有效域名或 IP。"
  fi

  read -r -p "TCP/UDP 监听端口 [8388]: " port
  port=${port:-8388}
  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other tcp "$port" "$tag" || port_in_use_by_other udp "$port" "$tag"; then
    warn "TCP 或 UDP/$port 已被占用："
    show_port_owner tcp "$port"
    show_port_owner udp "$port"
    die "请选择其他端口。"
  fi

  select_ss_method
  method=$SS_METHOD
  password=$(ss_password_for_method "$method")

  inbound=$(jq -n --arg method "$method" --arg password "$password" --argjson port "$port" \
    '{type:"shadowsocks",tag:"shadowsocks-in",listen:"::",listen_port:$port,method:$method,password:$password}')
  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "Shadowsocks"

  host=$(uri_host "$node_addr")
  name="sing-box-Shadowsocks"
  name_enc=$(uri_encode "$name")
  uri="ss://$(uri_encode "$method"):$(uri_encode "$password")@${host}:${port}#${name_enc}"
  state=$(jq -n \
    --arg name "$name" --arg address "$node_addr" --argjson port "$port" \
    --arg method "$method" --arg password "$password" --arg uri "$uri" \
    '{name:$name,type:"Shadowsocks",address:$address,port:$port,method:$method,password:$password,uri:$uri,firewall:"both",tls_enabled:false,certificate:false}')
  state_set_node ss "$state"

  allow_if_ufw_active "$port" tcp
  allow_if_ufw_active "$port" udp
  echo
  show_nodes
}

# Extend editor metadata for all managed protocols.
node_tag_for_key() {
  case "$1" in
    reality) printf '%s' 'vless-reality-in' ;;
    hy2) printf '%s' 'hysteria2-in' ;;
    tuic) printf '%s' 'tuic-in' ;;
    ws) printf '%s' 'vless-ws-tls-in' ;;
    anytls) printf '%s' 'anytls-in' ;;
    trojan) printf '%s' 'trojan-in' ;;
    ss) printf '%s' 'shadowsocks-in' ;;
    *) return 1 ;;
  esac
}

node_proto_for_key() {
  case "$1" in
    reality|ws|anytls|trojan|ss) printf '%s' 'tcp' ;;
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
    anytls) printf '%s' 'AnyTLS' ;;
    trojan) printf '%s' 'Trojan' ;;
    ss) printf '%s' 'Shadowsocks' ;;
    *) printf '%s' "$1" ;;
  esac
}

select_managed_node_for_edit() {
  ensure_state
  local order=(reality hy2 tuic ws anytls trojan ss) keys=() labels=() key idx choice
  for key in "${order[@]}"; do
    if jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1; then
      keys+=("$key")
      labels+=("$(node_label_for_key "$key")")
    fi
  done

  if (( ${#keys[@]} == 0 )); then
    warn "当前没有脚本管理的节点。"
    return 1
  fi

  echo
  headmsg "选择节点"
  for idx in "${!keys[@]}"; do
    ui_item "$((idx+1))" "${labels[$idx]}" "$(jq -r --arg k "${keys[$idx]}" '.nodes[$k].port // "-"' "$STATE_FILE")"
  done
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择节点 › " choice
  [[ "$choice" == 0 ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || { warn "无效选择。"; return 1; }
  (( choice >= 1 && choice <= ${#keys[@]} )) || { warn "无效选择。"; return 1; }
  SELECTED_NODE_KEY=${keys[$((choice-1))]}
}

rebuild_node_uri() {
  local key=$1 address domain port name name_enc uuid password obfs congestion path host tls insecure uri sni pub sid method
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
    anytls)
      password=$(jq -r '.nodes.anytls.password' "$STATE_FILE")
      uri="anytls://$(uri_encode "$password")@${host}:${port}?security=tls&sni=$(uri_encode "$domain")"
      [[ "$insecure" == true ]] && uri+="&insecure=1"
      ;;
    trojan)
      password=$(jq -r '.nodes.trojan.password' "$STATE_FILE")
      uri="trojan://$(uri_encode "$password")@${host}:${port}?security=tls&sni=$(uri_encode "$domain")"
      [[ "$insecure" == true ]] && uri+="&allowInsecure=1"
      ;;
    ss)
      method=$(jq -r '.nodes.ss.method' "$STATE_FILE")
      password=$(jq -r '.nodes.ss.password' "$STATE_FILE")
      uri="ss://$(uri_encode "$method"):$(uri_encode "$password")@${host}:${port}"
      ;;
    *) return 1 ;;
  esac

  uri+="#${name_enc}"
  local tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg k "$key" --arg uri "$uri" '.nodes[$k].uri=$uri' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
}

edit_tls_password() {
  local key=$1 tag new
  tag=$(node_tag_for_key "$key")
  read -r -p "新 $(node_label_for_key "$key") 密码（留空自动生成）: " new
  new=${new:-$(random_hex 24)}
  [[ -n "$new" ]] || die "密码不能为空。"
  config_patch_apply "修改 $(node_label_for_key "$key") 密码" \
    --arg tag "$tag" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .users[0].password=$value else . end)'
  state_patch_apply "$key" --arg value "$new" '.nodes[$k].password=$value'
  post_parameter_change "$key"
  info "$(node_label_for_key "$key") 密码已原地修改。"
}

edit_ss_port() {
  local old new tag="shadowsocks-in"
  old=$(jq -r '.nodes.ss.port' "$STATE_FILE")
  read -r -p "新 TCP/UDP 端口 [${old}]: " new
  new=${new:-$old}
  validate_port "$new" || die "端口必须为 1-65535。"
  [[ "$new" == "$old" ]] && { note "端口未变化。"; return 0; }
  if port_in_use_by_other tcp "$new" "$tag" || port_in_use_by_other udp "$new" "$tag"; then
    show_port_owner tcp "$new"
    show_port_owner udp "$new"
    die "TCP 或 UDP/$new 已被占用。"
  fi
  config_patch_apply "修改 Shadowsocks 端口" --arg tag "$tag" --argjson port "$new" \
    '.inbounds |= map(if .tag==$tag then .listen_port=$port else . end)'
  state_patch_apply ss --argjson port "$new" '.nodes[$k].port=$port'
  rebuild_node_uri ss || true
  render_node_info
  allow_if_ufw_active "$new" tcp
  allow_if_ufw_active "$new" udp
  if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then refresh_client_exports_if_present || true; fi
  warn "为避免误删其他服务规则，旧端口 ${old}/TCP+UDP 的 UFW 规则不会自动删除。"
  info "Shadowsocks 端口已从 $old 原地修改为 $new。"
}

edit_ss_password() {
  local method new
  method=$(jq -r '.nodes.ss.method' "$STATE_FILE")
  new=$(ss_password_for_method "$method")
  note "为保证 ${method} 密钥格式正确，将自动生成新密钥。"
  config_patch_apply "修改 Shadowsocks 密钥" --arg tag "shadowsocks-in" --arg value "$new" \
    '.inbounds |= map(if .tag==$tag then .password=$value else . end)'
  state_patch_apply ss --arg value "$new" '.nodes[$k].password=$value'
  post_parameter_change ss
  info "Shadowsocks 密钥已原地轮换。"
}

edit_ss_method() {
  local old new_method new_password tmp
  old=$(jq -r '.nodes.ss.method' "$STATE_FILE")
  select_ss_method
  new_method=$SS_METHOD
  [[ "$new_method" == "$old" ]] && { note "加密方法未变化。"; return 0; }
  new_password=$(ss_password_for_method "$new_method")
  note "切换加密方法会自动生成匹配长度的新密钥，客户端需要更新订阅。"
  config_patch_apply "修改 Shadowsocks 加密方法" \
    --arg tag "shadowsocks-in" --arg method "$new_method" --arg password "$new_password" \
    '.inbounds |= map(if .tag==$tag then .method=$method | .password=$password else . end)'
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg method "$new_method" --arg password "$new_password" \
    '.nodes.ss.method=$method | .nodes.ss.password=$password' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  rebuild_node_uri ss || true
  render_node_info
  if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then refresh_client_exports_if_present || true; fi
  info "Shadowsocks 已切换为 ${new_method}。"
}

edit_anytls_menu() {
  echo
  headmsg "AnyTLS · 原地修改"
  ui_item 1 "节点地址" "客户端连接地址"
  ui_item 2 "TCP 监听端口" "服务端"
  ui_item 3 "认证密码" "自动生成"
  ui_item 4 "TLS SNI / 证书" "ACME / 自签 / PEM"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择参数 › " n
  case "$n" in
    1) edit_client_address anytls ;;
    2) edit_node_port anytls ;;
    3) edit_tls_password anytls ;;
    4) switch_certificate_tls ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

edit_trojan_menu() {
  echo
  headmsg "Trojan · 原地修改"
  ui_item 1 "节点地址" "客户端连接地址"
  ui_item 2 "TCP 监听端口" "服务端"
  ui_item 3 "认证密码" "自动生成"
  ui_item 4 "TLS SNI / 证书" "ACME / 自签 / PEM"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择参数 › " n
  case "$n" in
    1) edit_client_address trojan ;;
    2) edit_node_port trojan ;;
    3) edit_tls_password trojan ;;
    4) switch_certificate_tls ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

edit_ss_menu() {
  echo
  headmsg "Shadowsocks · 原地修改"
  ui_item 1 "节点地址" "客户端连接地址"
  ui_item 2 "TCP + UDP 监听端口" "双栈协议"
  ui_item 3 "轮换密钥" "保持当前加密方法"
  ui_item 4 "加密方法" "切换时自动换密钥"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择参数 › " n
  case "$n" in
    1) edit_client_address ss ;;
    2) edit_ss_port ;;
    3) edit_ss_password ;;
    4) edit_ss_method ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

edit_node_parameters() {
  ensure_singbox
  ensure_state
  echo
  headmsg "节点参数原地修改"
  note "只修改所选字段；其他凭据、密钥和路径默认保持不变。"
  note "服务端参数继续执行 check → 备份 → reload/restart → 健康检查 → 失败回滚。"
  ui_node_overview
  select_managed_node_for_edit || return 0
  case "$SELECTED_NODE_KEY" in
    reality) edit_reality_menu ;;
    hy2) edit_hy2_menu ;;
    tuic) edit_tuic_menu ;;
    ws) edit_ws_menu ;;
    anytls) edit_anytls_menu ;;
    trojan) edit_trojan_menu ;;
    ss) edit_ss_menu ;;
  esac
}

# Extend certificate switching to AnyTLS/Trojan. Shadowsocks has no certificate layer.
switch_certificate_tls() {
  ensure_state
  ensure_singbox

  local order=(hy2 tuic ws anytls trojan) keys=() labels=() k key tag allow_off current_name server_name choice idx candidate port new_port insecure_json cert_json tmp
  for k in "${order[@]}"; do
    if jq -e --arg k "$k" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1; then
      keys+=("$k")
      labels+=("$(node_label_for_key "$k")")
    fi
  done
  if (( ${#keys[@]} == 0 )); then
    warn "当前没有可切换证书/TLS 的节点。"
    return 0
  fi

  echo
  headmsg "切换证书 / TLS 模式"
  for idx in "${!keys[@]}"; do ui_item "$((idx+1))" "${labels[$idx]}"; done
  read -r -p "  请选择节点 › " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || die "无效选择。"
  (( choice >= 1 && choice <= ${#keys[@]} )) || die "无效选择。"
  key=${keys[$((choice-1))]}

  case "$key" in
    hy2) tag="hysteria2-in"; allow_off=false ;;
    tuic) tag="tuic-in"; allow_off=false ;;
    ws) tag="vless-ws-tls-in"; allow_off=true ;;
    anytls) tag="anytls-in"; allow_off=false ;;
    trojan) tag="trojan-in"; allow_off=false ;;
  esac

  current_name=$(jq -r --arg k "$key" '.nodes[$k].domain // .nodes[$k].address // empty' "$STATE_FILE")
  server_name=$current_name
  if [[ "$key" != ws ]]; then
    read -r -p "TLS SNI / 证书名称 [${current_name}]: " server_name
    server_name=${server_name:-$current_name}
  fi
  select_certificate_mode "$server_name" "$allow_off"

  port=$(jq -r --arg k "$key" '.nodes[$k].port' "$STATE_FILE")
  new_port=$port
  if [[ "$key" == ws ]]; then
    if [[ "$TLS_ENABLED" == true ]] && ! cloudflare_https_port "$port"; then
      new_port=443
      port_in_use_by_other tcp "$new_port" "$tag" && new_port=8443
      read -r -p "TLS 开启后原端口 $port 不属于 Cloudflare HTTPS 端口，新端口 [${new_port}]: " tmp
      new_port=${tmp:-$new_port}
      cloudflare_https_port "$new_port" || die "请选择 Cloudflare HTTPS 端口。"
    elif [[ "$TLS_ENABLED" == false ]] && ! cloudflare_http_port "$port"; then
      new_port=8080
      port_in_use_by_other tcp "$new_port" "$tag" && new_port=8880
      read -r -p "TLS 关闭后原端口 $port 不属于 Cloudflare HTTP 端口，新端口 [${new_port}]: " tmp
      new_port=${tmp:-$new_port}
      cloudflare_http_port "$new_port" || die "请选择 Cloudflare HTTP 端口。"
    fi
    if [[ "$new_port" != "$port" ]] && port_in_use_by_other tcp "$new_port" "$tag"; then
      show_port_owner tcp "$new_port"
      die "TCP/$new_port 已被其他服务占用。"
    fi
  fi

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  cp -a "$CONFIG_FILE" "$candidate"
  if [[ "$TLS_ENABLED" == true ]]; then
    if [[ "$key" == tuic ]]; then
      jq --arg tag "$tag" --arg sn "$server_name" --arg cert "$CERT_PATH" --arg key "$KEY_PATH" --argjson port "$new_port" \
        '.inbounds |= map(if .tag==$tag then .listen_port=$port | .tls={enabled:true,server_name:$sn,alpn:["h3"],certificate_path:$cert,key_path:$key} else . end)' \
        "$candidate" > "${candidate}.tmp"
    else
      jq --arg tag "$tag" --arg sn "$server_name" --arg cert "$CERT_PATH" --arg key "$KEY_PATH" --argjson port "$new_port" \
        '.inbounds |= map(if .tag==$tag then .listen_port=$port | .tls={enabled:true,server_name:$sn,certificate_path:$cert,key_path:$key} else . end)' \
        "$candidate" > "${candidate}.tmp"
    fi
  else
    [[ "$key" == ws ]] || die "该协议不支持关闭 TLS。"
    jq --arg tag "$tag" --argjson port "$new_port" \
      '.inbounds |= map(if .tag==$tag then .listen_port=$port | del(.tls) else . end)' \
      "$candidate" > "${candidate}.tmp"
  fi
  mv -f "${candidate}.tmp" "$candidate"
  apply_candidate "$candidate" "切换证书/TLS"

  insecure_json=false
  [[ "$CERT_CLIENT_INSECURE" == true ]] && insecure_json=true
  cert_json=false
  [[ "$TLS_ENABLED" == true ]] && cert_json=true
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg k "$key" --arg domain "$server_name" --arg mode "$CERT_MODE" \
     --arg cert_path "$CERT_PATH" --arg key_path "$KEY_PATH" --argjson port "$new_port" \
     --argjson tls "$TLS_ENABLED" --argjson cert "$cert_json" --argjson insecure "$insecure_json" '
    .nodes[$k].domain=$domain
    | .nodes[$k].port=$port
    | .nodes[$k].tls_enabled=$tls
    | .nodes[$k].certificate=$cert
    | .nodes[$k].certificate_mode=$mode
    | .nodes[$k].certificate_path=$cert_path
    | .nodes[$k].key_path=$key_path
    | .nodes[$k].insecure=$insecure
  ' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  rebuild_node_uri "$key"
  render_node_info
  if [[ "$key" == ws ]] && have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw_allow_cloudflare_only "$new_port"
  fi
  if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then refresh_client_exports_if_present || true; fi
  info "证书/TLS 模式切换完成。"
  [[ "$CERT_CLIENT_INSECURE" == true ]] && warn "客户端需要启用跳过证书验证。"
  show_nodes
}

remove_node() {
  ensure_state
  local order=(reality hy2 tuic ws anytls trojan ss) keys=() labels=() key idx choice tag candidate
  for key in "${order[@]}"; do
    if jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1; then
      keys+=("$key")
      labels+=("$(node_label_for_key "$key")")
    fi
  done
  if (( ${#keys[@]} == 0 )); then
    warn "当前没有可删除的脚本管理节点。"
    return 0
  fi

  echo
  headmsg "删除节点"
  warn "只删除所选 sing-box 入站与状态；证书、BBR 和旧 UFW 规则不会自动清理。"
  for idx in "${!keys[@]}"; do ui_item "$((idx+1))" "${labels[$idx]}"; done
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择节点 › " choice
  [[ "$choice" == 0 ]] && return 0
  [[ "$choice" =~ ^[0-9]+$ ]] || { warn "无效选择。"; return 0; }
  (( choice >= 1 && choice <= ${#keys[@]} )) || { warn "无效选择。"; return 0; }
  key=${keys[$((choice-1))]}
  tag=$(node_tag_for_key "$key")

  [[ -f "$CONFIG_FILE" ]] || { state_remove_node "$key"; return 0; }
  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_without_inbound "$tag" "$candidate"
  apply_candidate "$candidate" "删除 $(node_label_for_key "$key")"
  state_remove_node "$key"
  info "$(node_label_for_key "$key") 已删除。"
}

firewall_setup_v16() {
  firewall_setup
  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active' \
      && [[ -f "$STATE_FILE" ]] && jq -e '.nodes.ss != null' "$STATE_FILE" >/dev/null 2>&1; then
    local p
    p=$(jq -r '.nodes.ss.port // empty' "$STATE_FILE")
    if validate_port "$p"; then
      ufw allow "${p}/tcp" >/dev/null || true
      ufw allow "${p}/udp" >/dev/null || true
      info "Shadowsocks 已同时放行 TCP/UDP/$p。"
    fi
  fi
}
