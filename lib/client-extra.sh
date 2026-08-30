#!/usr/bin/env bash
# shellcheck shell=bash

# v1.6 client export extensions. Loaded after client-export.sh so runtime
# dispatch includes AnyTLS / Trojan / Shadowsocks without changing the stable
# export pipeline and HTTPS subscription publisher.

managed_export_keys() {
  ensure_state
  local key
  for key in reality hy2 tuic ws anytls trojan ss; do
    jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 && printf '%s\n' "$key"
  done
}

export_node_tag() {
  case "$1" in
    reality) printf '%s' 'proxy-reality' ;;
    hy2) printf '%s' 'proxy-hy2' ;;
    tuic) printf '%s' 'proxy-tuic' ;;
    ws) printf '%s' 'proxy-cf-ws' ;;
    anytls) printf '%s' 'proxy-anytls' ;;
    trojan) printf '%s' 'proxy-trojan' ;;
    ss) printf '%s' 'proxy-ss' ;;
    *) return 1 ;;
  esac
}

singbox_outbound_for_key() {
  local key=$1 address port domain insecure uuid password obfs congestion path tls pub sid tag method
  address=$(jq -r --arg k "$key" '.nodes[$k].address // .nodes[$k].domain // empty' "$STATE_FILE")
  port=$(jq -r --arg k "$key" '.nodes[$k].port' "$STATE_FILE")
  tag=$(export_node_tag "$key")

  case "$key" in
    reality)
      uuid=$(jq -r '.nodes.reality.uuid' "$STATE_FILE")
      domain=$(jq -r '.nodes.reality.reality_sni' "$STATE_FILE")
      pub=$(jq -r '.nodes.reality.public_key' "$STATE_FILE")
      sid=$(jq -r '.nodes.reality.short_id' "$STATE_FILE")
      jq -n --arg tag "$tag" --arg server "$address" --argjson port "$port" \
        --arg uuid "$uuid" --arg sni "$domain" --arg pub "$pub" --arg sid "$sid" \
        '{type:"vless",tag:$tag,server:$server,server_port:$port,uuid:$uuid,flow:"xtls-rprx-vision",tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"},reality:{enabled:true,public_key:$pub,short_id:$sid}}}'
      ;;
    hy2)
      domain=$(jq -r '.nodes.hy2.domain // .nodes.hy2.address' "$STATE_FILE")
      password=$(jq -r '.nodes.hy2.password' "$STATE_FILE")
      obfs=$(jq -r '.nodes.hy2.obfs_password' "$STATE_FILE")
      insecure=$(jq -r '.nodes.hy2.insecure // false' "$STATE_FILE")
      jq -n --arg tag "$tag" --arg server "$address" --argjson port "$port" \
        --arg password "$password" --arg obfs "$obfs" --arg sni "$domain" --argjson insecure "$insecure" \
        '{type:"hysteria2",tag:$tag,server:$server,server_port:$port,password:$password,obfs:{type:"salamander",password:$obfs},tls:{enabled:true,server_name:$sni,insecure:$insecure}}'
      ;;
    tuic)
      domain=$(jq -r '.nodes.tuic.domain // .nodes.tuic.address' "$STATE_FILE")
      uuid=$(jq -r '.nodes.tuic.uuid' "$STATE_FILE")
      password=$(jq -r '.nodes.tuic.password' "$STATE_FILE")
      congestion=$(jq -r '.nodes.tuic.congestion_control // "bbr"' "$STATE_FILE")
      insecure=$(jq -r '.nodes.tuic.insecure // false' "$STATE_FILE")
      jq -n --arg tag "$tag" --arg server "$address" --argjson port "$port" \
        --arg uuid "$uuid" --arg password "$password" --arg congestion "$congestion" \
        --arg sni "$domain" --argjson insecure "$insecure" \
        '{type:"tuic",tag:$tag,server:$server,server_port:$port,uuid:$uuid,password:$password,congestion_control:$congestion,udp_relay_mode:"native",zero_rtt_handshake:false,heartbeat:"10s",tls:{enabled:true,server_name:$sni,insecure:$insecure,alpn:["h3"]}}'
      ;;
    ws)
      domain=$(jq -r '.nodes.ws.domain // .nodes.ws.address' "$STATE_FILE")
      uuid=$(jq -r '.nodes.ws.uuid' "$STATE_FILE")
      path=$(jq -r '.nodes.ws.path' "$STATE_FILE")
      tls=$(jq -r '.nodes.ws.tls_enabled // true' "$STATE_FILE")
      if [[ "$tls" == true ]]; then
        jq -n --arg tag "$tag" --arg server "$address" --argjson port "$port" \
          --arg uuid "$uuid" --arg sni "$domain" --arg path "$path" --arg host "$domain" \
          '{type:"vless",tag:$tag,server:$server,server_port:$port,uuid:$uuid,tls:{enabled:true,server_name:$sni},transport:{type:"ws",path:$path,headers:{Host:$host}}}'
      else
        jq -n --arg tag "$tag" --arg server "$address" --argjson port "$port" \
          --arg uuid "$uuid" --arg path "$path" --arg host "$domain" \
          '{type:"vless",tag:$tag,server:$server,server_port:$port,uuid:$uuid,transport:{type:"ws",path:$path,headers:{Host:$host}}}'
      fi
      ;;
    anytls)
      domain=$(jq -r '.nodes.anytls.domain // .nodes.anytls.address' "$STATE_FILE")
      password=$(jq -r '.nodes.anytls.password' "$STATE_FILE")
      insecure=$(jq -r '.nodes.anytls.insecure // false' "$STATE_FILE")
      jq -n --arg tag "$tag" --arg server "$address" --argjson port "$port" \
        --arg password "$password" --arg sni "$domain" --argjson insecure "$insecure" \
        '{type:"anytls",tag:$tag,server:$server,server_port:$port,password:$password,tls:{enabled:true,server_name:$sni,insecure:$insecure,utls:{enabled:true,fingerprint:"chrome"}}}'
      ;;
    trojan)
      domain=$(jq -r '.nodes.trojan.domain // .nodes.trojan.address' "$STATE_FILE")
      password=$(jq -r '.nodes.trojan.password' "$STATE_FILE")
      insecure=$(jq -r '.nodes.trojan.insecure // false' "$STATE_FILE")
      jq -n --arg tag "$tag" --arg server "$address" --argjson port "$port" \
        --arg password "$password" --arg sni "$domain" --argjson insecure "$insecure" \
        '{type:"trojan",tag:$tag,server:$server,server_port:$port,password:$password,tls:{enabled:true,server_name:$sni,insecure:$insecure,utls:{enabled:true,fingerprint:"chrome"}}}'
      ;;
    ss)
      method=$(jq -r '.nodes.ss.method' "$STATE_FILE")
      password=$(jq -r '.nodes.ss.password' "$STATE_FILE")
      jq -n --arg tag "$tag" --arg server "$address" --argjson port "$port" \
        --arg method "$method" --arg password "$password" \
        '{type:"shadowsocks",tag:$tag,server:$server,server_port:$port,method:$method,password:$password}'
      ;;
    *) return 1 ;;
  esac
}

write_mihomo_proxy_anytls() {
  local name address port password sni insecure
  name=$(export_node_name anytls)
  address=$(jq -r '.nodes.anytls.address' "$STATE_FILE")
  port=$(jq -r '.nodes.anytls.port' "$STATE_FILE")
  password=$(jq -r '.nodes.anytls.password' "$STATE_FILE")
  sni=$(jq -r '.nodes.anytls.domain // .nodes.anytls.address' "$STATE_FILE")
  insecure=$(jq -r '.nodes.anytls.insecure // false' "$STATE_FILE")
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: anytls
    server: $(yaml_quote "$address")
    port: $port
    password: $(yaml_quote "$password")
    client-fingerprint: chrome
    udp: true
    sni: $(yaml_quote "$sni")
    skip-cert-verify: $insecure
EOF
}

write_mihomo_proxy_trojan() {
  local name address port password sni insecure
  name=$(export_node_name trojan)
  address=$(jq -r '.nodes.trojan.address' "$STATE_FILE")
  port=$(jq -r '.nodes.trojan.port' "$STATE_FILE")
  password=$(jq -r '.nodes.trojan.password' "$STATE_FILE")
  sni=$(jq -r '.nodes.trojan.domain // .nodes.trojan.address' "$STATE_FILE")
  insecure=$(jq -r '.nodes.trojan.insecure // false' "$STATE_FILE")
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: trojan
    server: $(yaml_quote "$address")
    port: $port
    password: $(yaml_quote "$password")
    udp: true
    sni: $(yaml_quote "$sni")
    client-fingerprint: chrome
    skip-cert-verify: $insecure
EOF
}

write_mihomo_proxy_ss() {
  local name address port method password
  name=$(export_node_name ss)
  address=$(jq -r '.nodes.ss.address' "$STATE_FILE")
  port=$(jq -r '.nodes.ss.port' "$STATE_FILE")
  method=$(jq -r '.nodes.ss.method' "$STATE_FILE")
  password=$(jq -r '.nodes.ss.password' "$STATE_FILE")
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: ss
    server: $(yaml_quote "$address")
    port: $port
    cipher: $(yaml_quote "$method")
    password: $(yaml_quote "$password")
    udp: true
EOF
}

export_mihomo_client() {
  ensure_client_export_dir
  local target key name names=()
  target="${CLIENT_EXPORT_DIR}/mihomo.yaml"

  {
    cat <<'EOF'
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: true

proxies:
EOF
    while IFS= read -r key; do
      [[ -n "$key" ]] || continue
      name=$(export_node_name "$key")
      names+=("$name")
      case "$key" in
        reality) write_mihomo_proxy_reality ;;
        hy2) write_mihomo_proxy_hy2 ;;
        tuic) write_mihomo_proxy_tuic ;;
        ws) write_mihomo_proxy_ws ;;
        anytls) write_mihomo_proxy_anytls ;;
        trojan) write_mihomo_proxy_trojan ;;
        ss) write_mihomo_proxy_ss ;;
      esac
    done < <(managed_export_keys)

    echo
    echo 'proxy-groups:'
    echo '  - name: PROXY'
    echo '    type: select'
    echo '    proxies:'
    for name in "${names[@]}"; do
      printf '      - %s\n' "$(yaml_quote "$name")"
    done
    echo '      - DIRECT'
    echo
    echo 'rules:'
    echo '  - MATCH,PROXY'
  } > "$target"

  chmod 600 "$target"
  [[ ${CLIENT_EXPORT_QUIET:-false} == true ]] || info "Mihomo 客户端配置：$target"
}
