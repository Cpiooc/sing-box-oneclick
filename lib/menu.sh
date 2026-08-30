#!/usr/bin/env bash
# shellcheck shell=bash

MANAGER_UPDATE_STATE="${MANAGER_UPDATE_STATE:-unchecked}"
MANAGER_LOCAL_COMMIT="${MANAGER_LOCAL_COMMIT:-}"
MANAGER_REMOTE_COMMIT="${MANAGER_REMOTE_COMMIT:-}"

manager_local_commit() {
  local ref
  [[ -r "${MANAGER_DIR}/COMMIT" ]] || return 1
  ref=$(tr -d '[:space:]' < "${MANAGER_DIR}/COMMIT")
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s' "$ref"
}

manager_remote_commit_quick() {
  local json sha
  [[ "${SB_SKIP_UPDATE_CHECK:-0}" != 1 ]] || return 1
  json=$(curl -fsSL --proto '=https' --tlsv1.2 \
    --connect-timeout 1 --max-time 2 \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: sing-box-oneclick' \
    "${REPO_API}/commits/main" 2>/dev/null) || return 1
  sha=$(grep -oE '"sha"[[:space:]]*:[[:space:]]*"[0-9a-f]{40}"' <<< "$json" | head -n1 | cut -d'"' -f4)
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s' "$sha"
}

manager_check_update() {
  local local_commit remote_commit
  MANAGER_UPDATE_STATE="offline"
  MANAGER_LOCAL_COMMIT=""
  MANAGER_REMOTE_COMMIT=""

  local_commit=$(manager_local_commit 2>/dev/null || true)
  remote_commit=$(manager_remote_commit_quick) || return 0

  MANAGER_LOCAL_COMMIT="$local_commit"
  MANAGER_REMOTE_COMMIT="$remote_commit"
  if [[ -n "$local_commit" && "$local_commit" == "$remote_commit" ]]; then
    MANAGER_UPDATE_STATE="current"
  else
    MANAGER_UPDATE_STATE="available"
  fi
}

manager_update_notice() {
  [[ "$MANAGER_UPDATE_STATE" == "available" ]] || return 0
  local local_short="legacy" remote_short
  [[ "$MANAGER_LOCAL_COMMIT" =~ ^[0-9a-f]{40}$ ]] && local_short=${MANAGER_LOCAL_COMMIT:0:12}
  remote_short=${MANAGER_REMOTE_COMMIT:0:12}
  echo
  echo -e "  ${C_YELLOW}!${C_RESET} ${C_BOLD}管理脚本有更新${C_RESET}  ${C_DIM}${local_short} → ${remote_short}${C_RESET}"
  echo -e "    ${C_DIM}选择 24 安全更新，或运行 sb update；只提醒，不会自动安装。${C_RESET}"
}

if declare -F ui_cli_help >/dev/null 2>&1; then
  eval "$(declare -f ui_cli_help | sed '1s/ui_cli_help/ui_cli_help_pre_update_notice/')"
fi

ui_cli_help() {
  if declare -F ui_cli_help_pre_update_notice >/dev/null 2>&1; then
    ui_cli_help_pre_update_notice "$@"
  fi
  echo "  sb guide           新手指南 / 常见术语 / 推荐默认值"
  echo "  sb update          安全更新 sing-box-oneclick 管理脚本（手动确认）"
}

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

novice_first_run_hint() {
  [[ -f "$STATE_FILE" ]] || return 0
  local count
  count=$(jq -r '(.nodes // {}) | length' "$STATE_FILE" 2>/dev/null || echo 0)
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  (( count == 0 )) || return 0

  echo
  echo -e "  ${C_GREEN}★${C_RESET} ${C_BOLD}第一次使用${C_RESET}：直接选 ${C_CYAN}2 Reality${C_RESET} 最简单；sing-box 未安装时会自动安装。"
  echo -e "    ${C_DIM}端口和 Reality SNI 不懂就直接按 Enter；想看术语解释可选 35 或运行 sb guide。${C_RESET}"
}

novice_guide() {
  echo
  headmsg "新手指南 · 不懂就按这里的推荐值"
  echo
  note "第一次部署：推荐先选 2 · VLESS + Reality。它不需要普通 TLS 证书，步骤最少。"
  note "部署节点时若 sing-box 尚未安装，会自动安装；不需要先专门点菜单 1。"
  note "输入框里出现 [默认值] 时，不知道怎么改就直接按 Enter。"

  echo
  headmsg "最常见的几个词"
  ui_kv "节点地址" "客户端实际连接的 VPS IP / 域名"
  ui_kv "监听端口" "VPS 对外开放的端口；还要在云厂商安全组放行"
  ui_kv "TLS SNI" "TLS 使用的域名；普通 TLS 节点通常与节点域名相同"
  ui_kv "Reality SNI" "Reality 的握手伪装目标，不是你的节点域名；默认值可直接用"
  ui_kv "DNS only / 灰云" "Cloudflare 只做 DNS，不代理流量"
  ui_kv "Proxied / 橙云" "流量经过 Cloudflare；只有 WS 等兼容模式才适合普通橙云"
  ui_kv "ACME" "Let's Encrypt 自动签发的受信任证书，需要域名"
  ui_kv "自签证书" "没有域名也能用，但客户端必须允许跳过证书验证"

  echo
  headmsg "推荐默认值"
  printf '  %-18s %s\n' "Reality" "TCP/443 · SNI 默认 www.microsoft.com"
  printf '  %-18s %s\n' "Hysteria2" "UDP/443 · 伪装网站保持默认"
  printf '  %-18s %s\n' "TUIC" "UDP/8443 · QUIC 拥塞控制 bbr"
  printf '  %-18s %s\n' "Cloudflare WS" "端口自动选 443/8443 · 仅橙云用户选择"
  printf '  %-18s %s\n' "Shadowsocks" "TCP+UDP/8388 · 加密方法选 1"
  printf '  %-18s %s\n' "HTTPS 私有订阅" "直连模式 · TCP/9443"
  printf '  %-18s %s\n' "HY2 端口跳跃" "关闭；只有单端口 UDP 被限速时再开"
  printf '  %-18s %s\n' "BBR" "按需开启；HY2/TUIC 的 QUIC/UDP 不依赖 TCP BBR"

  echo
  headmsg "选协议时最简单的判断"
  echo "  只想先有一个稳定节点      → Reality"
  echo "  想要主力 UDP / QUIC       → Hysteria2"
  echo "  已明确要走 Cloudflare CDN → VLESS WebSocket"
  echo "  兼容 / 备用               → AnyTLS / Trojan / Shadowsocks"
  echo
  note "不需要为了“功能齐全”把所有协议都装一遍。"
}

novice_protocol_intro() {
  local kind=$1
  echo
  headmsg "小白提示"
  case "$kind" in
    reality)
      note "节点地址 = 客户端连接 VPS 的地址，可填公网 IP 或直接解析到 VPS 的域名。"
      note "Reality SNI 是握手伪装目标，不是你的节点域名；不懂就保持默认 www.microsoft.com。"
      note "TCP 端口不懂就保持 443。脚本会自动生成 UUID、Reality 密钥和 Short ID。"
      ;;
    hy2)
      note "有域名时推荐填域名并使用 Let's Encrypt；没有域名也可填 VPS IP，后面会默认自签证书。"
      note "TLS SNI / 证书名称通常与上一步节点地址相同，直接按 Enter 即可。"
      note "UDP 端口保持 443、伪装网站保持默认即可；普通 Cloudflare 橙云不能代理 HY2。"
      ;;
    tuic)
      note "有域名时推荐域名；没有域名也可使用 VPS IP + 自签证书。"
      note "TLS SNI 通常保持节点地址；UDP 端口默认 8443，QUIC 拥塞控制默认 bbr，小白都直接按 Enter。"
      note "普通 Cloudflare 橙云不能代理 TUIC。"
      ;;
    ws)
      note "只有明确要使用 Cloudflare 橙云/CDN 时才选这个模式；否则 Reality 更简单。"
      note "需要一个已经添加到 Cloudflare 的域名。端口会自动推荐 443 或 8443。"
      note "证书有域名时默认 Let's Encrypt；Cloudflare 最终建议使用 Full (strict)。"
      ;;
    anytls)
      note "AnyTLS 是兼容/备用 TCP 协议。第一次部署主力节点时通常先用 Reality。"
      note "节点地址可填域名或 IP；TLS SNI 通常保持相同。端口和证书模式不懂就按默认值。"
      ;;
    trojan)
      note "Trojan 是兼容性较好的 TLS TCP 备用协议。第一次部署通常先用 Reality。"
      note "节点地址可填域名或 IP；TLS SNI 通常保持相同。端口和证书模式不懂就按默认值。"
      ;;
    ss)
      note "Shadowsocks 是兼容/备用协议，本身没有普通 TLS 证书层。"
      note "端口保持 8388；加密方法不知道怎么选就选 1（2022-blake3-aes-128-gcm）。"
      note "脚本会自动生成合适长度的密钥，并同时配置 TCP + UDP。"
      ;;
  esac
}

novice_tls_hint() {
  local server_name=$1
  echo
  headmsg "小白提示 · TLS 证书"
  if is_hostname "$server_name"; then
    note "当前证书名称是域名 ${server_name}：下一步直接按 Enter，会默认选择 Let's Encrypt（推荐）。"
  else
    note "当前证书名称是 IP ${server_name}：下一步直接按 Enter，会默认生成自签证书。"
    warn "自签证书可用，但客户端需要允许跳过证书验证；长期使用有域名时更推荐受信任证书。"
  fi
  note "“导入已有 PEM”属于高级选项，不确定就不要选。"
}

novice_subscription_intro() {
  echo
  headmsg "小白提示 · HTTPS 私有订阅"
  note "这个功能不是节点运行的必需项；只有多设备想通过一个 HTTPS 地址自动更新配置时才需要。"
  note "不知道“直连 / Cloudflare 橙云”怎么选时，选择 1 · DNS only / 直连，默认 TCP/9443。"
  note "完整订阅 URL 等同于密码，生成后不要发到公开群、Issue 或第三方转换站。"
}

novice_edit_intro() {
  echo
  headmsg "小白提示 · 原地修改"
  note "没有明确要改的参数时直接返回，不需要为了“优化”随便改。"
  note "地址 / 端口类输入通常留空 = 保持当前值；UUID / 密码等凭据页面会明确提示“留空自动生成”。"
  warn "重新生成 UUID / 密码 / Short ID 后，旧客户端配置会失效，需要重新导入。"
}

novice_firewall_intro() {
  echo
  headmsg "小白提示 · 防火墙"
  note "UFW 是 VPS 系统内的防火墙，不等于云厂商控制台里的 Security Group / 安全组。"
  note "脚本可以管理本机端口，但云安全组仍要手动放行对应 TCP / UDP 端口。"
  warn "不要手工关闭当前 SSH 端口；脚本默认不会主动做破坏性 SSH 加固。"
}

# Add explanations around the final implementations loaded by previous modules.
for _novice_fn in deploy_reality deploy_hysteria2 deploy_tuic deploy_cloudflare_ws deploy_anytls deploy_trojan deploy_shadowsocks select_certificate_mode enable_https_subscription edit_node_parameters firewall_setup_v17; do
  if declare -F "$_novice_fn" >/dev/null 2>&1; then
    eval "$(declare -f "$_novice_fn" | sed "1s/${_novice_fn}/${_novice_fn}_pre_novice/")"
  fi
done
unset _novice_fn

deploy_reality() { novice_protocol_intro reality; deploy_reality_pre_novice "$@"; }
deploy_hysteria2() { novice_protocol_intro hy2; deploy_hysteria2_pre_novice "$@"; }
deploy_tuic() { novice_protocol_intro tuic; deploy_tuic_pre_novice "$@"; }
deploy_cloudflare_ws() { novice_protocol_intro ws; deploy_cloudflare_ws_pre_novice "$@"; }
deploy_anytls() { novice_protocol_intro anytls; deploy_anytls_pre_novice "$@"; }
deploy_trojan() { novice_protocol_intro trojan; deploy_trojan_pre_novice "$@"; }
deploy_shadowsocks() { novice_protocol_intro ss; deploy_shadowsocks_pre_novice "$@"; }

select_certificate_mode() {
  novice_tls_hint "$1"
  select_certificate_mode_pre_novice "$@"
}

enable_https_subscription() {
  novice_subscription_intro
  enable_https_subscription_pre_novice "$@"
}

edit_node_parameters() {
  novice_edit_intro
  edit_node_parameters_pre_novice "$@"
}

firewall_setup_v17() {
  novice_firewall_intro
  firewall_setup_v17_pre_novice "$@"
}

menu() {
  manager_check_update
  while true; do
    [[ -t 1 ]] && clear || true
    ui_banner
    ui_dashboard
    manager_update_notice
    novice_first_run_hint
    ui_rule

    ui_group "核心部署" "小白推荐：不知道怎么选就先用 Reality"
    ui_item 1  "安装 / 修复 sing-box" "通常不用先点；部署节点时会自动安装"
    ui_item 2  "VLESS + Reality" "第一次使用推荐 · TCP/443"
    ui_item 3  "Hysteria2" "主力 UDP/QUIC · 端口默认 443"
    ui_item 4  "Reality + Hysteria2" "一次配置 TCP + UDP 双 443"
    ui_item 5  "Cloudflare VLESS WS" "仅明确使用 Cloudflare 橙云/CDN 时选择"
    ui_item 6  "TUIC v5" "UDP 备用 · 不懂优先选 HY2"
    ui_group_end

    ui_group "兼容协议" "备用协议，新手不需要全部安装"
    ui_item 30 "AnyTLS" "TCP + TLS · 备用"
    ui_item 31 "Trojan" "TCP + TLS · 备用"
    ui_item 32 "Shadowsocks" "TCP+UDP · 默认 8388 / 推荐 2022 BLAKE3"
    ui_group_end

    ui_group "节点与订阅" "敏感信息默认隐藏"
    ui_item 7  "查看节点安全视图" "UUID / 密码 / 分享链接打码"
    ui_item 8  "显示节点二维码" "包含完整凭据"
    ui_item 36 "显示完整节点凭据" "敏感操作"
    ui_item 9  "删除单个节点"
    ui_item 26 "切换证书 / TLS 模式" "有域名默认 Let's Encrypt；IP 默认自签"
    ui_item 27 "原地修改节点参数" "不重建整个节点"
    ui_item 28 "本地客户端配置 / 订阅导出"
    ui_item 29 "安全 HTTPS 在线订阅" "多设备需要自动更新时再开"
    ui_item 33 "HY2 端口跳跃" "高级 · 默认关闭"
    ui_group_end

    ui_group "运行与诊断" "不知道怎么选先看指南；出问题先跑 doctor"
    ui_item 35 "新手指南 / 术语解释" "端口、SNI、灰云、证书、默认值"
    ui_item 34 "一键体检 sb doctor" "只检查，不自动改配置"
    ui_item 10 "sing-box 状态 / 配置校验"
    ui_item 11 "查看 sing-box 日志"
    ui_item 12 "网络诊断"
    ui_group_end

    ui_group "系统安全"
    ui_item 13 "BBR 开关 / 管理" "开启前自动记录原设置"
    ui_item 14 "查看 BBR 详细状态"
    ui_item 15 "配置 UFW 防火墙" "云安全组仍需单独放行"
    ui_item 16 "配置 Fail2ban SSH 防护"
    ui_item 17 "启用系统自动安全更新"
    ui_item 18 "完整安全自检"
    ui_group_end

    ui_group "备份 / 证书 / 更新"
    ui_item 19 "备份管理" "自动保留 30 个 · 安全 Diff"
    ui_item 20 "快速恢复备份"
    ui_item 21 "查看 TLS 证书状态"
    ui_item 22 "手动续期 ACME 证书"
    ui_item 23 "sing-box 版本管理" "小白选最新稳定版；指定版本/降级是高级操作"
    ui_item 24 "安全更新本管理脚本" "锁定 commit + SHA256"
    ui_item 25 "完全卸载"
    ui_group_end

    echo
    echo -e "  ${C_DIM}CLI  sb guide · sb doctor · sb nodes · sb core · sb bbr · sb sub · sb backup · sb hy2-hop${C_RESET}"
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
      24) self_update; manager_check_update; pause ;;
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
      35) novice_guide; pause ;;
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
    guide|newbie|beginner) novice_guide ;;
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
    update|self-update) self_update ;;
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
