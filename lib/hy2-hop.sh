#!/usr/bin/env bash
# shellcheck shell=bash

# Optional Hysteria2 UDP port hopping for sing-box.
# sing-box clients natively support server_ports/hop_interval, while the
# sing-box Hysteria2 inbound listens on one UDP port. On Linux we therefore
# redirect an explicitly selected UDP range to the real HY2 listen port.

HY2_HOP_TABLE="sb_oneclick_hy2_hop"
HY2_HOP_UNIT="${HY2_HOP_UNIT:-/etc/systemd/system/sing-box-oneclick-hy2-hop.service}"

# Preserve the implementations loaded before this module so we can extend
# only HY2 behaviour without duplicating the rest of the manager.
for _fn in deploy_hysteria2 rebuild_node_uri singbox_outbound_for_key write_mihomo_proxy_hy2 state_remove_node post_parameter_change; do
  if declare -F "$_fn" >/dev/null 2>&1; then
    eval "$(declare -f "$_fn" | sed "1s/${_fn}/${_fn}_pre_hop/")"
  fi
done
unset _fn

hy2_hop_enabled() {
  [[ -f "$STATE_FILE" ]] || return 1
  [[ $(jq -r '.nodes.hy2.port_hopping.enabled // false' "$STATE_FILE" 2>/dev/null || echo false) == true ]]
}

hy2_hop_range_dash() {
  local start end
  start=$(jq -r '.nodes.hy2.port_hopping.range_start // empty' "$STATE_FILE")
  end=$(jq -r '.nodes.hy2.port_hopping.range_end // empty' "$STATE_FILE")
  [[ -n "$start" && -n "$end" ]] || return 1
  printf '%s-%s' "$start" "$end"
}

hy2_hop_range_colon() {
  local start end
  start=$(jq -r '.nodes.hy2.port_hopping.range_start // empty' "$STATE_FILE")
  end=$(jq -r '.nodes.hy2.port_hopping.range_end // empty' "$STATE_FILE")
  [[ -n "$start" && -n "$end" ]] || return 1
  printf '%s:%s' "$start" "$end"
}

hy2_hop_interval_seconds() {
  jq -r '.nodes.hy2.port_hopping.hop_interval // 30' "$STATE_FILE" 2>/dev/null || echo 30
}

hy2_hop_backend() {
  if have nft; then
    printf '%s' nft
  elif have iptables; then
    printf '%s' iptables
  else
    return 1
  fi
}

hy2_hop_ensure_backend() {
  if hy2_hop_backend >/dev/null 2>&1; then
    return 0
  fi
  note "端口跳跃需要 nftables/iptables 来做 UDP 重定向。"
  info "安装 nftables（Debian / Ubuntu 官方软件包）..."
  apt-get update
  apt-get install -y nftables
  hy2_hop_backend >/dev/null 2>&1 || die "没有可用的 nftables/iptables，无法启用端口跳跃。"
}

hy2_hop_cleanup_nft() {
  have nft || return 0
  nft delete table inet "$HY2_HOP_TABLE" >/dev/null 2>&1 || true
}

hy2_hop_cleanup_iptables() {
  have iptables || return 0
  local start end target
  start=$(jq -r '.nodes.hy2.port_hopping.range_start // empty' "$STATE_FILE" 2>/dev/null || true)
  end=$(jq -r '.nodes.hy2.port_hopping.range_end // empty' "$STATE_FILE" 2>/dev/null || true)
  target=$(jq -r '.nodes.hy2.port // empty' "$STATE_FILE" 2>/dev/null || true)
  validate_port "$start" || return 0
  validate_port "$end" || return 0
  validate_port "$target" || return 0

  while iptables -t nat -C PREROUTING -p udp --dport "${start}:${end}" -j REDIRECT --to-ports "$target" >/dev/null 2>&1; do
    iptables -t nat -D PREROUTING -p udp --dport "${start}:${end}" -j REDIRECT --to-ports "$target" >/dev/null 2>&1 || break
  done
  if have ip6tables; then
    while ip6tables -t nat -C PREROUTING -p udp --dport "${start}:${end}" -j REDIRECT --to-ports "$target" >/dev/null 2>&1; do
      ip6tables -t nat -D PREROUTING -p udp --dport "${start}:${end}" -j REDIRECT --to-ports "$target" >/dev/null 2>&1 || break
    done
  fi
}

hy2_hop_cleanup_rules() {
  hy2_hop_cleanup_nft
  hy2_hop_cleanup_iptables
}

hy2_hop_nft_config() {
  local start=$1 end=$2 target=$3
  cat <<EOF
table inet ${HY2_HOP_TABLE} {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    udp dport ${start}-${end} redirect to :${target}
  }
}
EOF
}

hy2_hop_apply_rules() {
  local start=$1 end=$2 target=$3 backend tmp
  validate_port "$start" || return 1
  validate_port "$end" || return 1
  validate_port "$target" || return 1
  (( start <= end )) || return 1

  hy2_hop_cleanup_rules
  backend=$(hy2_hop_backend) || return 1

  case "$backend" in
    nft)
      tmp=$(mktemp)
      cleanup_files+=("$tmp")
      hy2_hop_nft_config "$start" "$end" "$target" > "$tmp"
      nft -f "$tmp" || return 1
      ;;
    iptables)
      iptables -t nat -A PREROUTING -p udp --dport "${start}:${end}" -j REDIRECT --to-ports "$target" || return 1
      if have ip6tables; then
        ip6tables -t nat -A PREROUTING -p udp --dport "${start}:${end}" -j REDIRECT --to-ports "$target" || true
      fi
      ;;
    *) return 1 ;;
  esac
  HY2_HOP_BACKEND=$backend
}

hy2_hop_rules_active() {
  local backend
  backend=$(jq -r '.nodes.hy2.port_hopping.backend // empty' "$STATE_FILE" 2>/dev/null || true)
  case "$backend" in
    nft) have nft && nft list table inet "$HY2_HOP_TABLE" >/dev/null 2>&1 ;;
    iptables)
      local start end target
      start=$(jq -r '.nodes.hy2.port_hopping.range_start // empty' "$STATE_FILE")
      end=$(jq -r '.nodes.hy2.port_hopping.range_end // empty' "$STATE_FILE")
      target=$(jq -r '.nodes.hy2.port // empty' "$STATE_FILE")
      iptables -t nat -C PREROUTING -p udp --dport "${start}:${end}" -j REDIRECT --to-ports "$target" >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

hy2_hop_apply_from_state() {
  hy2_hop_enabled || return 0
  local start end target tmp backend
  start=$(jq -r '.nodes.hy2.port_hopping.range_start' "$STATE_FILE")
  end=$(jq -r '.nodes.hy2.port_hopping.range_end' "$STATE_FILE")
  target=$(jq -r '.nodes.hy2.port' "$STATE_FILE")
  hy2_hop_ensure_backend
  hy2_hop_apply_rules "$start" "$end" "$target" || return 1
  backend=$HY2_HOP_BACKEND
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg backend "$backend" '.nodes.hy2.port_hopping.backend=$backend' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
}

hy2_hop_write_unit() {
  cat > "$HY2_HOP_UNIT" <<'EOF'
[Unit]
Description=sing-box-oneclick Hysteria2 port hopping redirect
After=network-pre.target
Before=sing-box.service
ConditionPathExists=/usr/local/bin/sb

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sb hy2-hop apply
ExecStop=/usr/local/bin/sb hy2-hop clear
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$HY2_HOP_UNIT"
  systemctl daemon-reload
}

hy2_hop_remove_unit() {
  systemctl disable --now sing-box-oneclick-hy2-hop.service >/dev/null 2>&1 || true
  rm -f "$HY2_HOP_UNIT"
  systemctl daemon-reload >/dev/null 2>&1 || true
}

hy2_hop_validate_range() {
  local range=$1 start end span p
  [[ "$range" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]] || return 1
  start=${BASH_REMATCH[1]}
  end=${BASH_REMATCH[2]}
  validate_port "$start" || return 1
  validate_port "$end" || return 1
  (( start < end )) || return 1
  span=$((end - start + 1))
  (( span <= 20000 )) || { warn "为避免误开过大的 UDP 范围，单次最多允许 20000 个端口。"; return 1; }

  while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    if (( p >= start && p <= end )); then
      warn "检测到 UDP/$p 已有本机服务监听；端口跳跃会抢占该范围。"
      return 1
    fi
  done < <(ss -H -lnu 2>/dev/null | awk '{print $4}' | sed -nE 's/.*:([0-9]+)$/\1/p' | sort -nu)

  HY2_HOP_START=$start
  HY2_HOP_END=$end
}

hy2_hop_enable() {
  ensure_state
  jq -e '.nodes.hy2 != null' "$STATE_FILE" >/dev/null 2>&1 || { warn "请先部署 Hysteria2。"; return 0; }

  echo
  headmsg "启用 Hysteria2 端口跳跃"
  note "用途：当运营商只针对某一个 UDP 端口限速/阻断时，客户端在一段端口范围内随机切换。"
  note "它不会提高正常线路的峰值速度；如果运营商限制整个 UDP，开启也没有帮助。"
  warn "云厂商安全组/云防火墙必须放行所选 UDP 范围；范围越大，暴露面也越大。"
  read -r -p "  确认需要开启？[y/N] › " ans
  [[ ${ans,,} == y || ${ans,,} == yes ]] || { note "已保持关闭（推荐默认）。"; return 0; }

  local range interval start end target tmp old_state backend
  read -r -p "  跳跃端口范围 [20000-30000] › " range
  range=${range:-20000-30000}
  hy2_hop_validate_range "$range" || die "端口范围无效、过大或与现有 UDP 服务冲突。"
  start=$HY2_HOP_START
  end=$HY2_HOP_END

  read -r -p "  跳跃间隔秒数 [30] › " interval
  interval=${interval:-30}
  [[ "$interval" =~ ^[0-9]+$ ]] || die "跳跃间隔必须是整数秒。"
  (( interval >= 5 && interval <= 3600 )) || die "跳跃间隔需在 5-3600 秒之间。"
  target=$(jq -r '.nodes.hy2.port' "$STATE_FILE")

  hy2_hop_ensure_backend
  old_state=$(mktemp)
  cleanup_files+=("$old_state")
  cp -a "$STATE_FILE" "$old_state"

  hy2_hop_apply_rules "$start" "$end" "$target" || die "端口重定向规则应用失败。"
  backend=$HY2_HOP_BACKEND

  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --argjson start "$start" --argjson end "$end" --argjson interval "$interval" --arg backend "$backend" '
    .nodes.hy2.port_hopping={enabled:true,range_start:$start,range_end:$end,hop_interval:$interval,backend:$backend}
  ' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"

  if ! hy2_hop_write_unit || ! systemctl enable sing-box-oneclick-hy2-hop.service >/dev/null 2>&1; then
    cp -a "$old_state" "$STATE_FILE"
    hy2_hop_cleanup_rules
    die "无法写入端口跳跃持久化服务，已回滚。"
  fi

  rebuild_node_uri hy2 || true
  render_node_info
  if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then refresh_client_exports_if_present || true; fi

  info "HY2 端口跳跃已启用：UDP/${start}-${end} → UDP/${target}，每 ${interval}s 跳跃。"
  note "UFW 仍只需要允许实际 HY2 端口；NAT 会先把跳跃范围重定向到该端口。"
  warn "请务必在 VPS 厂商安全组/云防火墙放行 UDP/${start}-${end}。"
}

hy2_hop_disable() {
  ensure_state
  if ! hy2_hop_enabled; then
    note "HY2 端口跳跃当前已关闭。"
    hy2_hop_cleanup_rules
    hy2_hop_remove_unit
    return 0
  fi

  local tmp
  hy2_hop_cleanup_rules
  hy2_hop_remove_unit
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq '.nodes.hy2.port_hopping={enabled:false}' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  rebuild_node_uri hy2 || true
  render_node_info
  if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then refresh_client_exports_if_present || true; fi
  info "HY2 端口跳跃已关闭，客户端已恢复使用真实监听端口。"
}

hy2_hop_status() {
  ensure_state
  echo
  headmsg "Hysteria2 端口跳跃"
  if ! jq -e '.nodes.hy2 != null' "$STATE_FILE" >/dev/null 2>&1; then
    warn "尚未部署 Hysteria2。"
    return 0
  fi
  if ! hy2_hop_enabled; then
    ui_kv "状态" "关闭（推荐默认）"
    ui_kv "实际端口" "UDP/$(jq -r '.nodes.hy2.port' "$STATE_FILE")"
    return 0
  fi
  ui_kv "状态" "开启"
  ui_kv "范围" "UDP/$(hy2_hop_range_dash)"
  ui_kv "实际端口" "UDP/$(jq -r '.nodes.hy2.port' "$STATE_FILE")"
  ui_kv "跳跃间隔" "$(hy2_hop_interval_seconds)s"
  ui_kv "重定向" "$(jq -r '.nodes.hy2.port_hopping.backend // "unknown"' "$STATE_FILE")"
  if hy2_hop_rules_active; then
    info "端口重定向规则已生效。"
  else
    warn "端口跳跃已配置，但当前重定向规则不存在；可选择“重新应用规则”。"
  fi
}

hy2_port_hopping_menu() {
  while true; do
    hy2_hop_status
    echo
    ui_group "HY2 高级网络" "默认关闭，小白无需设置"
    ui_item 1 "启用 / 修改端口跳跃" "仅单端口 UDP 限速时使用"
    ui_item 2 "重新应用重定向规则" "重启/防火墙变更后修复"
    ui_item 3 "关闭端口跳跃" "恢复普通单端口"
    ui_group_end
    echo -e "  ${C_CYAN} 0${C_RESET}  返回"
    read -r -p "  请选择 › " choice
    case "$choice" in
      1) hy2_hop_enable ;;
      2)
        if hy2_hop_enabled; then
          hy2_hop_apply_from_state && info "端口跳跃规则已重新应用。" || warn "重新应用失败。"
        else
          warn "端口跳跃当前未启用。"
        fi
        ;;
      3) hy2_hop_disable ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

hy2_hop_cli() {
  case "${1:-menu}" in
    menu) hy2_port_hopping_menu ;;
    apply) hy2_hop_apply_from_state ;;
    clear) hy2_hop_cleanup_rules ;;
    status) hy2_hop_status ;;
    *) err "用法：sb hy2-hop [status|apply|clear]"; return 2 ;;
  esac
}

# Rebuild the HY2 URI with the official multi-port format when hopping is on.
rebuild_node_uri() {
  local key=$1
  if [[ "$key" != hy2 ]] || ! hy2_hop_enabled; then
    rebuild_node_uri_pre_hop "$key"
    return
  fi

  local address domain name name_enc password obfs insecure host uri range
  address=$(jq -r '.nodes.hy2.address // .nodes.hy2.domain // empty' "$STATE_FILE")
  domain=$(jq -r '.nodes.hy2.domain // .nodes.hy2.address // empty' "$STATE_FILE")
  name=$(jq -r '.nodes.hy2.name // "sing-box-Hysteria2"' "$STATE_FILE")
  name_enc=$(uri_encode "$name")
  password=$(jq -r '.nodes.hy2.password' "$STATE_FILE")
  obfs=$(jq -r '.nodes.hy2.obfs_password' "$STATE_FILE")
  insecure=$(jq -r '.nodes.hy2.insecure // false' "$STATE_FILE")
  host=$(uri_host "$address")
  range=$(hy2_hop_range_dash)
  uri="hysteria2://$(uri_encode "$password")@${host}:${range}/?sni=$(uri_encode "$domain")&obfs=salamander&obfs-password=$(uri_encode "$obfs")"
  [[ "$insecure" == true ]] && uri+="&insecure=1"
  uri+="#${name_enc}"

  local tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg uri "$uri" '.nodes.hy2.uri=$uri' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
}

singbox_outbound_for_key() {
  local key=$1 base range interval
  if [[ "$key" != hy2 ]] || ! hy2_hop_enabled; then
    singbox_outbound_for_key_pre_hop "$key"
    return
  fi
  base=$(singbox_outbound_for_key_pre_hop hy2)
  range=$(hy2_hop_range_colon)
  interval=$(hy2_hop_interval_seconds)
  jq --arg range "$range" --arg interval "${interval}s" '.server_ports=[$range] | .hop_interval=$interval' <<< "$base"
}

write_mihomo_proxy_hy2() {
  if ! hy2_hop_enabled; then
    write_mihomo_proxy_hy2_pre_hop
    return
  fi
  local name address port password obfs sni insecure range interval
  name=$(export_node_name hy2)
  address=$(jq -r '.nodes.hy2.address' "$STATE_FILE")
  port=$(jq -r '.nodes.hy2.port' "$STATE_FILE")
  password=$(jq -r '.nodes.hy2.password' "$STATE_FILE")
  obfs=$(jq -r '.nodes.hy2.obfs_password' "$STATE_FILE")
  sni=$(jq -r '.nodes.hy2.domain // .nodes.hy2.address' "$STATE_FILE")
  insecure=$(jq -r '.nodes.hy2.insecure // false' "$STATE_FILE")
  range=$(hy2_hop_range_dash)
  interval=$(hy2_hop_interval_seconds)
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: hysteria2
    server: $(yaml_quote "$address")
    port: $port
    ports: $range
    hop-interval: $interval
    password: $(yaml_quote "$password")
    obfs: salamander
    obfs-password: $(yaml_quote "$obfs")
    sni: $(yaml_quote "$sni")
    skip-cert-verify: $insecure
    alpn:
      - h3
EOF
}

# Rebuilding HY2 deliberately returns to the safe single-port default.
deploy_hysteria2() {
  if hy2_hop_enabled; then
    warn "检测到旧 HY2 端口跳跃配置；重建 HY2 时将先关闭，完成后可在“HY2 高级网络”重新开启。"
    hy2_hop_disable
  fi
  deploy_hysteria2_pre_hop "$@"
  echo
  note "新手无需开启端口跳跃。只有出现“换一个 UDP 端口速度就恢复”的情况，再运行 sb hy2-hop。"
}

state_remove_node() {
  local key=$1
  if [[ "$key" == hy2 ]]; then
    hy2_hop_cleanup_rules
    hy2_hop_remove_unit
  fi
  state_remove_node_pre_hop "$@"
}

post_parameter_change() {
  post_parameter_change_pre_hop "$@"
  local key=$1
  if [[ "$key" == hy2 ]] && hy2_hop_enabled; then
    if hy2_hop_apply_from_state; then
      info "HY2 实际监听端口变化后，端口跳跃重定向已同步更新。"
    else
      warn "HY2 节点已修改，但端口跳跃规则重建失败；请运行 sb hy2-hop status 检查。"
    fi
  fi
}
