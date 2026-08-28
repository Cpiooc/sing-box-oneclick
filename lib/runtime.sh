#!/usr/bin/env bash
# shellcheck shell=bash

singbox_can_reload() {
  [[ $(systemctl show sing-box -p CanReload --value 2>/dev/null || true) == "yes" ]]
}

apply_runtime_change() {
  RUNTIME_APPLY_MODE="restart"

  if systemctl is-active --quiet sing-box 2>/dev/null && singbox_can_reload; then
    if systemctl reload sing-box; then
      RUNTIME_APPLY_MODE="reload"
      return 0
    fi
    warn "sing-box 热重载失败，自动回退到完整重启。"
  fi

  systemctl restart sing-box
  RUNTIME_APPLY_MODE="restart"
}

rollback_from_last_backup() {
  local dir=${LAST_BACKUP_DIR:-}
  [[ -n "$dir" && -d "$dir" ]] || return 1

  warn "正在自动回滚到变更前配置..."
  if [[ -f "$dir/config.json" ]]; then
    cp -a "$dir/config.json" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    if systemctl is-active --quiet sing-box 2>/dev/null && singbox_can_reload; then
      systemctl reload sing-box 2>/dev/null || systemctl restart sing-box 2>/dev/null || true
    else
      systemctl restart sing-box 2>/dev/null || true
    fi
  else
    rm -f "$CONFIG_FILE"
    systemctl stop sing-box 2>/dev/null || true
  fi
  [[ -f "$dir/state.json" ]] && cp -a "$dir/state.json" "$STATE_FILE"
  [[ -f "$dir/node-info.txt" ]] && cp -a "$dir/node-info.txt" "$NODE_INFO"
}

apply_candidate() {
  local candidate=$1 label=$2
  ensure_singbox

  info "校验候选配置..."
  if ! sing-box check -c "$candidate"; then
    die "${label} 配置校验失败；现有配置未被修改。"
  fi

  backup_all
  install -m 600 "$candidate" "${CONFIG_FILE}.new"
  mv -f "${CONFIG_FILE}.new" "$CONFIG_FILE"

  systemctl enable sing-box >/dev/null 2>&1 || true
  if ! apply_runtime_change; then
    rollback_from_last_backup || true
    die "${label} 应用失败，已尝试自动回滚。"
  fi

  sleep 1
  if ! systemctl is-active --quiet sing-box; then
    journalctl -u sing-box --no-pager -n 80 || true
    rollback_from_last_backup || true
    die "${label} 应用后未保持 active，已尝试自动回滚。"
  fi

  if [[ ${RUNTIME_APPLY_MODE:-restart} == "reload" ]]; then
    info "${label} 已通过 SIGHUP 热重载应用，sing-box 进程保持运行。"
    note "热重载避免进程级重启，但 sing-box 重载配置时仍可能重置部分现有连接。"
  else
    info "${label} 已应用，sing-box 已完成安全重启并保持 active。"
  fi
}

# Override Certbot setup so certificate renewals prefer reload over restart.
ensure_certbot() {
  if ! have certbot; then
    info "安装 Certbot（用于 TLS 证书和自动续期）..."
    apt-get update
    apt-get install -y certbot
  fi
  install -d -m 755 "$(dirname "$CERTBOT_HOOK")"
  cat > "$CERTBOT_HOOK" <<'HOOK'
#!/usr/bin/env bash
if systemctl is-active --quiet sing-box 2>/dev/null; then
  systemctl reload sing-box >/dev/null 2>&1 || systemctl restart sing-box >/dev/null 2>&1 || true
fi
HOOK
  chmod 755 "$CERTBOT_HOOK"
  systemctl enable --now certbot.timer >/dev/null 2>&1 || true
}

renew_certificates() {
  ensure_certbot
  certbot renew
  if systemctl is-active --quiet sing-box 2>/dev/null; then
    systemctl reload sing-box 2>/dev/null || systemctl restart sing-box 2>/dev/null || true
  fi
  certificate_status
}

restore_backup() {
  ensure_dirs
  mapfile -t dirs < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
  if (( ${#dirs[@]} == 0 )); then
    warn "没有找到备份。"
    return 0
  fi

  local i n dir
  echo
  headmsg "可用配置备份"
  for i in "${!dirs[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${dirs[$i]}"
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

  if ! apply_runtime_change; then
    rollback_from_last_backup || true
    die "恢复配置失败，已尝试回到恢复前状态。"
  fi
  render_node_info
  info "备份恢复成功。"
}
