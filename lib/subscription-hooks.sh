#!/usr/bin/env bash
# shellcheck shell=bash

# Loaded after client-export.sh and subscription.sh. These overrides keep
# local exports, published payloads, and the HTTPS service synchronized while
# applying a few defense-in-depth rules without complicating the core module.

refresh_client_exports_if_present() {
  [[ -f "$CLIENT_EXPORT_MARKER" ]] || return 0

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
  # journald access logs. Error logging remains enabled for diagnostics.
  sed -i 's|^[[:space:]]*access_log /dev/stdout combined;|    access_log off;|' "$SUBSCRIPTION_CONFIG"
  chmod 600 "$SUBSCRIPTION_CONFIG"
}

validate_subscription_nginx_config() {
  local nginx_bin
  harden_subscription_nginx_config || return 1
  nginx_bin=$(subscription_nginx_bin)
  [[ -n "$nginx_bin" ]] || die "未找到 nginx。"
  "$nginx_bin" -t -q -c "$SUBSCRIPTION_CONFIG"
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
