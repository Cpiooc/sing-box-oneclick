#!/usr/bin/env bash
# shellcheck shell=bash

SUBSCRIPTION_SERVICE="sing-box-oneclick-subscription.service"
SUBSCRIPTION_USER="${SUBSCRIPTION_USER:-sb-sub}"
SUBSCRIPTION_CONFIG="${SUBSCRIPTION_CONFIG:-${APP_DIR}/subscription-nginx.conf}"
SUBSCRIPTION_UNIT="${SUBSCRIPTION_UNIT:-/etc/systemd/system/${SUBSCRIPTION_SERVICE}}"
SUBSCRIPTION_PUBLISH_DIR="${SUBSCRIPTION_PUBLISH_DIR:-/var/lib/sing-box-oneclick-subscription}"
SUBSCRIPTION_RUNTIME_DIR="${SUBSCRIPTION_RUNTIME_DIR:-/run/sing-box-oneclick-subscription}"
SUBSCRIPTION_CERTBOT_HOOK="${SUBSCRIPTION_CERTBOT_HOOK:-/etc/letsencrypt/renewal-hooks/deploy/sing-box-oneclick-subscription-reload.sh}"

subscription_nginx_bin() {
  if [[ -x /usr/sbin/nginx ]]; then
    printf '%s' /usr/sbin/nginx
  else
    command -v nginx 2>/dev/null || true
  fi
}

subscription_enabled() {
  ensure_state
  [[ $(jq -r '.subscription.enabled // false' "$STATE_FILE" 2>/dev/null) == true ]]
}

subscription_mask_token() {
  local token=${1:-}
  if (( ${#token} <= 12 )); then
    printf '%s' '********'
  else
    printf '%s…%s' "${token:0:6}" "${token: -6}"
  fi
}

subscription_authority() {
  local domain=$1 port=$2
  if [[ "$port" == 443 ]]; then
    printf '%s' "$domain"
  else
    printf '%s:%s' "$domain" "$port"
  fi
}

subscription_cf_https_port() {
  cloudflare_https_port "$1"
}

subscription_default_cf_port() {
  local p
  for p in 2053 2083 2087 2096 8443 443; do
    if ! ss -H -lnt "sport = :$p" 2>/dev/null | grep -q .; then
      printf '%s' "$p"
      return 0
    fi
  done
  printf '%s' 2053
}

subscription_port_is_available() {
  local port=$1 current_port current_enabled
  current_port=$(jq -r '.subscription.port // empty' "$STATE_FILE" 2>/dev/null || true)
  current_enabled=$(jq -r '.subscription.enabled // false' "$STATE_FILE" 2>/dev/null || true)
  if [[ "$current_enabled" == true && "$current_port" == "$port" ]]; then
    return 0
  fi
  ! ss -H -lnt "sport = :$port" 2>/dev/null | grep -q .
}

ensure_subscription_user() {
  if getent passwd "$SUBSCRIPTION_USER" >/dev/null 2>&1; then
    return 0
  fi
  useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$SUBSCRIPTION_USER" \
    || die "创建订阅服务低权限用户失败。"
}

install_subscription_systemd_unit() {
  local nginx_bin
  nginx_bin=$(subscription_nginx_bin)
  [[ -n "$nginx_bin" ]] || die "未找到 nginx。"

  cat > "$SUBSCRIPTION_UNIT" <<EOF
[Unit]
Description=sing-box-oneclick private HTTPS subscription
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
RuntimeDirectory=sing-box-oneclick-subscription
RuntimeDirectoryMode=0755
ExecStartPre=${nginx_bin} -t -q -c ${SUBSCRIPTION_CONFIG}
ExecStart=${nginx_bin} -c ${SUBSCRIPTION_CONFIG} -g 'daemon off;'
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=/bin/kill -QUIT \$MAINPID
Restart=on-failure
RestartSec=2s
TimeoutStopSec=10s
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_SETUID CAP_SETGID

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$SUBSCRIPTION_UNIT"
  systemctl daemon-reload
}

install_subscription_certbot_hook() {
  install -d -m 755 "$(dirname "$SUBSCRIPTION_CERTBOT_HOOK")"
  cat > "$SUBSCRIPTION_CERTBOT_HOOK" <<'HOOK'
#!/usr/bin/env bash
if systemctl is-active --quiet sing-box-oneclick-subscription.service 2>/dev/null; then
  systemctl reload sing-box-oneclick-subscription.service >/dev/null 2>&1 \
    || systemctl restart sing-box-oneclick-subscription.service >/dev/null 2>&1 \
    || true
fi
HOOK
  chmod 755 "$SUBSCRIPTION_CERTBOT_HOOK"
}

ensure_subscription_runtime() {
  local had_nginx=false
  have nginx && had_nginx=true

  if [[ "$had_nginx" == false ]]; then
    info "安装 Nginx 二进制（仅供独立订阅服务实例使用）..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y nginx
    # Debian/Ubuntu packages may auto-start the distribution nginx service.
    # We installed nginx only as a binary dependency, so stop that newly-created
    # default service. If nginx existed before this function, it is never touched.
    systemctl disable --now nginx.service >/dev/null 2>&1 || true
  else
    note "检测到系统已有 Nginx；不会停止、禁用或改写它的站点配置。"
  fi

  ensure_subscription_user
  install -d -o root -g "$SUBSCRIPTION_USER" -m 0750 "$SUBSCRIPTION_PUBLISH_DIR"
  install_subscription_systemd_unit
  install_subscription_certbot_hook
}

subscription_select_certificate() {
  local domain=$1 choice
  CERT_PATH=""
  KEY_PATH=""
  CERT_MODE=""
  CERT_CLIENT_INSECURE=false

  echo
  headmsg "HTTPS 证书"
  ui_item 1 "ACME / Let's Encrypt 受信任证书（推荐）"
  ui_item 2 "导入已有受信任 PEM 证书 + 私钥"
  read -r -p "  请选择 [1] › " choice
  choice=${choice:-1}

  case "$choice" in
    1)
      ensure_certificate "$domain"
      CERT_MODE="acme"
      ;;
    2)
      ensure_custom_certificate "$domain"
      [[ ${CERT_CLIENT_INSECURE:-false} == false ]] \
        || die "HTTPS 在线订阅不接受需要跳过验证的证书。请使用受信任证书。"
      CERT_MODE="custom"
      ;;
    *) die "无效证书模式。" ;;
  esac

  validate_certificate_pair "$CERT_PATH" "$KEY_PATH"
}

publish_subscription_payloads() {
  ensure_state
  ensure_subscription_user
  install -d -o root -g "$SUBSCRIPTION_USER" -m 0750 "$SUBSCRIPTION_PUBLISH_DIR"

  local src dst f
  for f in sing-box-client.json mihomo.yaml v2rayn-subscription.txt v2rayn-subscription-base64.txt; do
    src="${CLIENT_EXPORT_DIR}/${f}"
    [[ -f "$src" ]] || continue
    dst="${SUBSCRIPTION_PUBLISH_DIR}/${f}"
    install -o root -g "$SUBSCRIPTION_USER" -m 0640 "$src" "${dst}.new"
    mv -f "${dst}.new" "$dst"
  done
}

refresh_subscription_payloads_if_enabled() {
  subscription_enabled || return 0
  publish_subscription_payloads || {
    warn "HTTPS 订阅内容自动刷新失败；请运行 sb sub 手工刷新。"
    return 0
  }
  return 0
}

write_subscription_nginx_config() {
  local domain=$1 port=$2 token=$3 cert=$4 key=$5 nginx_user=${6:-$SUBSCRIPTION_USER}
  local pid_path="${SUBSCRIPTION_RUNTIME_DIR}/nginx.pid"

  cat > "$SUBSCRIPTION_CONFIG" <<EOF
user ${nginx_user};
worker_processes 1;
pid ${pid_path};
error_log stderr warn;

events {
    worker_connections 256;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /dev/stdout combined;
    server_tokens off;
    sendfile on;
    keepalive_timeout 15s;
    client_max_body_size 1k;

    limit_req_zone \$binary_remote_addr zone=sbsub_req:1m rate=5r/s;
    limit_conn_zone \$binary_remote_addr zone=sbsub_conn:1m;

    server {
        listen ${port} ssl;
        listen [::]:${port} ssl;
        server_name ${domain};

        ssl_certificate ${cert};
        ssl_certificate_key ${key};
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_session_cache shared:SBSubSSL:1m;
        ssl_session_timeout 10m;
        ssl_session_tickets off;

        add_header Cache-Control "no-store, no-cache, must-revalidate" always;
        add_header Pragma "no-cache" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer" always;
        add_header X-Frame-Options "DENY" always;

        limit_req zone=sbsub_req burst=10 nodelay;
        limit_conn sbsub_conn 4;

        location = /${token}/sing-box {
            limit_except GET HEAD { deny all; }
            alias ${SUBSCRIPTION_PUBLISH_DIR}/sing-box-client.json;
            default_type application/json;
        }

        location = /${token}/mihomo {
            limit_except GET HEAD { deny all; }
            alias ${SUBSCRIPTION_PUBLISH_DIR}/mihomo.yaml;
            default_type text/yaml;
        }

        location = /${token}/v2rayn {
            limit_except GET HEAD { deny all; }
            alias ${SUBSCRIPTION_PUBLISH_DIR}/v2rayn-subscription-base64.txt;
            default_type text/plain;
        }

        location = /${token}/raw {
            limit_except GET HEAD { deny all; }
            alias ${SUBSCRIPTION_PUBLISH_DIR}/v2rayn-subscription.txt;
            default_type text/plain;
        }

        location / {
            return 404;
        }
    }
}
EOF
  chmod 600 "$SUBSCRIPTION_CONFIG"
}

validate_subscription_nginx_config() {
  local nginx_bin
  nginx_bin=$(subscription_nginx_bin)
  [[ -n "$nginx_bin" ]] || die "未找到 nginx。"
  "$nginx_bin" -t -q -c "$SUBSCRIPTION_CONFIG"
}

subscription_state_write() {
  local enabled=$1 domain=$2 port=$3 token=$4 mode=$5 cert=$6 key=$7 proxy_mode=$8 tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --argjson enabled "$enabled" --arg domain "$domain" --argjson port "$port" \
     --arg token "$token" --arg mode "$mode" --arg cert "$cert" --arg key "$key" --arg proxy_mode "$proxy_mode" '
    .subscription = {
      enabled:$enabled,
      domain:$domain,
      port:$port,
      token:$token,
      certificate_mode:$mode,
      certificate_path:$cert,
      key_path:$key,
      proxy_mode:$proxy_mode,
      updated_at:(now | todateiso8601)
    }
  ' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
}

subscription_local_healthcheck() {
  local domain=$1 port=$2 token=$3 authority url
  authority=$(subscription_authority "$domain" "$port")
  url="https://${authority}/${token}/mihomo"
  curl -kfsS --max-time 8 --resolve "${domain}:${port}:127.0.0.1" "$url" >/dev/null
}

enable_https_subscription() {
  ensure_state
  install_deps

  if [[ $(jq -r '(.nodes // {}) | length' "$STATE_FILE") -eq 0 ]]; then
    warn "当前没有节点，先部署至少一个节点后才能开启在线订阅。"
    return 1
  fi

  echo
  headmsg "安全 HTTPS 在线订阅"
  note "订阅文件只在本 VPS 生成；不会发送到第三方转换站。"
  note "访问路径使用 256-bit 随机 Token，错误路径统一返回 404。"
  warn "完整订阅 URL 本身就是凭据，请不要公开分享或提交到 GitHub。"

  local domain mode_choice proxy_mode port default_port token cert_mode old_config="" ans
  read -r -p "订阅域名（例如 sub.example.com）: " domain
  is_hostname "$domain" || die "HTTPS 订阅必须使用有效域名。"

  echo
  ui_item 1 "DNS only / 直连（推荐；默认 9443/TCP）"
  ui_item 2 "Cloudflare 橙云（仅 Cloudflare HTTPS 端口）"
  read -r -p "  接入方式 [1] › " mode_choice
  mode_choice=${mode_choice:-1}

  case "$mode_choice" in
    1)
      proxy_mode="direct"
      check_domain "$domain" direct
      default_port=9443
      ;;
    2)
      proxy_mode="cloudflare"
      check_domain "$domain" cloudflare
      default_port=$(subscription_default_cf_port)
      note "Cloudflare 模式默认端口：${default_port}/TCP。"
      warn "首次申请 Let's Encrypt 时若失败，请暂时切到 DNS only，签发成功后再开启橙云。"
      ;;
    *) die "无效接入方式。" ;;
  esac

  read -r -p "HTTPS 监听端口 [${default_port}]: " port
  port=${port:-$default_port}
  validate_port "$port" || die "端口必须为 1-65535。"
  if [[ "$proxy_mode" == cloudflare ]]; then
    subscription_cf_https_port "$port" \
      || die "Cloudflare 橙云仅支持 HTTPS 端口：443/2053/2083/2087/2096/8443。"
  fi

  if ! subscription_port_is_available "$port"; then
    warn "TCP/$port 已被占用："
    show_port_owner tcp "$port"
    die "请选择其他端口。"
  fi

  # Obtain/reuse certificate before installing nginx. This avoids a newly
  # installed distro nginx default site occupying TCP/80 during HTTP-01.
  subscription_select_certificate "$domain"
  cert_mode=$CERT_MODE

  generate_all_client_exports
  ensure_subscription_runtime
  publish_subscription_payloads

  token=$(random_hex 32)
  [[ ${#token} -ge 64 ]] || die "安全 Token 生成失败。"

  if [[ -f "$SUBSCRIPTION_CONFIG" ]]; then
    old_config=$(mktemp)
    cleanup_files+=("$old_config")
    cp -a "$SUBSCRIPTION_CONFIG" "$old_config"
  fi

  write_subscription_nginx_config "$domain" "$port" "$token" "$CERT_PATH" "$KEY_PATH"
  if ! validate_subscription_nginx_config; then
    [[ -n "$old_config" && -f "$old_config" ]] && cp -a "$old_config" "$SUBSCRIPTION_CONFIG"
    die "订阅 Nginx 配置校验失败，旧配置已保留。"
  fi

  systemctl daemon-reload
  if ! systemctl enable --now "$SUBSCRIPTION_SERVICE"; then
    [[ -n "$old_config" && -f "$old_config" ]] && cp -a "$old_config" "$SUBSCRIPTION_CONFIG"
    systemctl restart "$SUBSCRIPTION_SERVICE" >/dev/null 2>&1 || true
    die "HTTPS 订阅服务启动失败，已尝试恢复旧配置。"
  fi

  if ! subscription_local_healthcheck "$domain" "$port" "$token"; then
    journalctl -u "$SUBSCRIPTION_SERVICE" -n 60 --no-pager || true
    [[ -n "$old_config" && -f "$old_config" ]] && cp -a "$old_config" "$SUBSCRIPTION_CONFIG"
    systemctl restart "$SUBSCRIPTION_SERVICE" >/dev/null 2>&1 || true
    die "HTTPS 订阅本机健康检查失败，已尝试恢复旧配置。"
  fi

  subscription_state_write true "$domain" "$port" "$token" "$cert_mode" "$CERT_PATH" "$KEY_PATH" "$proxy_mode"
  allow_if_ufw_active "$port" tcp

  echo
  info "安全 HTTPS 在线订阅已启用。"
  note "云厂商安全组仍需放行 TCP/$port。"
  [[ "$proxy_mode" == cloudflare ]] && note "Cloudflare SSL/TLS 建议使用 Full (strict)。"
  echo
  read -r -p "现在显示完整订阅 URL？[y/N]: " ans
  if [[ ${ans,,} == y || ${ans,,} == yes ]]; then
    show_subscription_urls
  else
    show_https_subscription_status
  fi
}

show_https_subscription_status() {
  ensure_state
  echo
  headmsg "HTTPS 在线订阅状态"

  local enabled domain port token mode proxy_mode service_state cert authority
  enabled=$(jq -r '.subscription.enabled // false' "$STATE_FILE")
  domain=$(jq -r '.subscription.domain // "-"' "$STATE_FILE")
  port=$(jq -r '.subscription.port // "-"' "$STATE_FILE")
  token=$(jq -r '.subscription.token // empty' "$STATE_FILE")
  mode=$(jq -r '.subscription.certificate_mode // "-"' "$STATE_FILE")
  proxy_mode=$(jq -r '.subscription.proxy_mode // "direct"' "$STATE_FILE")
  cert=$(jq -r '.subscription.certificate_path // empty' "$STATE_FILE")
  service_state=$(systemctl is-active "$SUBSCRIPTION_SERVICE" 2>/dev/null || true)
  [[ -n "$service_state" ]] || service_state="inactive"

  printf '  %s %-14s %s\n' "$(ui_status_dot "$service_state")" "服务" "$service_state"
  printf '  %s %-14s %s\n' "$(ui_status_dot "$enabled")" "订阅" "$enabled"
  echo "     域名       : $domain"
  echo "     端口       : $port/TCP"
  echo "     接入       : $proxy_mode"
  echo "     证书       : $mode"
  echo "     Token      : $(subscription_mask_token "$token")"
  if [[ "$enabled" == true && "$domain" != - && "$port" != - ]]; then
    authority=$(subscription_authority "$domain" "$port")
    echo "     URL        : https://${authority}/<token>/{sing-box|mihomo|v2rayn}"
  fi

  if [[ -n "$cert" && -f "$cert" ]]; then
    echo
    openssl x509 -in "$cert" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/     /' || true
  fi
  echo
  warn "状态页默认隐藏完整 Token；只有“显示完整订阅 URL”才会输出秘密。"
}

show_subscription_urls() {
  ensure_state
  subscription_enabled || { warn "HTTPS 在线订阅当前未启用。"; return 0; }

  local domain port token authority
  domain=$(jq -r '.subscription.domain' "$STATE_FILE")
  port=$(jq -r '.subscription.port' "$STATE_FILE")
  token=$(jq -r '.subscription.token' "$STATE_FILE")
  authority=$(subscription_authority "$domain" "$port")

  echo
  headmsg "完整订阅 URL"
  warn "下面的 URL 包含高强度访问 Token，等同于节点凭据。"
  echo
  echo "  sing-box : https://${authority}/${token}/sing-box"
  echo "  Mihomo   : https://${authority}/${token}/mihomo"
  echo "  v2rayN   : https://${authority}/${token}/v2rayn"
  echo "  Raw URI  : https://${authority}/${token}/raw"
}

rotate_subscription_token() {
  ensure_state
  subscription_enabled || { warn "HTTPS 在线订阅当前未启用。"; return 0; }

  local domain port old_token new_token cert key mode proxy_mode old_config tmp
  domain=$(jq -r '.subscription.domain' "$STATE_FILE")
  port=$(jq -r '.subscription.port' "$STATE_FILE")
  old_token=$(jq -r '.subscription.token' "$STATE_FILE")
  cert=$(jq -r '.subscription.certificate_path' "$STATE_FILE")
  key=$(jq -r '.subscription.key_path' "$STATE_FILE")
  mode=$(jq -r '.subscription.certificate_mode' "$STATE_FILE")
  proxy_mode=$(jq -r '.subscription.proxy_mode // "direct"' "$STATE_FILE")
  new_token=$(random_hex 32)

  old_config=$(mktemp)
  cleanup_files+=("$old_config")
  cp -a "$SUBSCRIPTION_CONFIG" "$old_config"

  write_subscription_nginx_config "$domain" "$port" "$new_token" "$cert" "$key"
  if ! validate_subscription_nginx_config || ! systemctl reload "$SUBSCRIPTION_SERVICE"; then
    cp -a "$old_config" "$SUBSCRIPTION_CONFIG"
    systemctl reload "$SUBSCRIPTION_SERVICE" >/dev/null 2>&1 || systemctl restart "$SUBSCRIPTION_SERVICE" >/dev/null 2>&1 || true
    die "Token 轮换失败，已恢复旧 Token。"
  fi

  subscription_state_write true "$domain" "$port" "$new_token" "$mode" "$cert" "$key" "$proxy_mode"
  info "访问 Token 已轮换；旧订阅 URL 已立即失效。"
  show_subscription_urls
}

refresh_https_subscription() {
  subscription_enabled || { warn "HTTPS 在线订阅当前未启用。"; return 0; }
  generate_all_client_exports_quiet
  publish_subscription_payloads
  info "HTTPS 订阅内容已刷新。URL 和 Token 未变化。"
}

disable_https_subscription() {
  ensure_state
  subscription_enabled || { note "HTTPS 在线订阅已经是关闭状态。"; return 0; }
  local ans port tmp
  port=$(jq -r '.subscription.port // empty' "$STATE_FILE")
  warn "停用后所有在线订阅 URL 会立即不可访问；本地导出文件仍保留。"
  read -r -p "确认停用？[y/N]: " ans
  [[ ${ans,,} == y || ${ans,,} == yes ]] || { note "已取消。"; return 0; }

  systemctl disable --now "$SUBSCRIPTION_SERVICE" >/dev/null 2>&1 || true
  rm -f "$SUBSCRIPTION_CONFIG"
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq '.subscription.enabled=false | .subscription.updated_at=(now | todateiso8601)' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  info "HTTPS 在线订阅已停用。"
  [[ -n "$port" ]] && note "为避免误删其他服务规则，TCP/$port 的 UFW 规则未自动删除。"
}

subscription_logs() {
  journalctl -u "$SUBSCRIPTION_SERVICE" -n 120 --no-pager || true
}

subscription_menu() {
  echo
  headmsg "安全 HTTPS 在线订阅"
  note "HTTPS only · 256-bit Token · no-store · 精确路径 · 可轮换 · 可停用"
  echo
  ui_item 1 "启用 / 重新配置 HTTPS 私有订阅"
  ui_item 2 "刷新在线订阅内容"
  ui_item 3 "查看状态（Token 打码）"
  ui_item 4 "显示完整订阅 URL"
  ui_item 5 "轮换访问 Token（旧 URL 立即失效）"
  ui_item 6 "查看订阅服务日志"
  ui_item 7 "停用 HTTPS 在线订阅"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择操作 › " n

  case "$n" in
    1) enable_https_subscription ;;
    2) refresh_https_subscription ;;
    3) show_https_subscription_status ;;
    4) show_subscription_urls ;;
    5) rotate_subscription_token ;;
    6) subscription_logs ;;
    7) disable_https_subscription ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}
