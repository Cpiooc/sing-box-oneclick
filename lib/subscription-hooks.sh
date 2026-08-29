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
