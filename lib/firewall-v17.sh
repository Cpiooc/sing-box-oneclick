#!/usr/bin/env bash
# shellcheck shell=bash

# Final UFW reconciliation layer for v1.7. The older firewall flow is kept for
# SSH preservation and Cloudflare prompts; this pass makes the node firewall
# mode explicit and fixes TCP+UDP nodes such as Shadowsocks generically.

reconcile_managed_ufw_rules() {
  have ufw || return 0
  ufw status 2>/dev/null | grep -q '^Status: active' || return 0
  [[ -f "$STATE_FILE" ]] || return 0

  local key port mode cf
  while IFS= read -r key; do
    port=$(jq -r --arg k "$key" '.nodes[$k].port // empty' "$STATE_FILE")
    mode=$(jq -r --arg k "$key" '.nodes[$k].firewall // empty' "$STATE_FILE")
    cf=$(jq -r --arg k "$key" '.nodes[$k].cloudflare // false' "$STATE_FILE")
    validate_port "$port" || continue

    case "$mode" in
      tcp)
        # Do not replace Cloudflare source-restricted rules with a world-open rule.
        if [[ "$cf" != true ]]; then
          ufw allow "${port}/tcp" >/dev/null || true
        fi
        ;;
      udp)
        ufw allow "${port}/udp" >/dev/null || true
        ;;
      both)
        ufw allow "${port}/tcp" >/dev/null || true
        ufw allow "${port}/udp" >/dev/null || true
        info "${key}: UFW 已同时放行 TCP/UDP/${port}。"
        ;;
      *)
        warn "${key}: 未识别的 firewall 模式 '${mode:-empty}'，未自动修改规则。"
        ;;
    esac
  done < <(jq -r '.nodes | keys[]' "$STATE_FILE")
}

firewall_setup_v17() {
  firewall_setup
  reconcile_managed_ufw_rules
}
