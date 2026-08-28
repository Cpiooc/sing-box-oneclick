#!/usr/bin/env bash
# shellcheck shell=bash

system_summary() {
  local sb_state="未安装" bbr="未启用" v4="无" v6="无"
  have sing-box && sb_state=$(systemctl is-active sing-box 2>/dev/null || echo installed)
  [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true) == "bbr" ]] && bbr="已启用"
  ip -4 route show default 2>/dev/null | grep -q . && v4="有"
  ip -6 route show default 2>/dev/null | grep -q . && v6="有"

  echo "系统: ${PRETTY_NAME:-unknown} | 内核: $(uname -r)"
  echo "sing-box: ${sb_state} | BBR: ${bbr} | IPv4: ${v4} | IPv6: ${v6}"
}

menu() {
  while true; do
    clear || true
    cat <<MENU
==============================================================
  sing-box 一键部署 / 安全管理脚本 v${SCRIPT_VERSION}
  GitHub: ${REPO}
==============================================================
MENU
    system_summary
    cat <<'MENU'
--------------------------------------------------------------
  1. 安装 / 修复 sing-box

  2. 部署 / 重建 VLESS + Reality
  3. 部署 / 重建 Hysteria2
  4. Reality + Hysteria2 双协议
  5. 部署 / 重建 Cloudflare VLESS WS + TLS

  6. 查看全部节点 / 分享链接
  7. 显示节点二维码
  8. 删除单个节点
  9. 查看 sing-box 状态 / 配置校验
 10. 查看 sing-box 日志
 11. 网络诊断

 12. 启用 BBR + fq
 13. 验证 BBR
 14. 配置 UFW 防火墙
 15. 配置 Fail2ban SSH 防护
 16. 启用系统自动安全更新
 17. 完整安全自检

 18. 立即备份配置
 19. 恢复配置备份
 20. 查看 TLS 证书状态
 21. 手动续期 TLS 证书

 22. 安全更新 sing-box
 23. 更新本管理脚本
 24. 完全卸载

  0. 退出
==============================================================
MENU
    read -r -p "请选择: " choice
    case "$choice" in
      1) install_singbox; pause ;;
      2) deploy_reality; pause ;;
      3) deploy_hysteria2; pause ;;
      4) deploy_dual_reality_hy2; pause ;;
      5) deploy_cloudflare_ws; pause ;;
      6) show_nodes; pause ;;
      7) show_qr_codes; pause ;;
      8) remove_node; pause ;;
      9) show_status; pause ;;
      10) show_logs; pause ;;
      11) network_diagnostics; pause ;;
      12) enable_bbr || true; pause ;;
      13) bbr_status; pause ;;
      14) firewall_setup; pause ;;
      15) fail2ban_setup; pause ;;
      16) enable_security_updates; pause ;;
      17) security_audit; pause ;;
      18) backup_now; pause ;;
      19) restore_backup; pause ;;
      20) certificate_status; pause ;;
      21) renew_certificates; pause ;;
      22) safe_update_singbox || true; pause ;;
      23) self_update; pause ;;
      24) uninstall_all ;;
      0) exit 0 ;;
      *) warn "无效选择。"; sleep 1 ;;
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
  menu
}
