#!/usr/bin/env bash
# shellcheck shell=bash

show_script_version() {
  ui_banner
  echo
  ui_kv "管理脚本" "v${SCRIPT_VERSION}"
  if have sing-box; then
    ui_kv "sing-box" "$(sing-box version 2>/dev/null | head -n1 || echo unknown)"
  else
    ui_kv "sing-box" "未安装"
  fi
  if [[ -r "${MANAGER_DIR}/COMMIT" ]]; then
    ui_kv "Commit" "$(cut -c1-12 "${MANAGER_DIR}/COMMIT")"
  fi
  ui_kv "仓库" "$REPO"
}

menu() {
  while true; do
    [[ -t 1 ]] && clear || true
    ui_banner
    ui_dashboard
    ui_rule

    ui_group "核心部署" "小白推荐：按提示一路使用默认值"
    ui_item 1  "安装 / 修复 sing-box" "最新稳定版 · 小白推荐"
    ui_item 2  "VLESS + Reality" "TCP · Vision · 主力推荐"
    ui_item 3  "Hysteria2" "UDP · QUIC · 主力推荐"
    ui_item 4  "Reality + Hysteria2" "TCP/UDP 双 443"
    ui_item 5  "Cloudflare VLESS WS" "TCP · TLS 可选"
    ui_item 6  "TUIC v5" "UDP · QUIC"
    ui_group_end

    ui_group "兼容协议" "按需部署，不需要全部安装"
    ui_item 30 "AnyTLS" "TCP · TLS"
    ui_item 31 "Trojan" "TCP · TLS"
    ui_item 32 "Shadowsocks" "TCP+UDP · 2022 BLAKE3"
    ui_group_end

    ui_group "节点与订阅" "敏感信息默认隐藏"
    ui_item 7  "查看节点安全视图" "UUID / 密码 / 分享链接打码"
    ui_item 8  "显示节点二维码" "包含完整凭据"
    ui_item 36 "显示完整节点凭据" "敏感操作"
    ui_item 9  "删除单个节点"
    ui_item 26 "切换证书 / TLS 模式"
    ui_item 27 "原地修改节点参数"
    ui_item 28 "本地客户端配置 / 订阅导出"
    ui_item 29 "安全 HTTPS 在线订阅"
    ui_item 33 "HY2 端口跳跃" "高级 · 默认关闭"
    ui_group_end

    ui_group "运行与诊断" "出问题先跑 doctor"
    ui_item 34 "一键体检 sb doctor" "只检查，不自动改配置"
    ui_item 10 "sing-box 状态 / 配置校验"
    ui_item 11 "查看 sing-box 日志"
    ui_item 12 "网络诊断"
    ui_group_end

    ui_group "系统安全"
    ui_item 13 "BBR 开关 / 管理" "开启前自动记录原设置"
    ui_item 14 "查看 BBR 详细状态"
    ui_item 15 "配置 UFW 防火墙" "自动识别 TCP / UDP / TCP+UDP"
    ui_item 16 "配置 Fail2ban SSH 防护"
    ui_item 17 "启用系统自动安全更新"
    ui_item 18 "完整安全自检"
    ui_group_end

    ui_group "备份 / 证书 / 更新"
    ui_item 19 "备份管理" "自动保留 30 个 · 安全 Diff"
    ui_item 20 "快速恢复备份"
    ui_item 21 "查看 TLS 证书状态"
    ui_item 22 "手动续期 ACME 证书"
    ui_item 23 "sing-box 版本管理" "最新 / 指定版本 / 上一版回退"
    ui_item 24 "安全更新本管理脚本" "锁定 commit + SHA256"
    ui_item 25 "完全卸载"
    ui_group_end

    echo
    echo -e "  ${C_DIM}CLI  sb doctor · sb nodes · sb core · sb bbr · sb sub · sb backup · sb hy2-hop${C_RESET}"
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
      13) bbr_menu; pause ;;
      14) bbr_status; pause ;;
      15) firewall_setup_v17; pause ;;
      16) fail2ban_setup; pause ;;
      17) enable_security_updates; pause ;;
      18) security_audit; pause ;;
      19) backup_menu; pause ;;
      20) restore_backup; pause ;;
      21) certificate_status; pause ;;
      22) renew_certificates; pause ;;
      23) core_menu; pause ;;
      24) self_update; pause ;;
      25) uninstall_all ;;
      26) switch_certificate_tls; pause ;;
      27) edit_node_parameters; pause ;;
      28) client_export_menu; pause ;;
      29) subscription_menu; pause ;;
      30) deploy_anytls; pause ;;
      31) deploy_trojan; pause ;;
      32) deploy_shadowsocks; pause ;;
      33) hy2_port_hopping_menu; pause ;;
      34) doctor; pause ;;
      36) reveal_nodes; pause ;;
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
    doctor) doctor ;;
    nodes|info) ui_node_overview; echo; show_nodes ;;
    reveal|secrets) reveal_nodes ;;
    edit|modify) edit_node_parameters ;;
    export|client) client_export_menu ;;
    subscription|sub) subscription_menu ;;
    backup) backup_menu ;;
    core) core_cli "${2:-menu}" "${3:-}" ;;
    hy2-hop|hy2hop) hy2_hop_cli "${2:-menu}" ;;
    anytls) deploy_anytls ;;
    trojan) deploy_trojan ;;
    ss|shadowsocks) deploy_shadowsocks ;;
    qr) show_qr_codes ;;
    logs|log) show_logs ;;
    audit|check) security_audit ;;
    bbr) bbr_cli "${2:-menu}" ;;
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
