#!/usr/bin/env bash
# shellcheck shell=bash

show_status() {
  ensure_singbox
  echo
  systemctl status sing-box --no-pager -l || true
  echo
  [[ -f "$CONFIG_FILE" ]] && sing-box check -c "$CONFIG_FILE" || true
  echo
  headmsg "===== sing-box 监听端口 ====="
  ss -lntup 2>/dev/null | grep sing-box || true

  if systemctl list-unit-files 2>/dev/null | grep -q '^sing-box-oneclick-subscription.service'; then
    echo
    headmsg "===== HTTPS 私有订阅 ====="
    systemctl status sing-box-oneclick-subscription.service --no-pager -l 2>/dev/null | sed -n '1,14p' || true
  fi
}

show_logs() {
  ensure_singbox
  journalctl -u sing-box -n 120 --no-pager
}

network_diagnostics() {
  echo
  headmsg "===== 网络诊断 ====="
  show_ip_info
  echo
  echo "默认 IPv4 路由："
  ip -4 route show default 2>/dev/null || true
  echo "默认 IPv6 路由："
  ip -6 route show default 2>/dev/null || true
  echo
  echo "DNS："
  cat /etc/resolv.conf | sed -n '1,20p'
  echo
  echo "监听："
  ss -lntup | head -n 80
  echo
  bbr_status
}

backup_now() {
  backup_all
}

restore_backup() {
  ensure_dirs
  mapfile -t dirs < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
  if (( ${#dirs[@]} == 0 )); then
    warn "没有找到备份。"
    return 0
  fi

  local i n dir
  echo "可用备份："
  for i in "${!dirs[@]}"; do
    printf '%d) %s\n' "$((i+1))" "${dirs[$i]}"
  done
  read -r -p "选择要恢复的序号: " n
  [[ "$n" =~ ^[0-9]+$ ]] || die "无效序号。"
  (( n >= 1 && n <= ${#dirs[@]} )) || die "无效序号。"
  dir=${dirs[$((n-1))]}

  [[ -f "$dir/config.json" ]] || die "该备份没有 config.json。"
  sing-box check -c "$dir/config.json" || die "备份配置校验失败。"

  backup_all
  cp -a "$dir/config.json" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  [[ -f "$dir/state.json" ]] && cp -a "$dir/state.json" "$STATE_FILE"
  [[ -f "$dir/node-info.txt" ]] && cp -a "$dir/node-info.txt" "$NODE_INFO"

  if ! systemctl restart sing-box; then
    rollback_from_last_backup || true
    die "恢复后 sing-box 启动失败，已尝试回到恢复前状态。"
  fi
  render_node_info
  info "备份恢复成功。"
}

safe_update_singbox() {
  if ! have sing-box; then
    warn "sing-box 尚未安装，将直接安装当前官方稳定版。"
    install_singbox_core
    return 0
  fi
  backup_all

  local old_bin old_version tmp_installer backup_bin
  old_bin=$(command -v sing-box)
  old_version=$(sing-box version 2>/dev/null | head -n1 || true)
  backup_bin="${LAST_BACKUP_DIR}/sing-box.bin"
  cp -a "$old_bin" "$backup_bin" 2>/dev/null || true

  tmp_installer=$(mktemp)
  cleanup_files+=("$tmp_installer")
  download_checked_script "https://sing-box.app/install.sh" "$tmp_installer"

  info "更新前：${old_version}"
  if ! bash "$tmp_installer"; then
    warn "官方安装脚本执行失败。"
    return 1
  fi

  if [[ -f "$CONFIG_FILE" ]] && ! sing-box check -c "$CONFIG_FILE"; then
    err "新版本无法通过现有配置校验。"
    if [[ -f "$backup_bin" ]]; then
      warn "尝试恢复更新前 sing-box 二进制..."
      install -m 0755 "$backup_bin" "$old_bin"
    fi
    systemctl restart sing-box 2>/dev/null || true
    return 1
  fi

  systemctl restart sing-box
  info "更新后：$(sing-box version 2>/dev/null | head -n1 || true)"
}

self_update() {
  local remote ans
  remote=$(curl -fsSL --max-time 10 "${RAW_BASE}/VERSION" 2>/dev/null | tr -d '[:space:]' || true)

  echo "当前版本: $SCRIPT_VERSION"
  echo "远端版本: ${remote:-unknown}"
  read -r -p "从 GitHub main 更新整个 sb 管理脚本？[y/N]: " ans
  [[ ${ans,,} == "y" || ${ans,,} == "yes" ]] || return 0

  install_bundle_from_github
  info "脚本组件已全部更新。退出后重新运行 sb 即可使用新版本。"
}

certificate_status() {
  ensure_state
  local domains domain cert
  mapfile -t domains < <(jq -r '.nodes | to_entries[] | select(.value.certificate==true) | .value.domain' "$STATE_FILE" | sort -u)
  if (( ${#domains[@]} == 0 )); then
    warn "没有脚本管理的证书。"
    return 0
  fi

  for domain in "${domains[@]}"; do
    cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    echo
    headmsg "===== $domain ====="
    openssl x509 -in "$cert" -noout -subject -issuer -dates 2>/dev/null || warn "证书不存在或不可读。"
  done
  echo
  systemctl status certbot.timer --no-pager -l 2>/dev/null | sed -n '1,14p' || true
}

renew_certificates() {
  ensure_certbot
  certbot renew
  systemctl restart sing-box 2>/dev/null || true
  certificate_status
}

uninstall_all() {
  warn "此操作会停止 sing-box 和脚本管理的 HTTPS 订阅服务，并删除配置、状态、备份和 sb 命令。"
  warn "Let's Encrypt 证书、BBR、UFW、Fail2ban、Nginx 软件包和系统安全更新设置默认保留，避免误删系统级配置。"
  read -r -p "请输入 DELETE 确认完全卸载脚本管理内容: " ans
  [[ "$ans" == "DELETE" ]] || { warn "已取消。"; return 0; }

  local sub_service sub_unit sub_publish sub_hook
  sub_service=${SUBSCRIPTION_SERVICE:-sing-box-oneclick-subscription.service}
  sub_unit=${SUBSCRIPTION_UNIT:-/etc/systemd/system/sing-box-oneclick-subscription.service}
  sub_publish=${SUBSCRIPTION_PUBLISH_DIR:-/var/lib/sing-box-oneclick-subscription}
  sub_hook=${SUBSCRIPTION_CERTBOT_HOOK:-/etc/letsencrypt/renewal-hooks/deploy/sing-box-oneclick-subscription-reload.sh}

  systemctl stop "$sub_service" 2>/dev/null || true
  systemctl disable "$sub_service" 2>/dev/null || true
  rm -f "$sub_unit" "$sub_hook"
  rm -rf "$sub_publish"
  systemctl daemon-reload 2>/dev/null || true

  systemctl stop sing-box 2>/dev/null || true
  systemctl disable sing-box 2>/dev/null || true

  if have apt-get; then
    apt-get remove -y sing-box 2>/dev/null || true
  fi

  rm -rf "$CONFIG_DIR" "$APP_DIR" "$MANAGER_DIR"
  rm -f "$NODE_INFO" "$MANAGER_LINK"
  info "已删除 sing-box、HTTPS 订阅实例及 sing-box-oneclick 管理内容。系统级安全设置与 Nginx 软件包已保留。"
  exit 0
}