#!/usr/bin/env bash
# shellcheck shell=bash

# Loaded after client-export.sh and subscription.sh. These overrides keep
# local exports, published payloads, and the HTTPS service synchronized while
# applying defense-in-depth rules without complicating the core modules.

# A missing protocol is normal. Always return success after enumerating the
# nodes that actually exist, otherwise an ERR trap inside process substitution
# can turn a sparse node set into a false script error.
managed_export_keys() {
  ensure_state
  local key
  for key in reality hy2 tuic ws anytls trojan ss; do
    if jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1; then
      printf '%s\n' "$key"
    fi
  done
  return 0
}

purge_client_export_payloads() {
  rm -f "${CLIENT_EXPORT_DIR}/sing-box-client.json" \
        "${CLIENT_EXPORT_DIR}/mihomo.yaml" \
        "${CLIENT_EXPORT_DIR}/v2rayn-subscription.txt" \
        "${CLIENT_EXPORT_DIR}/v2rayn-subscription-base64.txt"
  if [[ -n "${SUBSCRIPTION_PUBLISH_DIR:-}" ]]; then
    rm -f "${SUBSCRIPTION_PUBLISH_DIR}/sing-box-client.json" \
          "${SUBSCRIPTION_PUBLISH_DIR}/mihomo.yaml" \
          "${SUBSCRIPTION_PUBLISH_DIR}/v2rayn-subscription.txt" \
          "${SUBSCRIPTION_PUBLISH_DIR}/v2rayn-subscription-base64.txt"
  fi
}

refresh_client_exports_if_present() {
  [[ -f "$CLIENT_EXPORT_MARKER" ]] || return 0

  if [[ $(jq -r '(.nodes // {}) | length' "$STATE_FILE" 2>/dev/null || echo 0) -eq 0 ]]; then
    purge_client_export_payloads
    note "已删除最后一个节点，本地导出与 HTTPS 发布副本中的旧节点凭据已清理。"
    return 0
  fi

  if ! generate_all_client_exports_quiet; then
    warn "节点已修改，但本地客户端导出自动刷新失败；请稍后运行 sb export 手工刷新。"
    return 0
  fi

  if subscription_enabled; then
    publish_subscription_payloads || {
      warn "本地导出已刷新，但 HTTPS 在线订阅内容同步失败；请运行 sb sub 手工刷新。"
      return 0
    }
  fi
  return 0
}

harden_subscription_nginx_config() {
  [[ -f "$SUBSCRIPTION_CONFIG" ]] || return 1
  # The access path contains the bearer Token. Never persist it in Nginx or
  # journald access logs. Suppress normal missing-file logging as well, because
  # Nginx error entries can include the original request URI.
  sed -i 's|^[[:space:]]*access_log /dev/stdout combined;|    access_log off;|' "$SUBSCRIPTION_CONFIG"
  sed -i 's|^error_log stderr warn;|error_log stderr error;|' "$SUBSCRIPTION_CONFIG"
  if ! grep -Fq 'log_not_found off;' "$SUBSCRIPTION_CONFIG"; then
    sed -i '/^[[:space:]]*server_name /a\        log_not_found off;' "$SUBSCRIPTION_CONFIG"
  fi
  chmod 600 "$SUBSCRIPTION_CONFIG"
}

validate_subscription_nginx_config() {
  local nginx_bin
  harden_subscription_nginx_config || return 1
  nginx_bin=$(subscription_nginx_bin)
  [[ -n "$nginx_bin" ]] || die "未找到 nginx。"

  # systemd creates RuntimeDirectory before ExecStartPre, but the installer
  # performs an nginx -t before the service has ever started. A fresh VPS has
  # no /run/sing-box-oneclick-subscription yet, so create only the parent
  # directory needed for the manual validation. systemd still owns its normal
  # lifecycle after the service starts and after reboot.
  install -d -m 0755 "$SUBSCRIPTION_RUNTIME_DIR" || return 1
  "$nginx_bin" -t -q -c "$SUBSCRIPTION_CONFIG"
}

# Override the generic UFW helper only for the active Cloudflare subscription
# origin. This makes the origin port reachable from Cloudflare edges but not
# directly from arbitrary Internet hosts. All other callers keep the original
# behavior.
allow_if_ufw_active() {
  local port=$1 proto=$2 sub_enabled=false sub_port="" sub_mode=""
  if [[ -f "${STATE_FILE:-}" ]] && have jq; then
    sub_enabled=$(jq -r '.subscription.enabled // false' "$STATE_FILE" 2>/dev/null || echo false)
    sub_port=$(jq -r '.subscription.port // empty' "$STATE_FILE" 2>/dev/null || true)
    sub_mode=$(jq -r '.subscription.proxy_mode // empty' "$STATE_FILE" 2>/dev/null || true)
  fi

  if [[ "$proto" == tcp && "$sub_enabled" == true && "$sub_port" == "$port" && "$sub_mode" == cloudflare ]]; then
    if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
      ufw_allow_cloudflare_only "$port"
      info "HTTPS 订阅源站 TCP/$port 已限制为仅 Cloudflare 官方边缘 IP 可访问。"
    else
      warn "UFW 当前未启用。Cloudflare 订阅源站建议之后配置 UFW 源地址限制。"
    fi
    return 0
  fi

  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "${port}/${proto}" >/dev/null || true
    info "UFW 已放行 ${proto^^}/$port。"
  else
    warn "UFW 当前未启用。请确认云厂商安全组已放行 ${proto^^}/$port。"
  fi
}

write_export_readme() {
  ensure_client_export_dir
  local online="disabled"
  subscription_enabled && online="enabled"
  cat > "${CLIENT_EXPORT_DIR}/README.txt" <<EOF
sing-box-oneclick client exports
Generated: $(date -Is 2>/dev/null || date)

Files:
  sing-box-client.json           sing-box client, local mixed proxy 127.0.0.1:2080
  mihomo.yaml                    Mihomo / Clash.Meta-compatible client config
  v2rayn-subscription.txt        Standard VLESS / Hysteria2 / TUIC share-link content
  v2rayn-subscription-base64.txt Legacy-compatible Base64 form

Security:
  Root-only export directory: ${CLIENT_EXPORT_DIR}
  HTTPS private subscription: ${online}
  These files contain UUIDs/passwords. Do not upload them to a public repository
  or an untrusted subscription converter.
  If HTTPS publishing is enabled, manage it with: sb sub
EOF
  chmod 600 "${CLIENT_EXPORT_DIR}/README.txt"
}

show_client_export_status() {
  ensure_client_export_dir
  echo
  headmsg "本地客户端配置 / 订阅"
  echo -e "  ${C_DIM}目录：${CLIENT_EXPORT_DIR}${C_RESET}"
  echo

  local f
  for f in sing-box-client.json mihomo.yaml v2rayn-subscription.txt v2rayn-subscription-base64.txt README.txt; do
    if [[ -f "${CLIENT_EXPORT_DIR}/${f}" ]]; then
      printf '  %s %-36s %s\n' "$(ui_status_dot yes)" "$f" "$(stat -c '%y' "${CLIENT_EXPORT_DIR}/${f}" 2>/dev/null | cut -d. -f1)"
    else
      printf '  %s %-36s %s\n' "$(ui_status_dot no)" "$f" "未生成"
    fi
  done

  echo
  if [[ -f "$CLIENT_EXPORT_MARKER" ]]; then
    note "本地自动刷新已启用：脚本管理的节点发生变化后会尽量同步导出文件。"
  fi
  if subscription_enabled; then
    info "HTTPS 私有订阅已启用；节点变化后会同步低权限发布副本。"
    note "完整 URL 默认不在这里显示，请使用 sb sub -> 显示完整订阅 URL。"
  else
    note "当前未开启公网订阅；需要时运行 sb sub。"
  fi
  warn "本地导出文件包含节点凭据，请像私钥一样保护。"
}

certificate_status() {
  ensure_state
  local keys=() key name mode tls cert domain sub_cert sub_domain sub_mode sub_port sub_enabled shown=0
  mapfile -t keys < <(jq -r '.nodes | to_entries[] | select((.value.certificate==true) or (.value.tls_enabled==true)) | .key' "$STATE_FILE")

  for key in "${keys[@]}"; do
    shown=1
    name=$(jq -r --arg k "$key" '.nodes[$k].name // $k' "$STATE_FILE")
    mode=$(jq -r --arg k "$key" '.nodes[$k].certificate_mode // "acme/legacy"' "$STATE_FILE")
    tls=$(jq -r --arg k "$key" '.nodes[$k].tls_enabled // true' "$STATE_FILE")
    cert=$(jq -r --arg k "$key" '.nodes[$k].certificate_path // empty' "$STATE_FILE")
    domain=$(jq -r --arg k "$key" '.nodes[$k].domain // empty' "$STATE_FILE")
    [[ -z "$cert" && "$mode" == "acme/legacy" && -n "$domain" ]] && cert="/etc/letsencrypt/live/${domain}/fullchain.pem"

    echo
    headmsg "$name"
    echo "TLS       : $tls"
    echo "证书模式  : $mode"
    echo "SNI/名称  : ${domain:-无}"
    if [[ "$tls" == true && -n "$cert" ]]; then
      echo "证书路径  : $cert"
      openssl x509 -in "$cert" -noout -subject -issuer -serial -dates 2>/dev/null || warn "证书不存在或不可读。"
    fi
  done

  sub_cert=$(jq -r '.subscription.certificate_path // empty' "$STATE_FILE")
  if [[ -n "$sub_cert" ]]; then
    shown=1
    sub_domain=$(jq -r '.subscription.domain // "-"' "$STATE_FILE")
    sub_mode=$(jq -r '.subscription.certificate_mode // "-"' "$STATE_FILE")
    sub_port=$(jq -r '.subscription.port // "-"' "$STATE_FILE")
    sub_enabled=$(jq -r '.subscription.enabled // false' "$STATE_FILE")
    echo
    headmsg "HTTPS 私有订阅"
    echo "状态      : $sub_enabled"
    echo "域名      : $sub_domain"
    echo "端口      : $sub_port/TCP"
    echo "证书模式  : $sub_mode"
    echo "证书路径  : $sub_cert"
    openssl x509 -in "$sub_cert" -noout -subject -issuer -serial -dates 2>/dev/null || warn "订阅证书不存在或不可读。"
  fi

  if (( shown == 0 )); then
    warn "没有脚本管理的普通 TLS 证书或 HTTPS 订阅证书。Reality 不使用普通证书。"
  fi

  echo
  systemctl status certbot.timer --no-pager -l 2>/dev/null | sed -n '1,12p' || true
}

disable_https_subscription() {
  ensure_state
  subscription_enabled || { note "HTTPS 在线订阅已经是关闭状态。"; return 0; }
  local ans port tmp
  port=$(jq -r '.subscription.port // empty' "$STATE_FILE")
  warn "停用后所有在线订阅 URL 会立即不可访问；root-only 本地导出文件仍保留。"
  read -r -p "确认停用？[y/N]: " ans
  [[ ${ans,,} == y || ${ans,,} == yes ]] || { note "已取消。"; return 0; }

  systemctl disable --now "$SUBSCRIPTION_SERVICE" >/dev/null 2>&1 || true
  rm -f "$SUBSCRIPTION_CONFIG"
  rm -f "${SUBSCRIPTION_PUBLISH_DIR}/sing-box-client.json" \
        "${SUBSCRIPTION_PUBLISH_DIR}/mihomo.yaml" \
        "${SUBSCRIPTION_PUBLISH_DIR}/v2rayn-subscription.txt" \
        "${SUBSCRIPTION_PUBLISH_DIR}/v2rayn-subscription-base64.txt"

  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq '.subscription.enabled=false | .subscription.updated_at=(now | todateiso8601)' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  info "HTTPS 在线订阅已停用，低权限发布副本已删除。"
  [[ -n "$port" ]] && note "为避免误删其他服务规则，TCP/$port 的 UFW 规则未自动删除。"
}
