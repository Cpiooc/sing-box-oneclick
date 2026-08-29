#!/usr/bin/env bash
# shellcheck shell=bash

# Loaded after client-export.sh and subscription.sh. This intentionally
# overrides the local-export refresh hook so node changes update both the
# root-only export set and the low-privilege HTTPS publish set.
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
