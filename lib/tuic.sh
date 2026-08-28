#!/usr/bin/env bash
# shellcheck shell=bash

# TUIC v5 support.
# Loaded after lib/protocols.sh so it can reuse certificate, state,
# firewall and safe candidate/apply helpers.

deploy_tuic() {
  ensure_singbox
  install_deps
  sync_time

  local tag="tuic-in"
  local domain node_addr port default_port uuid password congestion host name uri inbound candidate state name_enc

  echo
  headmsg "===== 部署 / 重建 TUIC v5 ====="
  note "TUIC 基于 QUIC/UDP + TLS。普通 Cloudflare 橙云不能代理该流量；域名应使用 DNS only（灰云）。"
  note "TUIC 的 QUIC 拥塞控制与 Linux TCP BBR 是两套机制；这里默认使用 TUIC 自身的 bbr。"
  note "为降低重放攻击风险，本脚本固定关闭 TUIC 0-RTT。"

  read -r -p "TUIC 域名（必须直接解析到 VPS）: " domain
  is_hostname "$domain" || die "TUIC 必须使用有效域名以签发 TLS 证书。"
  check_domain "$domain" direct
  node_addr=$domain

  default_port=8443
  if port_in_use_by_other udp "$default_port" "$tag"; then
    default_port=10443
    warn "UDP/8443 已被占用，默认改用 UDP/10443。"
  fi

  read -r -p "UDP 监听端口 [${default_port}]: " port
  port=${port:-$default_port}
  validate_port "$port" || die "端口必须为 1-65535。"
  if port_in_use_by_other udp "$port" "$tag"; then
    warn "UDP/$port 已被占用："
    show_port_owner udp "$port"
    die "请选择其他 UDP 端口。"
  fi

  ensure_certificate "$domain"

  uuid=$(sing-box generate uuid)
  password=$(random_hex 24)

  read -r -p "TUIC QUIC 拥塞控制 [bbr]（可选 bbr/cubic/new_reno）: " congestion
  congestion=${congestion:-bbr}
  congestion=${congestion,,}
  case "$congestion" in
    bbr|cubic|new_reno) ;;
    *) die "拥塞控制只允许：bbr / cubic / new_reno。" ;;
  esac

  inbound=$(jq -n \
    --arg uuid "$uuid" \
    --arg password "$password" \
    --arg congestion "$congestion" \
    --arg domain "$domain" \
    --arg cert "$CERT_PATH" \
    --arg key "$KEY_PATH" \
    --argjson port "$port" \
    '{
      type:"tuic",
      tag:"tuic-in",
      listen:"::",
      listen_port:$port,
      users:[{name:"main",uuid:$uuid,password:$password}],
      congestion_control:$congestion,
      auth_timeout:"3s",
      zero_rtt_handshake:false,
      heartbeat:"10s",
      tls:{
        enabled:true,
        server_name:$domain,
        alpn:["h3"],
        certificate_path:$cert,
        key_path:$key
      }
    }')

  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_with_inbound "$tag" "$inbound" "$candidate"
  apply_candidate "$candidate" "TUIC v5"

  host=$(uri_host "$node_addr")
  name="sing-box-TUIC"
  name_enc=$(uri_encode "$name")
  uri="tuic://${uuid}:$(uri_encode "$password")@${host}:${port}?sni=$(uri_encode "$domain")&alpn=h3&congestion_control=$(uri_encode "$congestion")&udp_relay_mode=native&zero_rtt_handshake=0#${name_enc}"

  state=$(jq -n \
    --arg name "$name" \
    --arg address "$node_addr" \
    --arg domain "$domain" \
    --argjson port "$port" \
    --arg uuid "$uuid" \
    --arg password "$password" \
    --arg congestion "$congestion" \
    --arg uri "$uri" \
    '{name:$name,type:"TUIC v5",address:$address,domain:$domain,port:$port,uuid:$uuid,password:$password,congestion_control:$congestion,uri:$uri,firewall:"udp",certificate:true}')
  state_set_node tuic "$state"

  allow_if_ufw_active "$port" udp
  echo
  show_nodes
}

# Extend the generic node removal menu with TUIC.
# This function intentionally overrides the implementation from protocols.sh.
remove_node() {
  ensure_state
  local key tag candidate
  echo
  headmsg "===== 删除脚本管理的节点 ====="
  echo "1. VLESS Reality"
  echo "2. Hysteria2"
  echo "3. Cloudflare VLESS WS+TLS"
  echo "4. TUIC v5"
  read -r -p "请选择: " n

  case "$n" in
    1) key=reality; tag=vless-reality-in ;;
    2) key=hy2; tag=hysteria2-in ;;
    3) key=ws; tag=vless-ws-tls-in ;;
    4) key=tuic; tag=tuic-in ;;
    *) warn "无效选择。"; return 0 ;;
  esac

  if ! jq -e --arg key "$key" '.nodes[$key] != null' "$STATE_FILE" >/dev/null; then
    warn "状态文件中没有该节点。"
  fi

  [[ -f "$CONFIG_FILE" ]] || { state_remove_node "$key"; return 0; }
  candidate=$(mktemp)
  cleanup_files+=("$candidate")
  make_candidate_without_inbound "$tag" "$candidate"
  apply_candidate "$candidate" "删除节点"
  state_remove_node "$key"
  info "节点已删除。证书和 BBR 设置未自动删除。"
}
