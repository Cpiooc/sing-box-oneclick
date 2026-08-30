#!/usr/bin/env bash
# shellcheck shell=bash

# Optional Hysteria2 port hopping for sing-box servers.
# sing-box inbound listens on one real UDP port; nftables redirects a user-
# selected public UDP range to that port. Disabled by default.

HY2_HOP_TABLE="sb_oneclick_hy2hop"
HY2_HOP_SERVICE="sing-box-oneclick-hy2-hop.service"
HY2_HOP_UNIT="/etc/systemd/system/${HY2_HOP_SERVICE}"
HY2_HOP_SCRIPT="${APP_DIR}/hy2-hop-apply.sh"

hy2_hop_enabled() {
  [[ -f "$STATE_FILE" ]] \
    && [[ $(jq -r '.nodes.hy2.port_hopping.enabled // false' "$STATE_FILE" 2>/dev/null) == true ]]
}

hy2_hop_validate_range() {
  local range=$1 start end
  [[ "$range" =~ ^([0-9]+)-([0-9]+)$ ]] || return 1
  start=${BASH_REMATCH[1]}
  end=${BASH_REMATCH[2]}
  validate_port "$start" || return 1
  validate_port "$end" || return 1
  (( 10#$start < 10#$end ))
}

hy2_hop_range_to_singbox() {
  printf '%s' "${1/-/:}"
}

hy2_hop_range_conflicts() {
  local range=$1 target=$2 start end p key
  start=${range%-*}
  end=${range#*-}

  if [[ -f "$STATE_FILE" ]]; then
    while IFS=$'\t' read -r key p; do
      [[ "$key" == hy2 || -z "$p" || ! "$p" =~ ^[0-9]+$ ]] && continue
      if (( 10#$p >= 10#$start && 10#$p <= 10#$end )); then
        warn "端口跳跃范围包含已管理节点端口：${key} -> ${p}。"
        return 0
      fi
    done < <(jq -r '.nodes | to_entries[] | [.key, (.value.port // "")] | @tsv' "$STATE_FILE" 2>/dev/null)
  fi

  while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    [[ "$p" == "$target" ]] && continue
    if (( 10#$p >= 10#$start && 10#$p <= 10#$end )); then
      warn "UDP/$p 已有其他程序监听，不能被端口跳跃范围覆盖。"
      return 0
    fi
  done < <(ss -H -lnu 2>/dev/null | awk '{print $5}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -nu)

  return 1
}

ensure_nftables() {
  if ! have nft; then
    info "安装 nftables（仅用于 HY2 端口跳跃重定向）..."
    apt-get update
    apt-get install -y nftables
  fi
  have nft || die "nftables 安装失败，无法启用端口跳跃。"
}

hy2_hop_write_runtime() {
  local range=$1 target=$2 start end
  start=${range%-*}
  end=${range#*-}
  install -d -m 700 "$APP_DIR"

  cat > "$HY2_HOP_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
TABLE="$HY2_HOP_TABLE"
ACTION=\${1:-apply}
case "\$ACTION" in
  apply)
    nft delete table inet "\$TABLE" 2>/dev/null || true
    nft add table inet "\$TABLE"
    nft 'add chain inet $HY2_HOP_TABLE prerouting { type nat hook prerouting priority dstnat; policy accept; }'
    nft add rule inet "$HY2_HOP_TABLE" prerouting udp dport ${start}-${end} counter redirect to :${target}
    ;;
  cleanup)
    nft delete table inet "\$TABLE" 2>/dev/null || true
    ;;
  *) exit 2 ;;
esac
EOF
  chmod 700 "$HY2_HOP_SCRIPT"

  cat > "$HY2_HOP_UNIT" <<EOF
[Unit]
Description=sing-box-oneclick Hysteria2 port hopping
After=network-online.target sing-box.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$HY2_HOP_SCRIPT apply
ExecStop=$HY2_HOP_SCRIPT cleanup

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$HY2_HOP_UNIT"
  systemctl daemon-reload
}

hy2_hop_allow_ufw() {
  local range=$1
  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "${range}/udp" >/dev/null || true
    info "UFW 已放行 UDP/${range}。"
  else
    warn "UFW 未启用；请确认云厂商安全组同时放行 UDP/${range}。"
  fi
}

hy2_hop_remove_ufw() {
  local range=$1
  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw --force delete allow "${range}/udp" >/dev/null 2>&1 || true
  fi
}

hy2_hop_store_state() {
  local enabled=$1 range=${2:-} target=${3:-} tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  if [[ "$enabled" == true ]]; then
    jq --arg range "$range" --argjson target "$target" '
      .nodes.hy2.port_hopping={enabled:true,range:$range,hop_interval:"30s",target_port:$target,backend:"nftables"}
    ' "$STATE_FILE" > "$tmp"
  else
    jq '.nodes.hy2.port_hopping={enabled:false}' "$STATE_FILE" > "$tmp"
  fi
  install -m 600 "$tmp" "$STATE_FILE"
}

hy2_hop_apply_current() {
  hy2_hop_enabled || return 0
  local range target
  range=$(jq -r '.nodes.hy2.port_hopping.range' "$STATE_FILE")
  target=$(jq -r '.nodes.hy2.port' "$STATE_FILE")
  hy2_hop_validate_range "$range" || return 1
  ensure_nftables
  hy2_hop_write_runtime "$range" "$target"
  systemctl enable --now "$HY2_HOP_SERVICE" >/dev/null
  "$HY2_HOP_SCRIPT" apply
  hy2_hop_store_state true "$range" "$target"
}

hy2_hop_enable() {
  ensure_state
  jq -e '.nodes.hy2 != null' "$STATE_FILE" >/dev/null 2>&1 || {
    warn "请先部署 Hysteria2，再开启端口跳跃。"
    return 0
  }

  local ans range target current
  echo
  headmsg "Hysteria2 · UDP 端口跳跃"
  note "这是高级可选功能，默认不需要开启。"
  note "仅当“某一个 UDP 端口容易被限速/阻断，换端口后恢复”时才可能有帮助。"
  warn "如果运营商限制的是全部 UDP，端口跳跃不会改善。开启后还要在云厂商安全组放行整段 UDP 端口。"
  read -r -p "  确认启用？[y/N] › " ans
  [[ ${ans,,} == y || ${ans,,} == yes ]] || { note "保持关闭（推荐默认）。"; return 0; }

  current=$(jq -r '.nodes.hy2.port_hopping.range // empty' "$STATE_FILE")
  read -r -p "  跳跃端口范围 [${current:-20000-30000}] › " range
  range=${range:-${current:-20000-30000}}
  hy2_hop_validate_range "$range" || die "范围格式应类似 20000-30000，且起始端口必须小于结束端口。"
  target=$(jq -r '.nodes.hy2.port' "$STATE_FILE")

  if hy2_hop_range_conflicts "$range" "$target"; then
    die "该端口范围与现有 UDP 服务冲突，请换一个范围。"
  fi

  ensure_nftables
  if hy2_hop_enabled; then
    local old_range
    old_range=$(jq -r '.nodes.hy2.port_hopping.range // empty' "$STATE_FILE")
    [[ -n "$old_range" && "$old_range" != "$range" ]] && hy2_hop_remove_ufw "$old_range"
  fi
  hy2_hop_write_runtime "$range" "$target"
  systemctl enable --now "$HY2_HOP_SERVICE" >/dev/null
  "$HY2_HOP_SCRIPT" apply
  hy2_hop_store_state true "$range" "$target"
  hy2_hop_allow_ufw "$range"
  rebuild_node_uri hy2 || true
  render_node_info
  if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then
    refresh_client_exports_if_present || true
  fi

  info "HY2 端口跳跃已启用：UDP/${range} → 实际 HY2 UDP/${target}。"
  note "sing-box / Mihomo 导出会自动加入端口范围，默认每 30 秒跳跃。"
  warn "别忘了在 VPS 厂商安全组放行 UDP/${range}；否则客户端仍无法使用跳跃端口。"
}

hy2_hop_disable_quiet() {
  local range=""
  [[ -f "$STATE_FILE" ]] && range=$(jq -r '.nodes.hy2.port_hopping.range // empty' "$STATE_FILE" 2>/dev/null || true)
  systemctl stop "$HY2_HOP_SERVICE" 2>/dev/null || true
  systemctl disable "$HY2_HOP_SERVICE" 2>/dev/null || true
  have nft && nft delete table inet "$HY2_HOP_TABLE" 2>/dev/null || true
  rm -f "$HY2_HOP_UNIT" "$HY2_HOP_SCRIPT"
  systemctl daemon-reload 2>/dev/null || true
  [[ -n "$range" ]] && hy2_hop_remove_ufw "$range"
  if [[ -f "$STATE_FILE" ]] && jq -e '.nodes.hy2 != null' "$STATE_FILE" >/dev/null 2>&1; then
    hy2_hop_store_state false
    rebuild_node_uri hy2 || true
    render_node_info
    if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then
      refresh_client_exports_if_present || true
    fi
  fi
}

hy2_hop_disable() {
  if ! hy2_hop_enabled; then
    note "HY2 端口跳跃当前已关闭。"
    return 0
  fi
  hy2_hop_disable_quiet
  info "HY2 端口跳跃已关闭，并清理 nftables/systemd 规则。"
  note "云厂商安全组中的旧 UDP 范围需要你在控制台手工删除；脚本不会远程修改厂商防火墙。"
}

hy2_hop_status() {
  echo
  headmsg "HY2 端口跳跃状态"
  if ! jq -e '.nodes.hy2 != null' "$STATE_FILE" >/dev/null 2>&1; then
    warn "尚未部署 Hysteria2。"
    return 0
  fi
  if hy2_hop_enabled; then
    ui_kv "状态" "Enabled"
    ui_kv "公网范围" "UDP/$(jq -r '.nodes.hy2.port_hopping.range' "$STATE_FILE")"
    ui_kv "实际监听" "UDP/$(jq -r '.nodes.hy2.port' "$STATE_FILE")"
    ui_kv "跳跃间隔" "30s"
    ui_kv "规则" "$(systemctl is-active "$HY2_HOP_SERVICE" 2>/dev/null || echo inactive)"
  else
    ui_kv "状态" "Disabled（推荐默认）"
    ui_kv "实际监听" "UDP/$(jq -r '.nodes.hy2.port' "$STATE_FILE")"
  fi
}

hy2_hop_menu() {
  local n
  while true; do
    hy2_hop_status
    echo
    ui_item 1 "启用 / 重新配置" "高级功能 · 默认关闭"
    ui_item 2 "关闭端口跳跃" "清理本机规则"
    echo -e "  ${C_CYAN} 0${C_RESET}  返回"
    read -r -p "  请选择 › " n
    case "$n" in
      1) hy2_hop_enable ;;
      2) hy2_hop_disable ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

# Extend URI rebuilding with the official multi-port host format while hopping.
if declare -F rebuild_node_uri >/dev/null 2>&1; then
  eval "$(declare -f rebuild_node_uri | sed '1s/rebuild_node_uri/rebuild_node_uri_v16_base/')"
fi
rebuild_node_uri() {
  local key=$1
  if [[ "$key" != hy2 ]] || ! hy2_hop_enabled; then
    rebuild_node_uri_v16_base "$@"
    return $?
  fi

  local address domain password obfs insecure host name name_enc range uri tmp
  address=$(jq -r '.nodes.hy2.address // .nodes.hy2.domain' "$STATE_FILE")
  domain=$(jq -r '.nodes.hy2.domain // .nodes.hy2.address' "$STATE_FILE")
  password=$(jq -r '.nodes.hy2.password' "$STATE_FILE")
  obfs=$(jq -r '.nodes.hy2.obfs_password' "$STATE_FILE")
  insecure=$(jq -r '.nodes.hy2.insecure // false' "$STATE_FILE")
  range=$(jq -r '.nodes.hy2.port_hopping.range' "$STATE_FILE")
  name=$(jq -r '.nodes.hy2.name // "sing-box-Hysteria2"' "$STATE_FILE")
  name_enc=$(uri_encode "$name")
  host=$(uri_host "$address")
  uri="hysteria2://$(uri_encode "$password")@${host}:${range}?sni=$(uri_encode "$domain")&obfs=salamander&obfs-password=$(uri_encode "$obfs")"
  [[ "$insecure" == true ]] && uri+="&insecure=1"
  uri+="#${name_enc}"
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg uri "$uri" '.nodes.hy2.uri=$uri' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
}

# Extend sing-box client export: server_ports overrides server_port.
if declare -F singbox_outbound_for_key >/dev/null 2>&1; then
  eval "$(declare -f singbox_outbound_for_key | sed '1s/singbox_outbound_for_key/singbox_outbound_for_key_v16_base/')"
fi
singbox_outbound_for_key() {
  local key=$1
  if [[ "$key" != hy2 ]] || ! hy2_hop_enabled; then
    singbox_outbound_for_key_v16_base "$@"
    return $?
  fi

  local address domain password obfs insecure range ports tag
  address=$(jq -r '.nodes.hy2.address // .nodes.hy2.domain' "$STATE_FILE")
  domain=$(jq -r '.nodes.hy2.domain // .nodes.hy2.address' "$STATE_FILE")
  password=$(jq -r '.nodes.hy2.password' "$STATE_FILE")
  obfs=$(jq -r '.nodes.hy2.obfs_password' "$STATE_FILE")
  insecure=$(jq -r '.nodes.hy2.insecure // false' "$STATE_FILE")
  range=$(jq -r '.nodes.hy2.port_hopping.range' "$STATE_FILE")
  ports=$(hy2_hop_range_to_singbox "$range")
  tag=$(export_node_tag hy2)
  jq -n --arg tag "$tag" --arg server "$address" --arg ports "$ports" \
    --arg password "$password" --arg obfs "$obfs" --arg sni "$domain" --argjson insecure "$insecure" \
    '{type:"hysteria2",tag:$tag,server:$server,server_ports:[$ports],hop_interval:"30s",password:$password,obfs:{type:"salamander",password:$obfs},tls:{enabled:true,server_name:$sni,insecure:$insecure}}'
}

# Extend Mihomo export with ports + hop-interval.
if declare -F write_mihomo_proxy_hy2 >/dev/null 2>&1; then
  eval "$(declare -f write_mihomo_proxy_hy2 | sed '1s/write_mihomo_proxy_hy2/write_mihomo_proxy_hy2_v16_base/')"
fi
write_mihomo_proxy_hy2() {
  if ! hy2_hop_enabled; then
    write_mihomo_proxy_hy2_v16_base "$@"
    return $?
  fi
  local name address port range password obfs sni insecure
  name=$(export_node_name hy2)
  address=$(jq -r '.nodes.hy2.address' "$STATE_FILE")
  port=$(jq -r '.nodes.hy2.port' "$STATE_FILE")
  range=$(jq -r '.nodes.hy2.port_hopping.range' "$STATE_FILE")
  password=$(jq -r '.nodes.hy2.password' "$STATE_FILE")
  obfs=$(jq -r '.nodes.hy2.obfs_password' "$STATE_FILE")
  sni=$(jq -r '.nodes.hy2.domain // .nodes.hy2.address' "$STATE_FILE")
  insecure=$(jq -r '.nodes.hy2.insecure // false' "$STATE_FILE")
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: hysteria2
    server: $(yaml_quote "$address")
    port: $port
    ports: $(yaml_quote "$range")
    hop-interval: 30
    password: $(yaml_quote "$password")
    obfs: salamander
    obfs-password: $(yaml_quote "$obfs")
    sni: $(yaml_quote "$sni")
    skip-cert-verify: $insecure
    alpn:
      - h3
EOF
}

# If HY2's real listen port changes, rebuild the redirect target automatically.
if declare -F post_parameter_change >/dev/null 2>&1; then
  eval "$(declare -f post_parameter_change | sed '1s/post_parameter_change/post_parameter_change_v16_base/')"
fi
post_parameter_change() {
  local key=${1:-} old_port=${2:-} new_port=${3:-}
  post_parameter_change_v16_base "$@"
  if [[ "$key" == hy2 && -n "$new_port" && "$new_port" != "$old_port" ]] && hy2_hop_enabled; then
    hy2_hop_apply_current
    rebuild_node_uri hy2 || true
    if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then
      refresh_client_exports_if_present || true
    fi
    note "HY2 跳跃规则已自动指向新的实际监听端口 UDP/${new_port}。"
  fi
}

# Removing HY2 also removes its port-hopping rules.
if declare -F state_remove_node >/dev/null 2>&1; then
  eval "$(declare -f state_remove_node | sed '1s/state_remove_node/state_remove_node_v16_base/')"
fi
state_remove_node() {
  local key=$1
  if [[ "$key" == hy2 ]] && hy2_hop_enabled; then
    hy2_hop_disable_quiet
  fi
  state_remove_node_v16_base "$@"
}
