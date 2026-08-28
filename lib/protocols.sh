#!/usr/bin/env bash
# shellcheck shell=bash

generate_reality_keypair() {
  local out
  out=$(sing-box generate reality-keypair)
  REALITY_PRIVATE=$(awk '/PrivateKey/ {print $NF; exit}' <<< "$out" | tr -d '"')
  REALITY_PUBLIC=$(awk '/PublicKey/ {print $NF; exit}' <<< "$out" | tr -d '"')
  [[ -n "${REALITY_PRIVATE:-}" && -n "${REALITY_PUBLIC:-}" ]] || die "Reality 密钥生成失败。"
}

deploy_reality() {
  ensure_singbox
  install_deps
  sync_time

  local tag="vless-reality-in"
  local node_addr port sni uuid short_id host name uri inbound candidate state name_enc

  echo
  headmsg "===== 部署 / 重建 VLESS + Reality ====="
  show_ip_info
  read -r -p "节点地址（VPS IP 或 Cloudflare DNS-only 灰云域名）: " node_addr
  [[ -n "$node_addr" ]] || die "节点地址不能为空。"
  check_domain "$node_addr" direct

  read -r -p "TCP 监听端口 [443]: " port
  port=${port:-443}
  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other tcp "$port" "$tag"; then
    warn "TCP/$port 已被其他程序或其他入站占用："
    show_port_owner tcp "$port"
    die "请选择其他端口。"
  fi

  read -r -p "Reality SNI / 握手域名 [www.microsoft.com]: " sni
  sni=${sni:-www.microsoft.com}
  is_hostname "$sni" || die "Reality SNI 必须是有效域名。"
  check_reality_target "$sni"

  uuid=$(sing-box generate uuid)
  short_id=$(sing-box generate rand --hex 8)
  generate_reality_keypair

  inbound=$(jq -n \
    --arg uuid "$uuid" \
    --arg sni "$sni" \
    --arg private_key "$REALITY_PRIVATE" \
    --arg short_id "$short_id" \
    --argjson port "$port" \
    '{
      type:"vless",
      tag:"vless-reality-in",
      listen:"::",
      listen_port:$port,
      users:[{name:"main",uuid:$uuid,flow:"xtls-rprx-vision"}],
      tls:{
        enabled:true,
        server_name:$sni,
        reality:{
          enabled:true,
          handshake:{server:$sni,server_port:443},
          private_key:$private_key,
          short_id:[$short_id],
          max_time_difference:"1m"
        }
      }
    }')

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "VLESS Reality"

  host=$(uri_host "$node_addr")
  name="sing-box-Reality"
  name_enc=$(uri_encode "$name")
  uri="vless://${uuid}@${host}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(uri_encode "$sni")&fp=chrome&pbk=$(uri_encode "$REALITY_PUBLIC")&sid=$(uri_encode "$short_id")&type=tcp#${name_enc}"

  state=$(jq -n \
    --arg name "$name" --arg address "$node_addr" --argjson port "$port" \
    --arg uuid "$uuid" --arg sni "$sni" --arg pub "$REALITY_PUBLIC" \
    --arg sid "$short_id" --arg uri "$uri" \
    '{name:$name,type:"VLESS Reality",address:$address,port:$port,uuid:$uuid,reality_sni:$sni,public_key:$pub,short_id:$sid,uri:$uri,firewall:"tcp"}')
  state_set_node reality "$state"

  allow_if_ufw_active "$port" tcp
  echo
  show_nodes
}

ensure_certbot() {
  if ! have certbot; then
    info "安装 Certbot（用于 TLS 证书和自动续期）..."
    apt-get update
    apt-get install -y certbot
  fi
  install -d -m 755 "$(dirname "$CERTBOT_HOOK")"
  cat > "$CERTBOT_HOOK" <<'HOOK'
#!/usr/bin/env bash
systemctl restart sing-box >/dev/null 2>&1 || true
HOOK
  chmod 755 "$CERTBOT_HOOK"
  systemctl enable --now certbot.timer >/dev/null 2>&1 || true
}

ensure_certificate() {
  local domain=$1
  ensure_certbot

  CERT_PATH="/etc/letsencrypt/live/${domain}/fullchain.pem"
  KEY_PATH="/etc/letsencrypt/live/${domain}/privkey.pem"

  if [[ -s "$CERT_PATH" && -s "$KEY_PATH" ]] && openssl x509 -checkend 2592000 -noout -in "$CERT_PATH" >/dev/null 2>&1; then
    info "复用现有有效证书：$CERT_PATH"
    return 0
  fi

  if ss -H -lnt "sport = :80" 2>/dev/null | grep -q .; then
    warn "TCP/80 已被占用，Certbot standalone 无法安全自动签发证书："
    show_port_owner tcp 80
    die "请先释放 TCP/80，或手工准备证书后再部署。"
  fi

  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow 80/tcp >/dev/null || true
    info "UFW 已放行 TCP/80，供 Let's Encrypt HTTP-01 验证及后续自动续期。"
  fi

  warn "证书签发要求云厂商安全组同时放行 TCP/80。"
  note "若该域名准备用于 Cloudflare 橙云，首次签证书建议先切到 DNS only（灰云）；证书成功后再开启橙云并使用 Full (strict)。"
  local email args=()
  read -r -p "Let's Encrypt 联系邮箱（可留空）: " email

  args=(certonly --standalone --non-interactive --agree-tos --preferred-challenges http -d "$domain")
  if [[ -n "$email" ]]; then
    args+=(-m "$email")
  else
    args+=(--register-unsafely-without-email)
  fi

  if ! certbot "${args[@]}"; then
    die "证书签发失败。请检查域名解析、Cloudflare 设置以及 VPS/云防火墙的 TCP/80。"
  fi

  [[ -s "$CERT_PATH" && -s "$KEY_PATH" ]] || die "Certbot 返回成功，但没有找到证书文件。"
  info "TLS 证书已签发，并启用 Certbot 自动续期。"
}

deploy_hysteria2() {
  ensure_singbox
  install_deps
  sync_time

  local tag="hysteria2-in"
  local domain node_addr port password obfs_password masquerade host name uri inbound candidate state name_enc

  echo
  headmsg "===== 部署 / 重建 Hysteria2 ====="
  warn "Hysteria2 使用 QUIC/UDP，普通 Cloudflare 橙云不能代理该流量；域名应使用 DNS only（灰云）。"

  read -r -p "HY2 域名（必须直接解析到 VPS）: " domain
  is_hostname "$domain" || die "HY2 必须使用有效域名以签发 TLS 证书。"
  check_domain "$domain" direct
  node_addr=$domain

  read -r -p "UDP 监听端口 [443]: " port
  port=${port:-443}
  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other udp "$port" "$tag"; then
    warn "UDP/$port 已被占用："
    show_port_owner udp "$port"
    die "请选择其他端口。"
  fi

  ensure_certificate "$domain"

  password=$(random_hex 24)
  obfs_password=$(random_hex 20)
  read -r -p "伪装网站 [https://www.microsoft.com]: " masquerade
  masquerade=${masquerade:-https://www.microsoft.com}
  [[ "$masquerade" =~ ^https?:// ]] || die "伪装网站必须以 http:// 或 https:// 开头。"

  inbound=$(jq -n \
    --arg password "$password" \
    --arg obfs "$obfs_password" \
    --arg domain "$domain" \
    --arg cert "$CERT_PATH" \
    --arg key "$KEY_PATH" \
    --arg masquerade "$masquerade" \
    --argjson port "$port" \
    '{
      type:"hysteria2",
      tag:"hysteria2-in",
      listen:"::",
      listen_port:$port,
      users:[{name:"main",password:$password}],
      obfs:{type:"salamander",password:$obfs},
      tls:{enabled:true,server_name:$domain,certificate_path:$cert,key_path:$key},
      masquerade:$masquerade
    }')

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "Hysteria2"

  host=$(uri_host "$node_addr")
  name="sing-box-Hysteria2"
  name_enc=$(uri_encode "$name")
  uri="hysteria2://$(uri_encode "$password")@${host}:${port}?sni=$(uri_encode "$domain")&obfs=salamander&obfs-password=$(uri_encode "$obfs_password")#${name_enc}"

  state=$(jq -n \
    --arg name "$name" --arg address "$node_addr" --arg domain "$domain" \
    --argjson port "$port" --arg password "$password" --arg obfs "$obfs_password" --arg uri "$uri" \
    '{name:$name,type:"Hysteria2",address:$address,domain:$domain,port:$port,password:$password,obfs_password:$obfs,uri:$uri,firewall:"udp",certificate:true}')
  state_set_node hy2 "$state"

  allow_if_ufw_active "$port" udp
  echo
  show_nodes
}

cloudflare_https_port() {
  case "$1" in
    443|2053|2083|2087|2096|8443) return 0 ;;
    *) return 1 ;;
  esac
}

deploy_cloudflare_ws() {
  ensure_singbox
  install_deps
  sync_time

  local tag="vless-ws-tls-in"
  local domain port default_port uuid path host name uri inbound candidate state name_enc

  echo
  headmsg "===== 部署 / 重建 VLESS WebSocket + TLS + Cloudflare ====="
  note "该模式用于 Cloudflare 橙云/CDN。Cloudflare SSL/TLS 建议设置 Full (strict)，并启用 WebSockets。"

  read -r -p "Cloudflare 域名: " domain
  is_hostname "$domain" || die "必须输入有效域名。"
  check_domain "$domain" cloudflare

  default_port=443
  if port_in_use_by_other tcp 443 "$tag"; then
    default_port=8443
    warn "TCP/443 已被其他服务占用，默认改用 Cloudflare 支持的 HTTPS 端口 8443。"
  fi

  read -r -p "HTTPS 端口 [${default_port}]: " port
  port=${port:-$default_port}
  validate_port "$port" || die "端口必须为 1-65535。"
  cloudflare_https_port "$port" || die "普通 Cloudflare 代理不支持该 HTTPS 端口。可用：443/2053/2083/2087/2096/8443。"

  if port_in_use_by_other tcp "$port" "$tag"; then
    warn "TCP/$port 已被占用："
    show_port_owner tcp "$port"
    die "请选择其他 Cloudflare HTTPS 端口。"
  fi

  ensure_certificate "$domain"

  uuid=$(sing-box generate uuid)
  path="/$(random_hex 12)"

  inbound=$(jq -n \
    --arg uuid "$uuid" \
    --arg domain "$domain" \
    --arg path "$path" \
    --arg cert "$CERT_PATH" \
    --arg key "$KEY_PATH" \
    --argjson port "$port" \
    '{
      type:"vless",
      tag:"vless-ws-tls-in",
      listen:"::",
      listen_port:$port,
      users:[{name:"main",uuid:$uuid}],
      tls:{enabled:true,server_name:$domain,certificate_path:$cert,key_path:$key},
      transport:{type:"ws",path:$path}
    }')

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "VLESS WS TLS"

  host=$(uri_host "$domain")
  name="sing-box-CF-WS"
  name_enc=$(uri_encode "$name")
  uri="vless://${uuid}@${host}:${port}?encryption=none&security=tls&sni=$(uri_encode "$domain")&type=ws&host=$(uri_encode "$domain")&path=$(uri_encode "$path")#${name_enc}"

  state=$(jq -n \
    --arg name "$name" --arg address "$domain" --arg domain "$domain" \
    --argjson port "$port" --arg uuid "$uuid" --arg path "$path" --arg uri "$uri" \
    '{name:$name,type:"VLESS WebSocket TLS (Cloudflare)",address:$address,domain:$domain,port:$port,uuid:$uuid,path:$path,uri:$uri,firewall:"tcp",cloudflare:true,certificate:true}')
  state_set_node ws "$state"

  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw_allow_cloudflare_only "$port"
  else
    warn "UFW 当前未启用。Cloudflare WS 模式建议之后运行“配置 UFW 防火墙”，并选择仅允许 Cloudflare IP 访问源站端口。"
  fi
  echo
  warn "若 Cloudflare 已开橙云，请确认 SSL/TLS 模式为 Full (strict)，Network -> WebSockets 为 On。"
  show_nodes
}

deploy_dual_reality_hy2() {
  echo
  headmsg "===== Reality + Hysteria2 双协议 ====="
  note "Reality 使用 TCP，HY2 使用 UDP，因此二者可以同时使用 443 端口。"
  deploy_reality
  echo
  deploy_hysteria2
}

remove_node() {
  ensure_state
  local key tag candidate
  echo
  headmsg "===== 删除脚本管理的节点 ====="
  echo "1. VLESS Reality"
  echo "2. Hysteria2"
  echo "3. Cloudflare VLESS WS+TLS"
  read -r -p "请选择: " n

  case "$n" in
    1) key=reality; tag=vless-reality-in ;;
    2) key=hy2; tag=hysteria2-in ;;
    3) key=ws; tag=vless-ws-tls-in ;;
    *) warn "无效选择。"; return 0 ;;
  esac

  if ! jq -e --arg key "$key" '.nodes[$key] != null' "$STATE_FILE" >/dev/null; then
    warn "状态文件中没有该节点。"
  fi

  [[ -f "$CONFIG_FILE" ]] || { state_remove_node "$key"; return 0; }
  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_without_inbound "$tag" "$candidate"
  apply_candidate "$candidate" "删除节点"
  state_remove_node "$key"
  info "节点已删除。证书和 BBR 设置未自动删除。"
}
