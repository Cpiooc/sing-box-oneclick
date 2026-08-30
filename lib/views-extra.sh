#!/usr/bin/env bash
# shellcheck shell=bash

# Richer node cards for v1.6. Loaded after views.sh.
show_nodes() {
  ensure_state
  render_node_info
  local keys key name type address port proto tls_mode uri detail
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
    echo -e "  ${C_CYAN}╭────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_GREEN}●${C_RESET} ${C_BOLD}${name}${C_RESET}  ${C_DIM}[${key}]${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}${type}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}入口${C_RESET}  ${C_WHITE}${address}:${port}${C_RESET}  ${C_DIM}${proto}${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}TLS ${C_RESET}  ${tls_mode}"

    case "$key" in
      reality)
        detail=$(jq -r '.nodes.reality.reality_sni // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· Vision + Reality${C_RESET}"
        ;;
      hy2)
        detail=$(jq -r '.nodes.hy2.domain // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· QUIC + Salamander${C_RESET}"
        ;;
      tuic)
        detail=$(jq -r '.nodes.tuic.domain // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}"
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}CC  ${C_RESET}  $(jq -r '.nodes.tuic.congestion_control // "-"' "$STATE_FILE")"
        ;;
      ws)
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}Path${C_RESET}  $(jq -r '.nodes.ws.path // "-"' "$STATE_FILE")  ${C_DIM}· Cloudflare${C_RESET}"
        ;;
      anytls)
        detail=$(jq -r '.nodes.anytls.domain // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· native AnyTLS${C_RESET}"
        ;;
      trojan)
        detail=$(jq -r '.nodes.trojan.domain // "-"' "$STATE_FILE")
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}SNI ${C_RESET}  ${detail}  ${C_DIM}· native Trojan${C_RESET}"
        ;;
      ss)
        echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}Cipher${C_RESET} $(jq -r '.nodes.ss.method // "-"' "$STATE_FILE")  ${C_DIM}· TCP + UDP${C_RESET}"
        ;;
    esac

    if [[ -n "$uri" ]]; then
      echo -e "  ${C_CYAN}│${C_RESET}"
      echo -e "  ${C_CYAN}│${C_RESET} ${C_DIM}分享链接${C_RESET}"
      echo -e "  ${C_CYAN}│${C_RESET} ${C_WHITE}${uri}${C_RESET}"
    fi
    echo -e "  ${C_CYAN}╰────────────────────────────────────────────────────────────╯${C_RESET}"
  done
  echo
  note "完整节点信息保存在 $NODE_INFO（权限 600）。"
}
