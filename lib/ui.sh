#!/usr/bin/env bash
# shellcheck shell=bash

# Terminal UI helpers. Keep output readable in plain terminals and CI logs.
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_WHITE='\033[97m'
C_MAGENTA='\033[35m'

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
  read -r -p "  ↩  按 Enter 返回菜单..." _ || true
}

ui_rule() {
  echo -e "${C_DIM}────────────────────────────────────────────────────────────────${C_RESET}"
}

ui_banner() {
  echo -e "${C_CYAN}╭────────────────────────────────────────────────────────────────╮${C_RESET}"
  echo -e "  ${C_BOLD}${C_WHITE}sing-box oneclick${C_RESET}  ${C_CYAN}v${SCRIPT_VERSION}${C_RESET}"
  echo -e "  ${C_DIM}安全 · 多协议 · 可回滚 · 模块化管理${C_RESET}"
  echo -e "${C_CYAN}╰────────────────────────────────────────────────────────────────╯${C_RESET}"
}

ui_status_dot() {
  local state=${1:-unknown}
  case "$state" in
    active|yes|enabled|ok|true) echo -e "${C_GREEN}●${C_RESET}" ;;
    inactive|no|disabled|false|none|installed) echo -e "${C_YELLOW}●${C_RESET}" ;;
    *) echo -e "${C_RED}●${C_RESET}" ;;
  esac
}

ui_dashboard() {
  local sb_state="未安装" sb_dot="unknown" bbr="未启用" bbr_dot="no"
  local v4="无" v6="无" v4_dot="no" v6_dot="no" node_count=0 sb_ver="-"

  if have sing-box; then
    sb_state=$(systemctl is-active sing-box 2>/dev/null || true)
    [[ -n "$sb_state" ]] || sb_state="installed"
    sb_dot="$sb_state"
    sb_ver=$(sing-box version 2>/dev/null | head -n1 | sed 's/^sing-box version //' || true)
    [[ -n "$sb_ver" ]] || sb_ver="unknown"
  fi

  if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true) == "bbr" ]]; then
    bbr="BBR"
    bbr_dot="yes"
  fi
  if ip -4 route show default 2>/dev/null | grep -q .; then v4="有"; v4_dot="yes"; fi
  if ip -6 route show default 2>/dev/null | grep -q .; then v6="有"; v6_dot="yes"; fi
  if [[ -f "$STATE_FILE" ]] && have jq; then
    node_count=$(jq -r '(.nodes // {}) | length' "$STATE_FILE" 2>/dev/null || echo 0)
  fi

  echo -e "  $(ui_status_dot "$sb_dot") sing-box ${C_BOLD}${sb_state}${C_RESET} ${C_DIM}(${sb_ver})${C_RESET}    $(ui_status_dot "$bbr_dot") TCP ${bbr}"
  echo -e "  $(ui_status_dot "$v4_dot") IPv4 ${v4}    $(ui_status_dot "$v6_dot") IPv6 ${v6}    ${C_MAGENTA}◆${C_RESET} 节点 ${C_BOLD}${node_count}${C_RESET} 个"
}

ui_group() {
  echo
  echo -e "${C_BOLD}${C_MAGENTA}  $*${C_RESET}"
}

ui_item() {
  local n=$1 text=$2
  printf "  ${C_CYAN}%2s${C_RESET}  %s\n" "$n" "$text"
}

ui_node_overview() {
  ensure_state
  echo
  headmsg "节点概览"
  if ! jq -e '(.nodes // {}) | length > 0' "$STATE_FILE" >/dev/null 2>&1; then
    echo -e "  ${C_DIM}尚未部署脚本管理的节点。${C_RESET}"
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
    echo -e "  ${C_GREEN}●${C_RESET} ${C_BOLD}${name}${C_RESET}"
    echo -e "     ${C_DIM}${type} · ${addr}:${port}/${proto} · ${tls}${C_RESET}"
  done
}

ui_cli_help() {
  ui_banner
  echo
  headmsg "快捷命令"
  cat <<'HELP'
  sb                 打开交互式管理菜单
  sb status          服务状态 + 配置校验
  sb nodes           查看节点与分享链接
  sb qr              显示节点二维码
  sb logs            查看最近日志
  sb audit           完整安全自检
  sb bbr             查看 TCP BBR 状态
  sb cert            查看证书状态
  sb version         显示脚本与 sing-box 版本
  sb help            显示此帮助
HELP
}
