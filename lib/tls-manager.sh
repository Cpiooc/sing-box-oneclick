#!/usr/bin/env bash
# shellcheck shell=bash

SELF_CERT_ROOT="${APP_DIR}/certs/self-signed"
CUSTOM_CERT_ROOT="${APP_DIR}/certs/custom"

cloudflare_http_port() {
  case "$1" in
    80|8080|8880|2052|2082|2086|2095) return 0 ;;
    *) return 1 ;;
  esac
}

managed_cert_dir_name() {
  printf '%s' "$1" | tr ':/' '__' | sed 's/[^A-Za-z0-9._-]/_/g'
}

certificate_public_key_hash() {
  openssl x509 -in "$1" -pubkey -noout 2>/dev/null \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | sha256sum | awk '{print $1}'
}

private_key_public_hash() {
  openssl pkey -in "$1" -pubout -outform DER 2>/dev/null \
    | sha256sum | awk '{print $1}'
}

validate_certificate_pair() {
  local cert=$1 key=$2 cert_hash key_hash
  [[ -r "$cert" ]] || die "证书文件不存在或不可读：$cert"
  [[ -r "$key" ]] || die "私钥文件不存在或不可读：$key"
  openssl x509 -in "$cert" -noout >/dev/null 2>&1 || die "不是有效的 PEM/X.509 证书：$cert"
  openssl pkey -in "$key" -noout >/dev/null 2>&1 || die "不是有效的 PEM 私钥：$key"
  cert_hash=$(certificate_public_key_hash "$cert")
  key_hash=$(private_key_public_hash "$key")
  [[ -n "$cert_hash" && "$cert_hash" == "$key_hash" ]] || die "证书与私钥不匹配。"
}

ensure_self_signed_certificate() {
  local server_name=$1 dir cert key san
  dir="${SELF_CERT_ROOT}/$(managed_cert_dir_name "$server_name")"
  cert="${dir}/cert.pem"
  key="${dir}/key.pem"
  install -d -m 700 "$dir"

  if [[ -s "$cert" && -s "$key" ]] \
      && openssl x509 -checkend 2592000 -noout -in "$cert" >/dev/null 2>&1; then
    info "复用现有自签证书：$cert"
  else
    if is_ipv4 "$server_name" || is_ipv6 "$server_name"; then
      san="IP:${server_name}"
    else
      is_hostname "$server_name" || die "自签证书名称必须是有效域名或 IP。"
      san="DNS:${server_name}"
    fi

    info "生成 10 年有效期 RSA-2048 自签证书（SAN=${san}）..."
    openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
      -keyout "$key" -out "$cert" \
      -subj "/CN=${server_name}" \
      -addext "subjectAltName=${san}" >/dev/null 2>&1 \
      || die "自签证书生成失败。"
    chmod 600 "$key"
    chmod 644 "$cert"
  fi

  CERT_PATH=$cert
  KEY_PATH=$key
  CERT_MODE="self-signed"
  CERT_CLIENT_INSECURE=true
  TLS_ENABLED=true
}

ensure_custom_certificate() {
  local server_name=$1 source_cert source_key dir ans
  read -r -p "现有证书链 PEM 路径: " source_cert
  read -r -p "现有私钥 PEM 路径: " source_key
  validate_certificate_pair "$source_cert" "$source_key"

  dir="${CUSTOM_CERT_ROOT}/$(managed_cert_dir_name "$server_name")"
  install -d -m 700 "$dir"
  install -m 0644 "$source_cert" "${dir}/cert.pem"
  install -m 0600 "$source_key" "${dir}/key.pem"

  CERT_PATH="${dir}/cert.pem"
  KEY_PATH="${dir}/key.pem"
  CERT_MODE="custom"
  TLS_ENABLED=true

  read -r -p "该证书是否由客户端系统信任且名称匹配 ${server_name}？[Y/n]: " ans
  if [[ -z "$ans" || ${ans,,} == "y" || ${ans,,} == "yes" ]]; then
    CERT_CLIENT_INSECURE=false
  else
    CERT_CLIENT_INSECURE=true
    warn "客户端需要允许跳过证书验证；安全性低于受信任证书。"
  fi
}

ensure_acme_domain_certificate() {
  local domain=$1
  is_hostname "$domain" || die "ACME 公网证书必须使用有效域名，不能直接给 IP 签发。"
  check_domain "$domain" direct
  ensure_certificate "$domain"
  CERT_MODE="acme"
  CERT_CLIENT_INSECURE=false
  TLS_ENABLED=true
}

select_certificate_mode() {
  local server_name=$1 allow_off=${2:-false} choice
  CERT_MODE=""
  CERT_CLIENT_INSECURE=false
  TLS_ENABLED=true
  CERT_PATH=""
  KEY_PATH=""

  while true; do
    echo
    headmsg "===== TLS / 证书模式 ====="
    echo "1. ACME 域名证书（Let's Encrypt，推荐）"
    echo "2. 自签证书（无需域名验证；客户端需允许不安全证书）"
    echo "3. 导入现有 PEM 证书 + 私钥"
    if [[ "$allow_off" == "true" ]]; then
      echo "4. 关闭 TLS（仅 VLESS WebSocket 支持）"
    fi
    read -r -p "请选择 [1]: " choice
    choice=${choice:-1}

    case "$choice" in
      1)
        if ! is_hostname "$server_name"; then
          warn "ACME 需要域名。当前 TLS 名称是 IP：$server_name"
          continue
        fi
        ensure_acme_domain_certificate "$server_name"
        return 0
        ;;
      2)
        ensure_self_signed_certificate "$server_name"
        return 0
        ;;
      3)
        ensure_custom_certificate "$server_name"
        return 0
        ;;
      4)
        if [[ "$allow_off" == "true" ]]; then
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

insecure_query_hy2() {
  [[ ${CERT_CLIENT_INSECURE:-false} == true ]] && printf '&insecure=1'
}

insecure_query_tuic() {
  [[ ${CERT_CLIENT_INSECURE:-false} == true ]] && printf '&allow_insecure=1'
}

deploy_hysteria2() {
  ensure_singbox
  install_deps
  sync_time

  local tag="hysteria2-in"
  local node_addr server_name port password obfs_password masquerade host name uri inbound candidate state name_enc insecure_json

  echo
  headmsg "===== 部署 / 重建 Hysteria2 ====="
  warn "Hysteria2 使用 QUIC/UDP；普通 Cloudflare 橙云不能代理，请使用 DNS only（灰云）或直接 IP。"

  read -r -p "HY2 节点地址（域名或 VPS IP）: " node_addr
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

  read -r -p "UDP 监听端口 [443]: " port
  port=${port:-443}
  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other udp "$port" "$tag"; then
    warn "UDP/$port 已被占用："
    show_port_owner udp "$port"
    die "请选择其他端口。"
  fi

  password=$(random_hex 24)
  obfs_password=$(random_hex 20)
  read -r -p "伪装网站 [https://www.microsoft.com]: " masquerade
  masquerade=${masquerade:-https://www.microsoft.com}
  [[ "$masquerade" =~ ^https?:// ]] || die "伪装网站必须以 http:// 或 https:// 开头。"

  inbound=$(jq -n \
    --arg password "$password" --arg obfs "$obfs_password" \
    --arg server_name "$server_name" --arg cert "$CERT_PATH" --arg key "$KEY_PATH" \
    --arg masquerade "$masquerade" --argjson port "$port" \
    '{type:"hysteria2",tag:"hysteria2-in",listen:"::",listen_port:$port,users:[{name:"main",password:$password}],obfs:{type:"salamander",password:$obfs},tls:{enabled:true,server_name:$server_name,certificate_path:$cert,key_path:$key},masquerade:$masquerade}')

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "Hysteria2"

  host=$(uri_host "$node_addr")
  name="sing-box-Hysteria2"
  name_enc=$(uri_encode "$name")
  uri="hysteria2://$(uri_encode "$password")@${host}:${port}?sni=$(uri_encode "$server_name")&obfs=salamander&obfs-password=$(uri_encode "$obfs_password")$(insecure_query_hy2)#${name_enc}"
  insecure_json=false
  [[ "$CERT_CLIENT_INSECURE" == true ]] && insecure_json=true

  state=$(jq -n \
    --arg name "$name" --arg address "$node_addr" --arg domain "$server_name" \
    --argjson port "$port" --arg password "$password" --arg obfs "$obfs_password" \
    --arg uri "$uri" --arg cert_mode "$CERT_MODE" --arg cert_path "$CERT_PATH" --arg key_path "$KEY_PATH" \
    --argjson insecure "$insecure_json" \
    '{name:$name,type:"Hysteria2",address:$address,domain:$domain,port:$port,password:$password,obfs_password:$obfs,uri:$uri,firewall:"udp",certificate:true,tls_enabled:true,certificate_mode:$cert_mode,certificate_path:$cert_path,key_path:$key_path,insecure:$insecure}')
  state_set_node hy2 "$state"

  allow_if_ufw_active "$port" udp
  [[ "$CERT_CLIENT_INSECURE" == true ]] && warn "当前为自签/不受信任证书，客户端必须允许跳过证书验证。"
  echo
  show_nodes
}

deploy_tuic() {
  ensure_singbox
  install_deps
  sync_time

  local tag="tuic-in"
  local node_addr server_name port default_port uuid password congestion host name uri inbound candidate state name_enc insecure_json

  echo
  headmsg "===== 部署 / 重建 TUIC v5 ====="
  note "TUIC 基于 QUIC/UDP + TLS；TLS 是协议必需项，不能关闭。"
  note "0-RTT 固定关闭；QUIC 拥塞控制默认使用 TUIC 自身的 bbr。"

  read -r -p "TUIC 节点地址（域名或 VPS IP）: " node_addr
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

  default_port=8443
  if port_in_use_by_other udp "$default_port" "$tag"; then
    default_port=10443
    warn "UDP/8443 已被占用，默认改用 UDP/10443。"
  fi
  read -r -p "UDP 监听端口 [${default_port}]: " port
  port=${port:-$default_port}
  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other udp "$port" "$tag"; then
    warn "UDP/$port 已被占用："
    show_port_owner udp "$port"
    die "请选择其他 UDP 端口。"
  fi

  uuid=$(sing-box generate uuid)
  password=$(random_hex 24)
  read -r -p "TUIC QUIC 拥塞控制 [bbr]（bbr/cubic/new_reno）: " congestion
  congestion=${congestion:-bbr}
  congestion=${congestion,,}
  case "$congestion" in bbr|cubic|new_reno) ;; *) die "只允许 bbr / cubic / new_reno。" ;; esac

  inbound=$(jq -n \
    --arg uuid "$uuid" --arg password "$password" --arg congestion "$congestion" \
    --arg server_name "$server_name" --arg cert "$CERT_PATH" --arg key "$KEY_PATH" \
    --argjson port "$port" \
    '{type:"tuic",tag:"tuic-in",listen:"::",listen_port:$port,users:[{name:"main",uuid:$uuid,password:$password}],congestion_control:$congestion,auth_timeout:"3s",zero_rtt_handshake:false,heartbeat:"10s",tls:{enabled:true,server_name:$server_name,alpn:["h3"],certificate_path:$cert,key_path:$key}}')

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "TUIC v5"

  host=$(uri_host "$node_addr")
  name="sing-box-TUIC"
  name_enc=$(uri_encode "$name")
  uri="tuic://${uuid}:$(uri_encode "$password")@${host}:${port}?sni=$(uri_encode "$server_name")&alpn=h3&congestion_control=$(uri_encode "$congestion")&udp_relay_mode=native&zero_rtt_handshake=0$(insecure_query_tuic)#${name_enc}"
  insecure_json=false
  [[ "$CERT_CLIENT_INSECURE" == true ]] && insecure_json=true

  state=$(jq -n \
    --arg name "$name" --arg address "$node_addr" --arg domain "$server_name" \
    --argjson port "$port" --arg uuid "$uuid" --arg password "$password" --arg congestion "$congestion" \
    --arg uri "$uri" --arg cert_mode "$CERT_MODE" --arg cert_path "$CERT_PATH" --arg key_path "$KEY_PATH" \
    --argjson insecure "$insecure_json" \
    '{name:$name,type:"TUIC v5",address:$address,domain:$domain,port:$port,uuid:$uuid,password:$password,congestion_control:$congestion,uri:$uri,firewall:"udp",certificate:true,tls_enabled:true,certificate_mode:$cert_mode,certificate_path:$cert_path,key_path:$key_path,insecure:$insecure}')
  state_set_node tuic "$state"

  allow_if_ufw_active "$port" udp
  [[ "$CERT_CLIENT_INSECURE" == true ]] && warn "当前为自签/不受信任证书，客户端必须允许跳过证书验证。"
  echo
  show_nodes
}

deploy_cloudflare_ws() {
  ensure_singbox
  install_deps
  sync_time

  local tag="vless-ws-tls-in"
  local domain port default_port uuid path host name uri inbound candidate state name_enc insecure_json cert_json

  echo
  headmsg "===== 部署 / 重建 Cloudflare VLESS WebSocket ====="
  read -r -p "Cloudflare 域名: " domain
  is_hostname "$domain" || die "必须输入有效域名。"
  check_domain "$domain" cloudflare

  select_certificate_mode "$domain" true

  if [[ "$TLS_ENABLED" == true ]]; then
    default_port=443
    if port_in_use_by_other tcp 443 "$tag"; then default_port=8443; fi
    read -r -p "HTTPS 端口 [${default_port}]: " port
    port=${port:-$default_port}
    cloudflare_https_port "$port" || die "TLS 开启时 Cloudflare HTTPS 端口仅支持 443/2053/2083/2087/2096/8443。"
  else
    warn "TLS 已关闭：客户端到 Cloudflare 将使用明文 WebSocket，不建议作为主力。"
    default_port=80
    if port_in_use_by_other tcp 80 "$tag"; then default_port=8080; fi
    read -r -p "HTTP 端口 [${default_port}]: " port
    port=${port:-$default_port}
    cloudflare_http_port "$port" || die "TLS 关闭时 Cloudflare HTTP 端口仅支持 80/8080/8880/2052/2082/2086/2095。"
  fi

  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other tcp "$port" "$tag"; then
    warn "TCP/$port 已被占用："
    show_port_owner tcp "$port"
    die "请选择其他端口。"
  fi

  uuid=$(sing-box generate uuid)
  path="/$(random_hex 12)"

  if [[ "$TLS_ENABLED" == true ]]; then
    inbound=$(jq -n \
      --arg uuid "$uuid" --arg domain "$domain" --arg path "$path" \
      --arg cert "$CERT_PATH" --arg key "$KEY_PATH" --argjson port "$port" \
      '{type:"vless",tag:"vless-ws-tls-in",listen:"::",listen_port:$port,users:[{name:"main",uuid:$uuid}],tls:{enabled:true,server_name:$domain,certificate_path:$cert,key_path:$key},transport:{type:"ws",path:$path}}')
  else
    inbound=$(jq -n \
      --arg uuid "$uuid" --arg path "$path" --argjson port "$port" \
      '{type:"vless",tag:"vless-ws-tls-in",listen:"::",listen_port:$port,users:[{name:"main",uuid:$uuid}],transport:{type:"ws",path:$path}}')
  fi

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "Cloudflare VLESS WS"

  host=$(uri_host "$domain")
  name="sing-box-CF-WS"
  name_enc=$(uri_encode "$name")
  if [[ "$TLS_ENABLED" == true ]]; then
    uri="vless://${uuid}@${host}:${port}?encryption=none&security=tls&sni=$(uri_encode "$domain")&type=ws&host=$(uri_encode "$domain")&path=$(uri_encode "$path")#${name_enc}"
  else
    uri="vless://${uuid}@${host}:${port}?encryption=none&security=none&type=ws&host=$(uri_encode "$domain")&path=$(uri_encode "$path")#${name_enc}"
  fi

  insecure_json=false
  [[ "$CERT_CLIENT_INSECURE" == true ]] && insecure_json=true
  cert_json=false
  [[ "$TLS_ENABLED" == true ]] && cert_json=true
  state=$(jq -n \
    --arg name "$name" --arg address "$domain" --arg domain "$domain" --argjson port "$port" \
    --arg uuid "$uuid" --arg path "$path" --arg uri "$uri" --arg cert_mode "$CERT_MODE" \
    --arg cert_path "$CERT_PATH" --arg key_path "$KEY_PATH" \
    --argjson tls "$TLS_ENABLED" --argjson cert "$cert_json" --argjson insecure "$insecure_json" \
    '{name:$name,type:"VLESS WebSocket (Cloudflare)",address:$address,domain:$domain,port:$port,uuid:$uuid,path:$path,uri:$uri,firewall:"tcp",cloudflare:true,certificate:$cert,tls_enabled:$tls,certificate_mode:$cert_mode,certificate_path:$cert_path,key_path:$key_path,insecure:$insecure}')
  state_set_node ws "$state"

  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw_allow_cloudflare_only "$port"
  else
    warn "UFW 未启用。建议之后配置 UFW，并把该源站端口限制为仅 Cloudflare IP 可访问。"
  fi

  if [[ "$TLS_ENABLED" == true ]]; then
    if [[ "$CERT_CLIENT_INSECURE" == true ]]; then
      warn "源站使用自签/不受信任证书：Cloudflare SSL 模式应使用 Full，而不是 Full (strict)。"
    else
      note "Cloudflare SSL/TLS 建议使用 Full (strict)。"
    fi
  else
    warn "TLS 关闭时为 WS 明文模式；Cloudflare 端必须使用受支持的 HTTP 端口。"
  fi
  show_nodes
}

rebuild_node_uri() {
  local key=$1 address domain port name name_enc uuid password obfs congestion path host tls insecure uri
  address=$(jq -r --arg k "$key" '.nodes[$k].address // empty' "$STATE_FILE")
  domain=$(jq -r --arg k "$key" '.nodes[$k].domain // empty' "$STATE_FILE")
  port=$(jq -r --arg k "$key" '.nodes[$k].port // empty' "$STATE_FILE")
  name=$(jq -r --arg k "$key" '.nodes[$k].name // $k' "$STATE_FILE")
  name_enc=$(uri_encode "$name")
  host=$(uri_host "$address")
  insecure=$(jq -r --arg k "$key" '.nodes[$k].insecure // false' "$STATE_FILE")

  case "$key" in
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
}

switch_certificate_tls() {
  ensure_state
  ensure_singbox

  local keys=() labels=() key tag allow_off current_name server_name choice idx candidate port new_port insecure_json cert_json tls_json tmp
  jq -e '.nodes.hy2 != null' "$STATE_FILE" >/dev/null && { keys+=(hy2); labels+=("Hysteria2"); }
  jq -e '.nodes.tuic != null' "$STATE_FILE" >/dev/null && { keys+=(tuic); labels+=("TUIC v5"); }
  jq -e '.nodes.ws != null' "$STATE_FILE" >/dev/null && { keys+=(ws); labels+=("Cloudflare VLESS WS"); }

  if (( ${#keys[@]} == 0 )); then
    warn "当前没有可切换证书/TLS 的 HY2、TUIC 或 WS 节点。"
    return 0
  fi

  echo
  headmsg "===== 切换证书 / TLS 模式 ====="
  for idx in "${!keys[@]}"; do
    printf '%d. %s\n' "$((idx+1))" "${labels[$idx]}"
  done
  read -r -p "请选择节点: " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || die "无效选择。"
  (( choice >= 1 && choice <= ${#keys[@]} )) || die "无效选择。"
  key=${keys[$((choice-1))]}

  case "$key" in
    hy2) tag="hysteria2-in"; allow_off=false ;;
    tuic) tag="tuic-in"; allow_off=false ;;
    ws) tag="vless-ws-tls-in"; allow_off=true ;;
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
      new_port=80
      port_in_use_by_other tcp "$new_port" "$tag" && new_port=8080
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
      jq --arg tag "$tag" --arg sn "$server_name" --arg cert "$CERT_PATH" --arg key "$KEY_PATH" --argjson port "$new_port" '
        .inbounds |= map(if .tag==$tag then .listen_port=$port | .tls={enabled:true,server_name:$sn,alpn:["h3"],certificate_path:$cert,key_path:$key} else . end)
      ' "$candidate" > "${candidate}.tmp"
    else
      jq --arg tag "$tag" --arg sn "$server_name" --arg cert "$CERT_PATH" --arg key "$KEY_PATH" --argjson port "$new_port" '
        .inbounds |= map(if .tag==$tag then .listen_port=$port | .tls={enabled:true,server_name:$sn,certificate_path:$cert,key_path:$key} else . end)
      ' "$candidate" > "${candidate}.tmp"
    fi
  else
    [[ "$key" == ws ]] || die "该协议不支持关闭 TLS。"
    jq --arg tag "$tag" --argjson port "$new_port" '
      .inbounds |= map(if .tag==$tag then .listen_port=$port | del(.tls) else . end)
    ' "$candidate" > "${candidate}.tmp"
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

  if [[ "$key" == ws && "$new_port" != "$port" ]] && have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw_allow_cloudflare_only "$new_port"
  fi

  info "证书/TLS 模式切换完成。"
  [[ "$CERT_CLIENT_INSECURE" == true ]] && warn "客户端需要启用跳过证书验证。"
  [[ "$key" == ws && "$TLS_ENABLED" == false ]] && warn "WS 当前关闭 TLS，客户端到 Cloudflare 为明文 WebSocket。"
  show_nodes
}

certificate_status() {
  ensure_state
  local keys key name mode tls cert domain
  mapfile -t keys < <(jq -r '.nodes | to_entries[] | select((.value.certificate==true) or (.value.tls_enabled==true)) | .key' "$STATE_FILE")
  if (( ${#keys[@]} == 0 )); then
    warn "没有脚本管理的普通 TLS 证书节点。Reality 不使用普通证书。"
    return 0
  fi

  for key in "${keys[@]}"; do
    name=$(jq -r --arg k "$key" '.nodes[$k].name // $k' "$STATE_FILE")
    mode=$(jq -r --arg k "$key" '.nodes[$k].certificate_mode // "acme/legacy"' "$STATE_FILE")
    tls=$(jq -r --arg k "$key" '.nodes[$k].tls_enabled // true' "$STATE_FILE")
    cert=$(jq -r --arg k "$key" '.nodes[$k].certificate_path // empty' "$STATE_FILE")
    domain=$(jq -r --arg k "$key" '.nodes[$k].domain // empty' "$STATE_FILE")
    [[ -z "$cert" && "$mode" == "acme/legacy" && -n "$domain" ]] && cert="/etc/letsencrypt/live/${domain}/fullchain.pem"

    echo
    headmsg "===== $name ====="
    echo "TLS       : $tls"
    echo "证书模式  : $mode"
    echo "SNI/名称  : ${domain:-无}"
    if [[ "$tls" == true && -n "$cert" ]]; then
      echo "证书路径  : $cert"
      openssl x509 -in "$cert" -noout -subject -issuer -serial -dates 2>/dev/null || warn "证书不存在或不可读。"
    fi
  done

  echo
  systemctl status certbot.timer --no-pager -l 2>/dev/null | sed -n '1,12p' || true
}

renew_certificates() {
  ensure_state
  local acme_count
  acme_count=$(jq '[.nodes[] | select((.certificate_mode=="acme") or ((.certificate_mode==null) and (.certificate==true)))] | length' "$STATE_FILE")
  if (( acme_count > 0 )); then
    ensure_certbot
    certbot renew
    systemctl restart sing-box 2>/dev/null || true
  else
    note "当前没有 ACME/Let's Encrypt 节点，无需运行 Certbot renew。"
  fi
  note "自签证书默认有效 10 年，不参与 ACME 自动续期。"
  certificate_status
}
