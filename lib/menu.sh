#!/usr/bin/env bash
# shellcheck shell=bash

show_script_version() {
  ui_banner
  echo
  echo -e "  管理脚本 : ${C_BOLD}v${SCRIPT_VERSION}${C_RESET}"
  if have sing-box; then
    echo -e "  sing-box : ${C_BOLD}$(sing-box version 2>/dev/null | head -n1 || echo unknown)${C_RESET}"
  else
    echo "  sing-box : 未安装"
  fi
  echo -e "  仓库     : ${C_CYAN}${REPO}${C_RESET}"
}

menu() {
  while true; do
    [[ -t 1 ]] && clear || true
    ui_banner
    ui_dashboard
    ui_rule

    ui_group "节点部署"
    ui_item 1  "安装 / 修复 sing-box"
    ui_item 2  "部署 / 重建 VLESS + Reality"
    ui_item 3  "部署 / 重建 Hysteria2"
    ui_item 4  "Reality + Hysteria2 双协议"
    ui_item 5  "部署 / 重建 Cloudflare VLESS WS（TLS 可选）"
    ui_item 6  "部署 / 重建 TUIC v5"

    ui_group "节点管理"
    ui_item 7  "查看全部节点 / 分享链接"
    ui_item 8  "显示节点二维码"
    ui_item 9  "删除单个节点"
    ui_item 26 "切换证书 / TLS 模式"
    ui_item 27 "原地修改节点参数"
    ui_item 28 "客户端配置 / 订阅导出"

    ui_group "运行与诊断"
    ui_item 10 "sing-box 状态 / 配置校验"
    ui_item 11 "查看 sing-box 日志"
    ui_item 12 "网络诊断"

    ui_group "系统安全"
    ui_item 13 "启用 TCP BBR + fq"
    ui_item 14 "验证 TCP BBR"
    ui_item 15 "配置 UFW 防火墙"
    ui_item 16 "配置 Fail2ban SSH 防护"
    ui_item 17 "启用系统自动安全更新"
    ui_item 18 "完整安全自检"

    ui_group "备份与证书"
    ui_item 19 "立即备份配置"
    ui_item 20 "恢复配置备份"
    ui_item 21 "查看 TLS 证书状态"
    ui_item 22 "手动续期 ACME 证书"

    ui_group "维护"
    ui_item 23 "安全更新 sing-box"
    ui_item 24 "更新本管理脚本"
    ui_item 25 "完全卸载"

    echo
    ui_rule
    echo -e "  ${C_DIM}快捷命令：sb status · sb nodes · sb edit · sb export · sb qr · sb logs · sb audit · sb cert${C_RESET}"
    echo -e "  ${C_CYAN} 0${C_RESET}  退出"
    echo
    read -r -p "  请选择操作 › " choice

    case "$choice" in
      1) install_singbox; pause ;;
      2) deploy_reality; pause ;;
      3) deploy_hysteria2; pause ;;
      4) deploy_dual_reality_hy2; pause ;;
      5) deploy_cloudflare_ws; pause ;;
      6) deploy_tuic; pause ;;
      7) show_nodes; pause ;;
      8) show_qr_codes; pause ;;
      9) remove_node; pause ;;
      10) show_status; pause ;;
      11) show_logs; pause ;;
      12) network_diagnostics; pause ;;
      13) enable_bbr || true; pause ;;
      14) bbr_status; pause ;;
      15) firewall_setup; pause ;;
      16) fail2ban_setup; pause ;;
      17) enable_security_updates; pause ;;
      18) security_audit; pause ;;
      19) backup_now; pause ;;
      20) restore_backup; pause ;;
      21) certificate_status; pause ;;
      22) renew_certificates; pause ;;
      23) safe_update_singbox || true; pause ;;
      24) self_update; pause ;;
      25) uninstall_all ;;
      26) switch_certificate_tls; pause ;;
      27) edit_node_parameters; pause ;;
      28) client_export_menu; pause ;;
      0) exit 0 ;;
      *) warn "无效选择：${choice:-空}"; sleep 1 ;;
    esac
  done
}

main() {
  require_root
  load_os
  ensure_dirs

  if ! have jq; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y jq curl ca-certificates
  fi

  ensure_state

  case "${1:-menu}" in
    menu|"") menu ;;
    status) show_status ;;
    nodes|info) ui_node_overview; echo; show_nodes ;;
    edit|modify) edit_node_parameters ;;
    export|client|subscription|sub) client_export_menu ;;
    qr) show_qr_codes ;;
    logs|log) show_logs ;;
    audit|check) security_audit ;;
    bbr) bbr_status ;;
    cert|certificate) certificate_status ;;
    version|-v|--version) show_script_version ;;
    help|-h|--help) ui_cli_help ;;
    *)
      err "未知命令：$1"
      echo
      ui_cli_help
      return 2
      ;;
  esac
}