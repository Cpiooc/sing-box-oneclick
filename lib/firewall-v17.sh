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

# Hysteria2 hopping uses `server_ports`, which conflicts with `server_port`
# in sing-box. hy2-hop.sh starts from the normal single-port outbound and adds
# server_ports; this final compatibility wrapper removes server_port only when
# hopping is enabled. Keeping the fix in this late-loaded module also protects
# future export extensions from accidentally reintroducing the conflict.
if declare -F singbox_outbound_for_key >/dev/null 2>&1; then
  eval "$(declare -f singbox_outbound_for_key | sed '1s/singbox_outbound_for_key/singbox_outbound_for_key_pre_v17_safe/')"
fi

singbox_outbound_for_key() {
  local key=$1 out
  out=$(singbox_outbound_for_key_pre_v17_safe "$@") || return $?
  if [[ "$key" == hy2 ]] \
      && declare -F hy2_hop_enabled >/dev/null 2>&1 \
      && hy2_hop_enabled; then
    jq 'del(.server_port)' <<< "$out"
  else
    printf '%s\n' "$out"
  fi
}

# Make systemd resilience visible in `sb doctor`. The official sing-box unit
# already provides Restart=on-failure; this check is deliberately read-only and
# does not add a watchdog or automatically restart a healthy service.
doctor_check_systemd_resilience() {
  local enabled restart_policy restart_delay

  enabled=$(systemctl is-enabled sing-box 2>/dev/null || true)
  if [[ "$enabled" == "enabled" ]]; then
    doctor_ok "sing-box 开机自启：enabled"
  else
    doctor_warn "sing-box 开机自启：${enabled:-unknown}；如需开启：systemctl enable sing-box"
  fi

  restart_policy=$(systemctl show sing-box -p Restart --value 2>/dev/null || true)
  restart_delay=$(systemctl show sing-box -p RestartUSec --value 2>/dev/null || true)
  [[ -n "$restart_delay" ]] || restart_delay="unknown"

  if [[ "$restart_policy" == "on-failure" ]]; then
    doctor_ok "sing-box 崩溃自动恢复：on-failure / ${restart_delay}"
  else
    doctor_warn "sing-box 崩溃自动恢复：${restart_policy:-unknown} / ${restart_delay}；建议运行 sb → 1 安装 / 修复 sing-box"
  fi
}

# usability.sh owns the main doctor implementation and is loaded immediately
# before this module. Inject the resilience check just before its PASS/WARN/FAIL
# summary so these two checks are counted in the final result without copying
# the entire doctor function into another module.
if declare -F doctor >/dev/null 2>&1; then
  _doctor_definition=$(declare -f doctor)
  _doctor_definition=$(printf '%s\n' "$_doctor_definition" | sed '/^[[:space:]]*ui_rule[[:space:]]*;[[:space:]]*$/i\    doctor_check_systemd_resilience')
  eval "$_doctor_definition"
  unset _doctor_definition
fi
