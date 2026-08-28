#!/usr/bin/env bash
# shellcheck shell=bash

CLIENT_EXPORT_DIR="${APP_DIR}/exports"
CLIENT_EXPORT_MARKER="${CLIENT_EXPORT_DIR}/.auto-refresh"

ensure_client_export_dir() {
  install -d -m 700 "$CLIENT_EXPORT_DIR"
}

managed_export_keys() {
  ensure_state
  local key
  for key in reality hy2 tuic ws; do
    jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 && printf '%s\n' "$key"
  done
}

export_node_tag() {
  case "$1" in
    reality) printf '%s' 'proxy-reality' ;;
    hy2) printf '%s' 'proxy-hy2' ;;
    tuic) printf '%s' 'proxy-tuic' ;;
    ws) printf '%s' 'proxy-cf-ws' ;;
    *) return 1 ;;
  esac
}

export_node_name() {
  jq -r --arg k "$1" '.nodes[$k].name // $k' "$STATE_FILE"
}

yaml_quote() {
  local escaped
  escaped=$(printf '%s' "$1" | sed "s/'/''/g")
  printf "'%s'" "$escaped"
}

singbox_outbound_for_key() {
  local key=$1 address port domain insecure uuid password obfs congestion path tls pub sid tag
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
        '{type:"vless",tag:$tag,server:$server,server_port:$port,uuid:$uuid,flow:"xtls-rprx-vision",tls:{enabled:true,server_name:$sni,reality:{enabled:true,public_key:$pub,short_id:$sid}}}'
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
    *) return 1 ;;
  esac
}

export_singbox_client() {
  ensure_client_export_dir
  local key outbound tmp_arr next_arr first_tag="" target
  tmp_arr=$(mktemp)
  cleanup_files+=("$tmp_arr")
  printf '%s\n' '[]' > "$tmp_arr"

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    outbound=$(singbox_outbound_for_key "$key") || continue
    [[ -n "$first_tag" ]] || first_tag=$(export_node_tag "$key")
    next_arr=$(mktemp)
    cleanup_files+=("$next_arr")
    jq --argjson item "$outbound" '. + [$item]' "$tmp_arr" > "$next_arr"
    mv -f "$next_arr" "$tmp_arr"
  done < <(managed_export_keys)

  [[ -n "$first_tag" ]] || { warn "没有节点可导出。"; return 1; }
  target="${CLIENT_EXPORT_DIR}/sing-box-client.json"

  jq -n --argjson proxies "$(cat "$tmp_arr")" --arg final "$first_tag" '
    {
      log:{level:"warn",timestamp:true},
      dns:{servers:[{type:"local",tag:"local"}],final:"local"},
      inbounds:[{type:"mixed",tag:"mixed-in",listen:"127.0.0.1",listen_port:2080}],
      outbounds:($proxies + [{type:"direct",tag:"direct"}]),
      route:{final:$final,default_domain_resolver:"local",auto_detect_interface:true}
    }
  ' > "$target"
  chmod 600 "$target"

  if have sing-box; then
    if ! sing-box check -c "$target"; then
      warn "生成的 sing-box 客户端配置未通过当前 sing-box 校验。"
      note "失败文件暂时保留在 $target，便于诊断；修复后重新运行 sb export 即可覆盖。"
      return 1
    fi
  fi

  [[ ${CLIENT_EXPORT_QUIET:-false} == true ]] || info "sing-box 客户端配置：$target"
}

write_mihomo_proxy_reality() {
  local name address port uuid sni pub sid
  name=$(export_node_name reality)
  address=$(jq -r '.nodes.reality.address' "$STATE_FILE")
  port=$(jq -r '.nodes.reality.port' "$STATE_FILE")
  uuid=$(jq -r '.nodes.reality.uuid' "$STATE_FILE")
  sni=$(jq -r '.nodes.reality.reality_sni' "$STATE_FILE")
  pub=$(jq -r '.nodes.reality.public_key' "$STATE_FILE")
  sid=$(jq -r '.nodes.reality.short_id' "$STATE_FILE")
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: vless
    server: $(yaml_quote "$address")
    port: $port
    uuid: $(yaml_quote "$uuid")
    udp: true
    network: tcp
    tls: true
    servername: $(yaml_quote "$sni")
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    reality-opts:
      public-key: $(yaml_quote "$pub")
      short-id: $(yaml_quote "$sid")
EOF
}

write_mihomo_proxy_hy2() {
  local name address port password obfs sni insecure
  name=$(export_node_name hy2)
  address=$(jq -r '.nodes.hy2.address' "$STATE_FILE")
  port=$(jq -r '.nodes.hy2.port' "$STATE_FILE")
  password=$(jq -r '.nodes.hy2.password' "$STATE_FILE")
  obfs=$(jq -r '.nodes.hy2.obfs_password' "$STATE_FILE")
  sni=$(jq -r '.nodes.hy2.domain // .nodes.hy2.address' "$STATE_FILE")
  insecure=$(jq -r '.nodes.hy2.insecure // false' "$STATE_FILE")
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: hysteria2
    server: $(yaml_quote "$address")
    port: $port
    password: $(yaml_quote "$password")
    obfs: salamander
    obfs-password: $(yaml_quote "$obfs")
    sni: $(yaml_quote "$sni")
    skip-cert-verify: $insecure
    alpn:
      - h3
EOF
}

write_mihomo_proxy_tuic() {
  local name address port uuid password sni congestion insecure
  name=$(export_node_name tuic)
  address=$(jq -r '.nodes.tuic.address' "$STATE_FILE")
  port=$(jq -r '.nodes.tuic.port' "$STATE_FILE")
  uuid=$(jq -r '.nodes.tuic.uuid' "$STATE_FILE")
  password=$(jq -r '.nodes.tuic.password' "$STATE_FILE")
  sni=$(jq -r '.nodes.tuic.domain // .nodes.tuic.address' "$STATE_FILE")
  congestion=$(jq -r '.nodes.tuic.congestion_control // "bbr"' "$STATE_FILE")
  insecure=$(jq -r '.nodes.tuic.insecure // false' "$STATE_FILE")
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: tuic
    server: $(yaml_quote "$address")
    port: $port
    uuid: $(yaml_quote "$uuid")
    password: $(yaml_quote "$password")
    sni: $(yaml_quote "$sni")
    alpn:
      - h3
    udp-relay-mode: native
    congestion-controller: $congestion
    reduce-rtt: false
    skip-cert-verify: $insecure
EOF
}

write_mihomo_proxy_ws() {
  local name address port uuid domain path tls
  name=$(export_node_name ws)
  address=$(jq -r '.nodes.ws.address' "$STATE_FILE")
  port=$(jq -r '.nodes.ws.port' "$STATE_FILE")
  uuid=$(jq -r '.nodes.ws.uuid' "$STATE_FILE")
  domain=$(jq -r '.nodes.ws.domain // .nodes.ws.address' "$STATE_FILE")
  path=$(jq -r '.nodes.ws.path' "$STATE_FILE")
  tls=$(jq -r '.nodes.ws.tls_enabled // true' "$STATE_FILE")
  cat <<EOF
  - name: $(yaml_quote "$name")
    type: vless
    server: $(yaml_quote "$address")
    port: $port
    uuid: $(yaml_quote "$uuid")
    udp: true
    network: ws
    tls: $tls
EOF
  if [[ "$tls" == true ]]; then
    printf '    servername: %s\n' "$(yaml_quote "$domain")"
  fi
  cat <<EOF
    ws-opts:
      path: $(yaml_quote "$path")
      headers:
        Host: $(yaml_quote "$domain")
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

export_v2rayn_subscription() {
  ensure_client_export_dir
  local raw base64_file key uri
  raw="${CLIENT_EXPORT_DIR}/v2rayn-subscription.txt"
  base64_file="${CLIENT_EXPORT_DIR}/v2rayn-subscription-base64.txt"
  : > "$raw"

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    rebuild_node_uri "$key" || true
    uri=$(jq -r --arg k "$key" '.nodes[$k].uri // empty' "$STATE_FILE")
    [[ -n "$uri" ]] && printf '%s\n' "$uri" >> "$raw"
  done < <(managed_export_keys)

  [[ -s "$raw" ]] || { warn "没有分享链接可导出。"; rm -f "$raw"; return 1; }
  base64 -w 0 "$raw" > "$base64_file"
  printf '\n' >> "$base64_file"
  chmod 600 "$raw" "$base64_file"

  [[ ${CLIENT_EXPORT_QUIET:-false} == true ]] || {
    info "v2rayN 标准订阅内容：$raw"
    info "v2rayN Base64 兼容订阅：$base64_file"
  }
}

write_export_readme() {
  ensure_client_export_dir
  cat > "${CLIENT_EXPORT_DIR}/README.txt" <<EOF
sing-box-oneclick client exports
Generated: $(date -Is 2>/dev/null || date)

Files:
  sing-box-client.json          sing-box client, local mixed proxy 127.0.0.1:2080
  mihomo.yaml                   Mihomo / Clash.Meta-compatible client config
  v2rayn-subscription.txt       Standard VLESS / Hysteria2 / TUIC share-link subscription content
  v2rayn-subscription-base64.txt Legacy-compatible Base64 form

Security:
  These files contain UUIDs/passwords and are mode 600 under a mode 700 directory.
  The script DOES NOT publish them to a public HTTP endpoint automatically.
  Do not upload them to a public repository or an untrusted subscription converter.
EOF
  chmod 600 "${CLIENT_EXPORT_DIR}/README.txt"
}

generate_all_client_exports() {
  ensure_state
  if [[ $(jq -r '(.nodes // {}) | length' "$STATE_FILE") -eq 0 ]]; then
    warn "当前没有节点，无法生成客户端配置。"
    return 1
  fi

  export_singbox_client
  export_mihomo_client
  export_v2rayn_subscription
  write_export_readme
  touch "$CLIENT_EXPORT_MARKER"
  chmod 600 "$CLIENT_EXPORT_MARKER"
  [[ ${CLIENT_EXPORT_QUIET:-false} == true ]] || info "客户端配置已全部本地生成，并启用节点变更后的自动刷新。"
}

generate_all_client_exports_quiet() {
  local old_quiet=${CLIENT_EXPORT_QUIET:-false}
  CLIENT_EXPORT_QUIET=true
  generate_all_client_exports
  CLIENT_EXPORT_QUIET=$old_quiet
}

refresh_client_exports_if_present() {
  [[ -f "$CLIENT_EXPORT_MARKER" ]] || return 0
  generate_all_client_exports_quiet || {
    warn "节点已修改，但本地客户端导出自动刷新失败；请稍后运行 sb export 手工刷新。"
    return 0
  }
  return 0
}

show_client_export_status() {
  ensure_client_export_dir
  echo
  headmsg "本地客户端配置 / 订阅"
  echo -e "  ${C_DIM}目录：${CLIENT_EXPORT_DIR}${C_RESET}"
  echo

  local f
  for f in sing-box-client.json mihomo.yaml v2rayn-subscription.txt v2rayn-subscription-base64.txt README.txt; do
    if [[ -f "${CLIENT_EXPORT_DIR}/${f}" ]]; then
      printf '  %s %-36s %s\n' "$(ui_status_dot yes)" "$f" "$(stat -c '%y' "${CLIENT_EXPORT_DIR}/${f}" 2>/dev/null | cut -d. -f1)"
    else
      printf '  %s %-36s %s\n' "$(ui_status_dot no)" "$f" "未生成"
    fi
  done

  echo
  if [[ -f "$CLIENT_EXPORT_MARKER" ]]; then
    note "已启用自动刷新：通过本脚本新增/删除节点或原地修改参数后会尽量同步导出文件。"
  fi
  warn "这些文件包含节点凭据。脚本不会自动创建公网订阅 URL。"
}

client_export_menu() {
  ensure_state
  echo
  headmsg "本地客户端配置 / 订阅"
  note "所有转换都在本 VPS 完成，不调用第三方订阅转换服务。"
  warn "导出文件包含节点 UUID / 密码，请像私钥一样保护。"
  echo
  ui_item 1 "生成 / 刷新全部（sing-box + Mihomo + v2rayN）"
  ui_item 2 "仅生成 sing-box 客户端配置"
  ui_item 3 "仅生成 Mihomo 客户端配置"
  ui_item 4 "仅生成 v2rayN 订阅文件"
  ui_item 5 "查看导出状态 / 路径"
  echo -e "  ${C_CYAN} 0${C_RESET}  返回"
  read -r -p "  请选择操作 › " n

  case "$n" in
    1) generate_all_client_exports; show_client_export_status ;;
    2) export_singbox_client; write_export_readme; touch "$CLIENT_EXPORT_MARKER"; chmod 600 "$CLIENT_EXPORT_MARKER" ;;
    3) export_mihomo_client; write_export_readme; touch "$CLIENT_EXPORT_MARKER"; chmod 600 "$CLIENT_EXPORT_MARKER" ;;
    4) export_v2rayn_subscription; write_export_readme; touch "$CLIENT_EXPORT_MARKER"; chmod 600 "$CLIENT_EXPORT_MARKER" ;;
    5) show_client_export_status ;;
    0) return 0 ;;
    *) warn "无效选择。" ;;
  esac
}

# Extend state mutation hooks so existing exports stay synchronized after deploy/remove.
state_set_node() {
  local key=$1 json=$2 tmp
  ensure_state
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg key "$key" --argjson value "$json" '.nodes[$key]=$value' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  render_node_info
  refresh_client_exports_if_present || true
}

state_remove_node() {
  local key=$1 tmp
  ensure_state
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg key "$key" 'del(.nodes[$key])' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  render_node_info
  refresh_client_exports_if_present || true
}
