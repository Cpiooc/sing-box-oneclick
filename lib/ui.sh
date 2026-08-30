#!/usr/bin/env bash
# shellcheck shell=bash

# Terminal UI system. Keep it dependency-free, readable over SSH and graceful
# when colors are disabled in CI or dumb terminals.
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_WHITE='\033[97m'
C_MAGENTA='\033[35m'
C_GRAY='\033[90m'

if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
  C_RESET=''
  C_RED=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
  C_CYAN=''
  C_BOLD=''
  C_DIM=''
  C_WHITE=''
  C_MAGENTA=''
  C_GRAY=''
fi

ui_strip_title() {
  local text="$*"
  text=${text#===== }
  text=${text% =====}
  printf '%s' "$text"
}

info() { echo -e "${C_GREEN}✓${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}!${C_RESET} $*"; }
err()  { echo -e "${C_RED}✗${C_RESET} $*" >&2; }
note() { echo -e "${C_CYAN}•${C_RESET} $*"; }

headmsg() {
  local text
  text=$(ui_strip_title "$*")
  echo -e "${C_BOLD}${C_BLUE}◆ ${text}${C_RESET}"
}

pause() {
  echo
  echo -e "${C_DIM}  ───────────────────────────────────────────────────────────${C_RESET}"
  read -r -p "  ↩  按 Enter 返回控制台..." _ || true
}

ui_rule() {
  echo -e "${C_DIM}  ───────────────────────────────────────────────────────────${C_RESET}"
}

ui_banner() {
  echo -e "${C_CYAN}╭──────────────────────────────────────────────────────────────────╮${C_RESET}"
  echo -e "${C_CYAN}│${C_RESET}  ${C_BOLD}${C_WHITE}SING-BOX ONECLICK${C_RESET}                                      ${C_CYAN}v${SCRIPT_VERSION}${C_RESET}  ${C_CYAN}│${C_RESET}"
  echo -e "${C_CYAN}│${C_RESET}  ${C_DIM}Secure Gateway Manager · safe changes · local-first${C_RESET}           ${C_CYAN}│${C_RESET}"
  echo -e "${C_CYAN}╰──────────────────────────────────────────────────────────────────╯${C_RESET}"
}

ui_status_dot() {
  local state=${1:-unknown}
  case "$state" in
    active|yes|enabled|ok|true|online) echo -e "${C_GREEN}●${C_RESET}" ;;
    inactive|no|disabled|false|none|installed|off) echo -e "${C_YELLOW}●${C_RESET}" ;;
    *) echo -e "${C_RED}●${C_RESET}" ;;
  esac
}

ui_badge() {
  local label=$1 value=$2 state=${3:-yes}
  printf '%b %s %b%s%b' "$(ui_status_dot "$state")" "$label" "$C_BOLD" "$value" "$C_RESET"
}

ui_dashboard() {
  local sb_state="未安装" sb_dot="unknown" bbr="OFF" bbr_dot="no"
  local v4="OFF" v6="OFF" v4_dot="no" v6_dot="no" node_count=0 sb_ver="-"
  local sub_state="OFF" sub_dot="no" sub_port="-"

  if have sing-box; then
    sb_state=$(systemctl is-active sing-box 2>/dev/null || true)
    [[ -n "$sb_state" ]] || sb_state="installed"
    sb_dot="$sb_state"
    sb_ver=$(sing-box version 2>/dev/null | head -n1 | sed 's/^sing-box version //' || true)
    [[ -n "$sb_ver" ]] || sb_ver="unknown"
  fi
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true) == "bbr" ]]; then
    bbr="ON"; bbr_dot="yes"
  fi
  if ip -4 route show default 2>/dev/null | grep -q .; then v4="ON"; v4_dot="yes"; fi
  if ip -6 route show default 2>/dev/null | grep -q .; then v6="ON"; v6_dot="yes"; fi
  if [[ -f "$STATE_FILE" ]] && have jq; then
    node_count=$(jq -r '(.nodes // {}) | length' "$STATE_FILE" 2>/dev/null || echo 0)
    if [[ $(jq -r '.subscription.enabled // false' "$STATE_FILE" 2>/dev/null || echo false) == true ]]; then
      sub_state="HTTPS"; sub_dot="yes"
      sub_port=$(jq -r '.subscription.port // "-"' "$STATE_FILE" 2>/dev/null || echo -)
    fi
  fi

  echo
  echo -e "  ${C_DIM}CORE${C_RESET}  $(ui_badge "sing-box" "$sb_state" "$sb_dot")  ${C_DIM}v${sb_ver}${C_RESET}     $(ui_badge "BBR" "$bbr" "$bbr_dot")"
  echo -e "  ${C_DIM}NET ${C_RESET}  $(ui_badge "IPv4" "$v4" "$v4_dot")        $(ui_badge "IPv6" "$v6" "$v6_dot")        ${C_MAGENTA}◆${C_RESET} Nodes ${C_BOLD}${node_count}${C_RESET}"
  echo -e "  ${C_DIM}SUB ${C_RESET}  $(ui_badge "Private" "$sub_state" "$sub_dot")${sub_port:+  ${C_DIM}TCP/${sub_port}${C_RESET}}"
}

ui_group() {
  local title=$1 hint=${2:-}
  echo
  echo -e "  ${C_BOLD}${C_MAGENTA}┌─ ${title}${C_RESET}${hint:+  ${C_DIM}${hint}${C_RESET}}"
}

ui_item() {
  local n=$1 text=$2 hint=${3:-}
  if [[ -n "$hint" ]]; then
    printf "  ${C_MAGENTA}│${C_RESET} ${C_CYAN}%2s${C_RESET}  %s  ${C_DIM}· %s${C_RESET}\n" "$n" "$text" "$hint"
  else
    printf "  ${C_MAGENTA}│${C_RESET} ${C_CYAN}%2s${C_RESET}  %s\n" "$n" "$text"
  fi
}

ui_group_end() {
  echo -e "  ${C_MAGENTA}└────────────────────────────────────────────────────────────${C_RESET}"
}

ui_kv() {
  local key=$1 value=$2
  printf "  ${C_DIM}%-12s${C_RESET} %s\n" "$key" "$value"
}

ui_node_overview() {
  ensure_state
  echo
  headmsg "节点概览"
  if ! jq -e '(.nodes // {}) | length > 0' "$STATE_FILE" >/dev/null 2>&1; then
    echo -e "  ${C_DIM}暂无脚本管理节点。${C_RESET}"
    return 0
  fi

  jq -r '
    (.nodes // {}) | to_entries[] |
    [
      (.value.name // .key),
      (.value.type // "unknown"),
      ((.value.address // "-") | tostring),
      ((.value.port // "-") | tostring),
      ((.value.firewall // "-") | ascii_upcase),
      (.value.certificate_mode // (if .value.tls_enabled == false then "TLS off" elif .value.certificate == true then "TLS" else "-" end))
    ] | @tsv
  ' "$STATE_FILE" 2>/dev/null | while IFS=$'\t' read -r name type addr port proto tls; do
    echo -e "  ${C_GREEN}●${C_RESET} ${C_BOLD}${name}${C_RESET}  ${C_DIM}${type}${C_RESET}"
    echo -e "     ${C_CYAN}${addr}:${port}${C_RESET}  ${C_DIM}${proto} · ${tls}${C_RESET}"
  done
}

ui_cli_help() {
  ui_banner
  echo
  headmsg "快捷命令"
  cat <<'HELP'
  sb                 打开交互式管理控制台
  sb status          服务状态 + 配置校验
  sb nodes           节点概览 + 分享链接
  sb edit            原地修改节点参数
  sb export          本地生成 sing-box / Mihomo / v2rayN 配置
  sb sub             管理安全 HTTPS 私有订阅
  sb anytls          部署 / 重建 AnyTLS
  sb trojan          部署 / 重建 Trojan
  sb ss              部署 / 重建 Shadowsocks
  sb qr              显示节点二维码
  sb logs            查看最近日志
  sb audit           完整安全自检
  sb bbr             查看 TCP BBR 状态
  sb cert            查看证书状态
  sb version         显示脚本与 sing-box 版本
  sb help            显示此帮助
HELP
}
