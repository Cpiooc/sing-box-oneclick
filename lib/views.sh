#!/usr/bin/env bash
# shellcheck shell=bash

show_nodes() {
  ensure_state
  render_node_info
  local keys key name type address port proto tls_mode uri
  mapfile -t keys < <(jq -r '.nodes | keys[]' "$STATE_FILE")

  echo
  headmsg "节点与分享链接"
  if (( ${#keys[@]} == 0 )); then
    warn "尚未创建脚本管理的节点。"
    return 0
  fi

  for key in "${keys[@]}"; do
    name=$(jq -r --arg k "$key" '.nodes[$k].name // $k' "$STATE_FILE")
    type=$(jq -r --arg k "$key" '.nodes[$k].type // "unknown"' "$STATE_FILE")
    address=$(jq -r --arg k "$key" '.nodes[$k].address // "-"' "$STATE_FILE")
    port=$(jq -r --arg k "$key" '.nodes[$k].port // "-"' "$STATE_FILE")
    proto=$(jq -r --arg k "$key" '.nodes[$k].firewall // "-"' "$STATE_FILE" | tr '[:lower:]' '[:upper:]')
    tls_mode=$(jq -r --arg k "$key" '.nodes[$k].certificate_mode // (if .nodes[$k].tls_enabled == false then "off" elif .nodes[$k].certificate == true then "tls" else "-" end)' "$STATE_FILE")
    uri=$(jq -r --arg k "$key" '.nodes[$k].uri // empty' "$STATE_FILE")

    echo
    echo -e "  ${C_GREEN}●${C_RESET} ${C_BOLD}${name}${C_RESET}  ${C_DIM}[${key}]${C_RESET}"
    echo -e "     类型    ${type}"
    echo -e "     入口    ${C_CYAN}${address}:${port}/${proto}${C_RESET}"
    echo -e "     TLS     ${tls_mode}"

    case "$key" in
      reality)
        echo -e "     SNI     $(jq -r '.nodes.reality.reality_sni // "-"' "$STATE_FILE")"
        ;;
      hy2)
        echo -e "     SNI     $(jq -r '.nodes.hy2.domain // "-"' "$STATE_FILE")"
        ;;
      tuic)
        echo -e "     SNI     $(jq -r '.nodes.tuic.domain // "-"' "$STATE_FILE")"
        echo -e "     CC      $(jq -r '.nodes.tuic.congestion_control // "-"' "$STATE_FILE")"
        ;;
      ws)
        echo -e "     Path    $(jq -r '.nodes.ws.path // "-"' "$STATE_FILE")"
        ;;
    esac

    if [[ -n "$uri" ]]; then
      echo -e "     ${C_DIM}分享链接${C_RESET}"
      echo -e "     ${C_WHITE}${uri}${C_RESET}"
    fi
  done
  echo
  note "完整节点信息同时保存在 $NODE_INFO（权限 600）。"
}

show_qr_codes() {
  ensure_state
  have qrencode || apt-get install -y qrencode
  local keys key uri name
  mapfile -t keys < <(jq -r '.nodes | keys[]' "$STATE_FILE")
  if (( ${#keys[@]} == 0 )); then
    warn "没有节点。"
    return 0
  fi

  echo
  headmsg "节点二维码"
  for key in "${keys[@]}"; do
    uri=$(jq -r --arg key "$key" '.nodes[$key].uri // empty' "$STATE_FILE")
    name=$(jq -r --arg key "$key" '.nodes[$key].name // $key' "$STATE_FILE")
    [[ -n "$uri" ]] || continue
    echo
    ui_rule
    echo -e "  ${C_BOLD}${name}${C_RESET}"
    echo
    qrencode -t ANSIUTF8 "$uri" || true
    echo -e "${C_DIM}${uri}${C_RESET}"
  done
}

show_status() {
  ensure_singbox
  local state enabled pid since
  state=$(systemctl is-active sing-box 2>/dev/null || true)
  enabled=$(systemctl is-enabled sing-box 2>/dev/null || true)
  pid=$(systemctl show sing-box -p MainPID --value 2>/dev/null || echo 0)
  since=$(systemctl show sing-box -p ActiveEnterTimestamp --value 2>/dev/null || true)

  echo
  headmsg "sing-box 运行状态"
  if [[ "$state" == "active" ]]; then
    info "服务状态：active"
  else
    warn "服务状态：${state:-unknown}"
  fi
  echo "  开机启动 : ${enabled:-unknown}"
  echo "  主进程   : ${pid:-0}"
  echo "  启动时间 : ${since:-unknown}"
  echo "  版本     : $(sing-box version 2>/dev/null | head -n1 || echo unknown)"
  echo "  重载能力 : $(singbox_can_reload && echo 'SIGHUP hot-reload' || echo 'restart fallback')"

  echo
  headmsg "配置检查"
  if [[ -f "$CONFIG_FILE" ]] && sing-box check -c "$CONFIG_FILE"; then
    info "配置校验通过：$CONFIG_FILE"
  else
    err "配置校验失败或配置文件不存在。"
  fi

  ui_node_overview

  echo
  headmsg "监听端口"
  if ! ss -lntup 2>/dev/null | grep sing-box; then
    warn "没有观察到 sing-box 监听端口。"
  fi

  if [[ "$state" != "active" ]]; then
    echo
    headmsg "最近错误日志"
    journalctl -u sing-box -n 30 --no-pager -p warning 2>/dev/null || true
  fi
}

show_logs() {
  ensure_singbox
  echo
  headmsg "sing-box 最近 120 行日志"
  echo -e "${C_DIM}  提示：Ctrl+C 可结束持续查看；当前页面只显示最近日志。${C_RESET}"
  echo
  journalctl -u sing-box -n 120 --no-pager -o short-iso 2>/dev/null || true
}

network_diagnostics() {
  echo
  headmsg "网络诊断"
  show_ip_info

  echo
  headmsg "默认路由"
  echo -e "${C_CYAN}IPv4${C_RESET}"
  ip -4 route show default 2>/dev/null || echo "  无 IPv4 默认路由"
  echo -e "${C_CYAN}IPv6${C_RESET}"
  ip -6 route show default 2>/dev/null || echo "  无 IPv6 默认路由"

  echo
  headmsg "DNS"
  sed -n '1,20p' /etc/resolv.conf 2>/dev/null || true

  echo
  headmsg "sing-box 监听"
  ss -lntup 2>/dev/null | grep sing-box || warn "当前未观察到 sing-box 监听。"

  bbr_status
}

bbr_status() {
  echo
  headmsg "TCP BBR 状态"
  local available cc qdisc virt
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
  qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || true)
  virt=$(systemd-detect-virt 2>/dev/null || true)

  echo "  内核       : $(uname -r)"
  echo "  虚拟化     : ${virt:-none/unknown}"
  echo "  可用算法   : ${available:-unknown}"
  echo "  当前算法   : ${cc:-unknown}"
  echo "  默认 qdisc : ${qdisc:-unknown}"

  if grep -qw bbr <<< "$available" && [[ "$cc" == "bbr" ]]; then
    info "TCP BBR 已生效。"
  else
    warn "TCP BBR 当前未完全生效。"
  fi
  [[ "$qdisc" == "fq" ]] && info "默认 qdisc = fq。" || warn "默认 qdisc 不是 fq。"
  note "HY2/TUIC 使用 QUIC/UDP，不使用 Linux TCP BBR。"
}

certificate_status() {
  ensure_state
  local keys key name domain mode cert end end_epoch now days
  mapfile -t keys < <(jq -r '.nodes | to_entries[] | select(.value.certificate == true) | .key' "$STATE_FILE")

  echo
  headmsg "TLS 证书状态"
  if (( ${#keys[@]} == 0 )); then
    warn "没有脚本管理的证书节点。"
    return 0
  fi

  for key in "${keys[@]}"; do
    name=$(jq -r --arg k "$key" '.nodes[$k].name // $k' "$STATE_FILE")
    domain=$(jq -r --arg k "$key" '.nodes[$k].domain // .nodes[$k].address // "-"' "$STATE_FILE")
    mode=$(jq -r --arg k "$key" '.nodes[$k].certificate_mode // "legacy/acme"' "$STATE_FILE")
    cert=$(jq -r --arg k "$key" '.nodes[$k].certificate_path // empty' "$STATE_FILE")
    if [[ -z "$cert" && "$domain" != "-" ]]; then
      cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    fi

    echo
    echo -e "  ${C_GREEN}●${C_RESET} ${C_BOLD}${name}${C_RESET}"
    echo "     名称/域名 : $domain"
    echo "     模式      : $mode"
    echo "     文件      : ${cert:-未知}"

    if [[ -n "$cert" && -r "$cert" ]]; then
      openssl x509 -in "$cert" -noout -subject -issuer 2>/dev/null | sed 's/^/     /'
      end=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2- || true)
      echo "     到期      : ${end:-unknown}"
      if [[ -n "$end" ]]; then
        end_epoch=$(date -d "$end" +%s 2>/dev/null || echo 0)
        now=$(date +%s)
        if (( end_epoch > 0 )); then
          days=$(( (end_epoch - now) / 86400 ))
          if (( days < 15 )); then
            warn "${name} 证书约 ${days} 天后到期。"
          else
            info "${name} 证书剩余约 ${days} 天。"
          fi
        fi
      fi
    else
      err "证书文件不存在或不可读。"
    fi
  done

  echo
  if systemctl is-enabled certbot.timer >/dev/null 2>&1; then
    info "Certbot 自动续期 timer 已启用。"
  else
    note "未启用 Certbot timer；自签/自定义证书不需要它，ACME 节点则建议检查。"
  fi
}
