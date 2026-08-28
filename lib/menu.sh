#!/usr/bin/env bash
# shellcheck shell=bash

system_summary() {
  local sb_state="未安装" bbr="未启用" v4="无" v6="无"
  have sing-box && sb_state=$(systemctl is-active sing-box 2>/dev/null || echo installed)
  [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true) == "bbr" ]] && bbr="已启用"
  ip -4 route show default 2>/dev/null | grep -q . && v4="有"
  ip -6 route show default 2>/dev/null | grep -q . && v6="有"

  echo "系统: ${PRETTY_NAME:-unknown} | 内核: $(uname -r)"
  echo "sing-box: ${sb_state} | TCP BBR: ${bbr} | IPv4: ${v4} | IPv6: ${v6}"
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
  6. 部署 / 重建 TUIC v5

  7. 查看全部节点 / 分享链接
  8. 显示节点二维码
  9. 删除单个节点
 10. 查看 sing-box 状态 / 配置校验
 11. 查看 sing-box 日志
 12. 网络诊断

 13. 启用 TCP BBR + fq
 14. 验证 TCP BBR
 15. 配置 UFW 防火墙
 16. 配置 Fail2ban SSH 防护
 17. 启用系统自动安全更新
 18. 完整安全自检

 19. 立即备份配置
 20. 恢复配置备份
 21. 查看 TLS 证书状态
 22. 手动续期 TLS 证书

 23. 安全更新 sing-box
 24. 更新本管理脚本
 25. 完全卸载

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
