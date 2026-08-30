#!/usr/bin/env bash
# shellcheck shell=bash

# Certificate pinning safety layer.
# Loaded last so it can extend the final protocol/client/menu implementations.
#
# Goals:
# - Trusted CA certificates keep normal verification and never need insecure=true.
# - Self-signed / explicitly untrusted certificates use certificate pinning.
# - sing-box uses SPKI SHA256 (base64) via certificate_public_key_sha256.
# - Mihomo uses the leaf certificate SHA256 fingerprint.
# - v2rayN/Xray-compatible share links use pinSHA256 for HY2 and pcs for Trojan.
# - Cloudflare WS is special: clients validate the Cloudflare edge certificate;
#   an origin self-signed certificate affects Cloudflare Full vs Full (strict),
#   not the client-side certificate pin.

CERT_VERIFY_MODE="${CERT_VERIFY_MODE:-system}"
CERT_PIN_SPKI_SHA256="${CERT_PIN_SPKI_SHA256:-}"
CERT_PIN_CERT_SHA256="${CERT_PIN_CERT_SHA256:-}"
CERT_PIN_CERT_SHA256_COLON="${CERT_PIN_CERT_SHA256_COLON:-}"
CERT_PINNING_CONTEXT="${CERT_PINNING_CONTEXT:-}"
CLIENT_EXPORT_CERT_DIR="${CLIENT_EXPORT_CERT_DIR:-${CLIENT_EXPORT_DIR}/certs}"

certificate_spki_sha256_base64() {
  local cert=$1
  [[ -r "$cert" ]] || return 1
  openssl x509 -in "$cert" -pubkey -noout 2>/dev/null \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | openssl dgst -sha256 -binary 2>/dev/null \
    | openssl base64 -A 2>/dev/null
}

certificate_sha256_colon() {
  local cert=$1 fp
  [[ -r "$cert" ]] || return 1
  fp=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null | sed -E 's/^[^=]+=//')
  [[ "$fp" =~ ^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$ ]] || return 1
  printf '%s' "${fp^^}"
}

certificate_sha256_hex() {
  local fp
  fp=$(certificate_sha256_colon "$1") || return 1
  printf '%s' "$(tr -d ':' <<< "$fp" | tr 'A-F' 'a-f')"
}

cert_pinning_clear_selection() {
  CERT_VERIFY_MODE="system"
  CERT_PIN_SPKI_SHA256=""
  CERT_PIN_CERT_SHA256=""
  CERT_PIN_CERT_SHA256_COLON=""
  CERT_CLIENT_INSECURE=false
}

cert_pinning_load_selection_pin() {
  local cert=$1
  CERT_PIN_SPKI_SHA256=$(certificate_spki_sha256_base64 "$cert") || die "无法计算证书公钥 SHA256 Pin。"
  CERT_PIN_CERT_SHA256=$(certificate_sha256_hex "$cert") || die "无法计算证书 SHA256 指纹。"
  CERT_PIN_CERT_SHA256_COLON=$(certificate_sha256_colon "$cert") || die "无法计算证书 SHA256 指纹。"
  CERT_VERIFY_MODE="pin"
  CERT_CLIENT_INSECURE=false
}

cert_pinning_is_direct_tls_key() {
  case "$1" in
    hy2|tuic|anytls|trojan) return 0 ;;
    *) return 1 ;;
  esac
}

cert_pinning_state_update() {
  local key=$1 filter=$2
  shift 2
  local tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg k "$key" "$@" "$filter" "$STATE_FILE" > "$tmp" || return 1
  install -m 600 "$tmp" "$STATE_FILE"
}

cert_pinning_state_set_pin() {
  local key=$1 cert=$2 spki cert_hex cert_colon
  [[ -r "$cert" ]] || { warn "无法读取 $key 的证书文件，暂不能生成证书 Pin：$cert"; return 1; }
  spki=$(certificate_spki_sha256_base64 "$cert") || return 1
  cert_hex=$(certificate_sha256_hex "$cert") || return 1
  cert_colon=$(certificate_sha256_colon "$cert") || return 1

  cert_pinning_state_update "$key" '
    .nodes[$k].tls_verify_mode="pin"
    | .nodes[$k].insecure=false
    | .nodes[$k].certificate_public_key_sha256=$spki
    | .nodes[$k].certificate_sha256=$cert_hex
    | .nodes[$k].certificate_sha256_colon=$cert_colon
  ' --arg spki "$spki" --arg cert_hex "$cert_hex" --arg cert_colon "$cert_colon"
}

cert_pinning_state_set_system() {
  local key=$1 mode=${2:-system}
  cert_pinning_state_update "$key" '
    .nodes[$k].tls_verify_mode=$mode
    | .nodes[$k].insecure=false
    | del(.nodes[$k].certificate_public_key_sha256)
    | del(.nodes[$k].certificate_sha256)
    | del(.nodes[$k].certificate_sha256_colon)
  ' --arg mode "$mode"
}

cert_pinning_selection_to_node() {
  local key=$1 cert=${CERT_PATH:-}
  [[ -f "$STATE_FILE" ]] || return 0
  jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || return 0

  case "$key:$CERT_VERIFY_MODE" in
    ws:*)
      # The end user sees Cloudflare's edge cert. Origin trust is a Cloudflare setting.
      cert_pinning_state_set_system "$key" "cloudflare-edge"
      ;;
    *:pin)
      cert_pinning_state_set_pin "$key" "$cert" || return 1
      ;;
    *)
      cert_pinning_state_set_system "$key" "system"
      ;;
  esac
}

cert_pinning_migrate_node() {
  local key=$1 tls mode insecure cert
  [[ -f "$STATE_FILE" ]] || return 0
  jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || return 0

  tls=$(jq -r --arg k "$key" '.nodes[$k].tls_enabled // .nodes[$k].certificate // false' "$STATE_FILE")
  [[ "$tls" == true ]] || return 0
  mode=$(jq -r --arg k "$key" '.nodes[$k].certificate_mode // "legacy"' "$STATE_FILE")
  insecure=$(jq -r --arg k "$key" '.nodes[$k].insecure // false' "$STATE_FILE")
  cert=$(jq -r --arg k "$key" '.nodes[$k].certificate_path // empty' "$STATE_FILE")

  if [[ "$key" == ws ]]; then
    if [[ "$insecure" == true || $(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // empty' "$STATE_FILE") != cloudflare-edge ]]; then
      cert_pinning_state_set_system "$key" "cloudflare-edge" || true
    fi
    return 0
  fi

  cert_pinning_is_direct_tls_key "$key" || return 0
  if [[ "$mode" == self-signed || "$insecure" == true || $(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // empty' "$STATE_FILE") == pin ]]; then
    [[ -n "$cert" ]] && cert_pinning_state_set_pin "$key" "$cert" || true
  else
    cert_pinning_state_set_system "$key" "system" || true
  fi
}

cert_pinning_migrate_all() {
  ensure_state
  local key changed=0 before after
  for key in hy2 tuic anytls trojan ws; do
    jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || continue
    before=$(jq -c --arg k "$key" '.nodes[$k] | {tls_verify_mode,insecure,certificate_public_key_sha256,certificate_sha256}' "$STATE_FILE" 2>/dev/null || true)
    cert_pinning_migrate_node "$key"
    after=$(jq -c --arg k "$key" '.nodes[$k] | {tls_verify_mode,insecure,certificate_public_key_sha256,certificate_sha256}' "$STATE_FILE" 2>/dev/null || true)
    [[ "$before" == "$after" ]] || changed=1
  done
  if (( changed == 1 )); then
    for key in hy2 tuic anytls trojan ws; do
      jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || continue
      rebuild_node_uri "$key" >/dev/null 2>&1 || true
    done
    render_node_info >/dev/null 2>&1 || true
  fi
}

cert_pinning_legacy_count() {
  [[ -f "$STATE_FILE" ]] || { printf '0'; return 0; }
  jq '[.nodes // {} | to_entries[] | select(
      (.key=="hy2" or .key=="tuic" or .key=="anytls" or .key=="trojan")
      and ((.value.insecure // false)==true or ((.value.certificate_mode // "")=="self-signed" and (.value.tls_verify_mode // "")!="pin"))
    )] | length' "$STATE_FILE" 2>/dev/null || printf '0'
}

cert_pinning_legacy_notice() {
  local count
  count=$(cert_pinning_legacy_count)
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  (( count > 0 )) || return 0
  echo
  echo -e "  ${C_YELLOW}!${C_RESET} ${C_BOLD}检测到 ${count} 个旧版 TLS 节点仍使用“跳过证书验证”语义${C_RESET}"
  echo -e "    ${C_DIM}运行 sb export 会自动生成证书 Pin 并更新导出；客户端重新导入后不要手动开启跳过验证。${C_RESET}"
}

cert_pinning_uri_apply() {
  local key=$1 mode pin uri base frag sep param tmp
  mode=$(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // "system"' "$STATE_FILE" 2>/dev/null || echo system)
  [[ "$mode" == pin ]] || return 0
  pin=$(jq -r --arg k "$key" '.nodes[$k].certificate_sha256 // empty' "$STATE_FILE")
  [[ -n "$pin" ]] || return 0

  case "$key" in
    hy2) param="pinSHA256" ;;
    trojan) param="pcs" ;;
    *) return 0 ;;
  esac

  uri=$(jq -r --arg k "$key" '.nodes[$k].uri // empty' "$STATE_FILE")
  [[ -n "$uri" ]] || return 0
  if [[ "$uri" == *#* ]]; then
    base=${uri%%#*}
    frag=${uri#*#}
  else
    base=$uri
    frag=""
  fi
  # Remove legacy dangerous flags and any stale pin of the same type.
  base=$(sed -E \
    -e 's/([?&])(insecure|allowInsecure|allow_insecure)=(1|true)(&|$)/\1/g' \
    -e "s/([?&])${param}=[^&#]*(&|$)/\\1/g" \
    -e 's/\?&/?/g' -e 's/&&+/\&/g' -e 's/[?&]$//' <<< "$base")
  [[ "$base" == *\?* ]] && sep='&' || sep='?'
  base="${base}${sep}${param}=$(uri_encode "$pin")"
  [[ -n "$frag" ]] && uri="${base}#${frag}" || uri="$base"

  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg k "$key" --arg uri "$uri" '.nodes[$k].uri=$uri' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
}

cert_pinning_mihomo_filter() {
  local key=$1 content=$2 mode fp line inserted=0
  mode=$(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // "system"' "$STATE_FILE" 2>/dev/null || echo system)
  [[ "$mode" == pin ]] || { printf '%s\n' "$content"; return 0; }
  fp=$(jq -r --arg k "$key" '.nodes[$k].certificate_sha256_colon // empty' "$STATE_FILE")
  [[ -n "$fp" ]] || { printf '%s\n' "$content"; return 0; }

  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]+skip-cert-verify: ]]; then
      if (( inserted == 0 )); then
        printf '    fingerprint: %s\n' "$(yaml_quote "$fp")"
        inserted=1
      fi
      printf '    skip-cert-verify: false\n'
      continue
    fi
    printf '%s\n' "$line"
    if (( inserted == 0 )) && [[ "$line" =~ ^[[:space:]]+(sni|servername): ]]; then
      printf '    fingerprint: %s\n' "$(yaml_quote "$fp")"
      inserted=1
    fi
  done <<< "$content"
}

cert_pinning_export_certificates() {
  ensure_client_export_dir
  install -d -m 700 "$CLIENT_EXPORT_CERT_DIR"
  local key mode cert target
  for key in hy2 tuic anytls trojan; do
    jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || continue
    mode=$(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // "system"' "$STATE_FILE")
    [[ "$mode" == pin ]] || continue
    cert=$(jq -r --arg k "$key" '.nodes[$k].certificate_path // empty' "$STATE_FILE")
    [[ -r "$cert" ]] || continue
    target="${CLIENT_EXPORT_CERT_DIR}/${key}-server.crt"
    install -m 600 "$cert" "$target"
  done
}

cert_pinning_show_node_guidance() {
  local key=$1 mode cert_mode cert_file
  [[ -f "$STATE_FILE" ]] || return 0
  jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || return 0
  mode=$(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // "system"' "$STATE_FILE")
  cert_mode=$(jq -r --arg k "$key" '.nodes[$k].certificate_mode // "-"' "$STATE_FILE")

  echo
  headmsg "客户端证书验证"
  case "$mode" in
    pin)
      info "已启用证书固定（Pin）。不要在客户端手动开启“跳过证书验证”。"
      note "sing-box >= 1.13：导出会写入 certificate_public_key_sha256，insecure=false。"
      note "Mihomo：导出会写入 certificate fingerprint，skip-cert-verify=false。"
      case "$key" in
        hy2)
          note "v2rayN：分享链接会写入 pinSHA256；“允许不安全/跳过验证”保持关闭。"
          warn "若当前 v2rayN 版本导入 Pin 后仍无法连接，不要改成跳过验证；请使用导出的 certs/hy2-server.crt，或直接使用 sing-box/Mihomo 配置。"
          ;;
        trojan)
          note "v2rayN/Xray：分享链接会写入 pcs（pinnedPeerCertSha256）；不要开启 allowInsecure。"
          ;;
        tuic|anytls)
          warn "v2rayN 对该协议的 Pin 传递受版本/内核影响较大；不要靠“跳过验证”兜底。优先使用本脚本生成的 sing-box/Mihomo 配置，或改用受信任证书。"
          ;;
      esac
      cert_file="${CLIENT_EXPORT_CERT_DIR}/${key}-server.crt"
      note "运行 sb export 后会同时保存公开服务器证书：$cert_file"
      ;;
    cloudflare-edge)
      info "客户端连接 Cloudflare 边缘证书：客户端“跳过证书验证”应保持关闭。"
      if [[ "$cert_mode" == self-signed ]]; then
        warn "源站是自签证书：Cloudflare SSL/TLS 应使用 Full，而不是 Full (strict)。客户端 Pin 不能替代 Cloudflare 对源站证书的验证。"
      else
        note "源站为受信任证书时，Cloudflare 建议 Full (strict)。"
      fi
      ;;
    *)
      info "当前使用受信任证书 / 系统 CA 验证：客户端“跳过证书验证”应保持关闭。"
      ;;
  esac
}

cert_pinning_show_all_guidance() {
  local key
  for key in hy2 tuic anytls trojan ws; do
    jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || continue
    cert_pinning_show_node_guidance "$key"
  done
}

# Preserve final implementations after all previous modules (including menu.sh).
for _fn in ensure_self_signed_certificate ensure_acme_domain_certificate select_certificate_mode \
  rebuild_node_uri singbox_outbound_for_key \
  write_mihomo_proxy_hy2 write_mihomo_proxy_tuic write_mihomo_proxy_anytls write_mihomo_proxy_trojan \
  deploy_hysteria2 deploy_tuic deploy_anytls deploy_trojan deploy_cloudflare_ws \
  switch_certificate_tls export_singbox_client export_mihomo_client export_v2rayn_subscription \
  write_export_readme show_client_export_status certificate_status ui_dashboard novice_guide; do
  if declare -F "$_fn" >/dev/null 2>&1; then
    eval "$(declare -f "$_fn" | sed "1s/${_fn}/${_fn}_pre_pinning/")"
  fi
done
unset _fn

ensure_self_signed_certificate() {
  local server_name=$1 cert before="" after=""
  cert="${SELF_CERT_ROOT}/$(managed_cert_dir_name "$server_name")/cert.pem"
  [[ -r "$cert" ]] && before=$(certificate_sha256_hex "$cert" 2>/dev/null || true)
  ensure_self_signed_certificate_pre_pinning "$@"

  if [[ "$CERT_PINNING_CONTEXT" == ws ]]; then
    CERT_VERIFY_MODE="cloudflare-edge"
    CERT_PIN_SPKI_SHA256=""
    CERT_PIN_CERT_SHA256=""
    CERT_PIN_CERT_SHA256_COLON=""
    # Preserve the existing Cloudflare origin warning inside deploy_cloudflare_ws.
    CERT_CLIENT_INSECURE=true
  else
    cert_pinning_load_selection_pin "$CERT_PATH"
    info "自签证书已启用证书固定；sing-box/Mihomo 导出无需开启跳过证书验证。"
  fi

  after=$(certificate_sha256_hex "$CERT_PATH" 2>/dev/null || true)
  if [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
    warn "自签证书已更换，证书 Pin 也随之变化；旧客户端需要重新导入配置。"
  fi
}

ensure_acme_domain_certificate() {
  ensure_acme_domain_certificate_pre_pinning "$@"
  cert_pinning_clear_selection
}

ensure_custom_certificate() {
  local server_name=$1 source_cert source_key dir ans
  read -r -p "现有证书链 PEM 路径: " source_cert
  read -r -p "现有私钥 PEM 路径: " source_key
  validate_certificate_pair "$source_cert" "$source_key"

  dir="${CUSTOM_CERT_ROOT}/$(managed_cert_dir_name "$server_name")"
  install -d -m 700 "$dir"
  install -m 0644 "$source_cert" "${dir}/cert.pem"
  install -m 0600 "$source_key" "${dir}/key.pem"

  CERT_PATH="${dir}/cert.pem"
  KEY_PATH="${dir}/key.pem"
  CERT_MODE="custom"
  TLS_ENABLED=true

  read -r -p "该证书是否由客户端系统信任且名称匹配 ${server_name}？[Y/n]: " ans
  if [[ -z "$ans" || ${ans,,} == y || ${ans,,} == yes ]]; then
    cert_pinning_clear_selection
    note "将使用系统 CA 正常验证；客户端不要开启“跳过证书验证”。"
  elif [[ "$CERT_PINNING_CONTEXT" == ws ]]; then
    CERT_VERIFY_MODE="cloudflare-edge"
    CERT_CLIENT_INSECURE=true
    CERT_PIN_SPKI_SHA256=""
    CERT_PIN_CERT_SHA256=""
    CERT_PIN_CERT_SHA256_COLON=""
    warn "该证书不受公网客户端信任。Cloudflare 源站可使用 Full；客户端仍应关闭跳过证书验证。"
  else
    cert_pinning_load_selection_pin "$CERT_PATH"
    info "该证书将使用证书固定验证；客户端不需要、也不建议开启“跳过证书验证”。"
  fi
}

select_certificate_mode() {
  local server_name=$1 allow_off=${2:-false} choice default_choice
  CERT_MODE=""
  TLS_ENABLED=true
  CERT_PATH=""
  KEY_PATH=""
  cert_pinning_clear_selection

  if is_hostname "$server_name"; then default_choice=1; else default_choice=2; fi

  while true; do
    echo
    headmsg "===== TLS / 证书模式 ====="
    echo "1. ACME 域名证书（Let's Encrypt，域名推荐）"
    if [[ "$CERT_PINNING_CONTEXT" == ws ]]; then
      echo "2. 自签源站证书（无公网 CA；Cloudflare 使用 Full）"
    else
      echo "2. 自签证书（IP 推荐；自动启用证书 Pin，不需要跳过验证）"
    fi
    echo "3. 导入现有 PEM 证书 + 私钥"
    if [[ "$allow_off" == true ]]; then
      echo "4. 关闭 TLS（仅 VLESS WebSocket 支持）"
    fi
    read -r -p "请选择 [${default_choice}]: " choice
    choice=${choice:-$default_choice}

    case "$choice" in
      1)
        if ! is_hostname "$server_name"; then
          warn "Let's Encrypt 公网证书需要域名。当前 TLS 名称是 IP：$server_name"
          note "小白直接选择 2，自签证书会自动配好证书 Pin。"
          continue
        fi
        ensure_acme_domain_certificate "$server_name"
        return 0
        ;;
      2)
        ensure_self_signed_certificate "$server_name"
        return 0
        ;;
      3)
        ensure_custom_certificate "$server_name"
        return 0
        ;;
      4)
        if [[ "$allow_off" == true ]]; then
          CERT_MODE="off"
          TLS_ENABLED=false
          CERT_PATH=""
          KEY_PATH=""
          cert_pinning_clear_selection
          return 0
        fi
        ;;
    esac
    warn "无效选择。"
  done
}

# Correct the beginner hint now that IP defaults really do choose self-signed + pin.
novice_tls_hint() {
  local server_name=$1
  echo
  headmsg "小白提示 · TLS 证书"
  if is_hostname "$server_name"; then
    note "当前证书名称是域名 ${server_name}：下一步直接按 Enter，会默认选择 Let's Encrypt（推荐）。"
    note "使用受信任证书时，客户端“跳过证书验证”保持关闭。"
  else
    note "当前证书名称是 IP ${server_name}：下一步直接按 Enter，会默认生成自签证书。"
    note "脚本会自动生成证书 Pin；sing-box/Mihomo 导出不需要开启“跳过证书验证”。"
  fi
  note "“导入已有 PEM”属于高级选项，不确定就不要选。"
}

novice_guide() {
  # Keep the existing guide, but replace the legacy self-signed wording.
  novice_guide_pre_pinning "$@" \
    | sed 's/没有域名也能用，但客户端必须允许跳过证书验证/没有域名也能用；脚本会自动生成证书 Pin，导出配置不要开启跳过验证/'
  echo
  headmsg "自签证书的新规则"
  note "sing-box / Mihomo：脚本会自动写入证书 Pin，“跳过证书验证”保持关闭。"
  note "v2rayN：能写入 Pin 的分享链接会自动携带 Pin；不要手动勾选 allowInsecure / 跳过证书验证。"
  warn "如果某个客户端版本不支持 Pin，不要用“跳过验证”硬凑；改用受信任证书，或使用本脚本生成的兼容配置。"
}

rebuild_node_uri() {
  rebuild_node_uri_pre_pinning "$@"
  cert_pinning_uri_apply "$1"
}

singbox_outbound_for_key() {
  local key=$1 base mode pin
  base=$(singbox_outbound_for_key_pre_pinning "$@") || return
  mode=$(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // "system"' "$STATE_FILE" 2>/dev/null || echo system)
  if [[ "$mode" == pin ]] && jq -e '.tls.enabled == true' <<< "$base" >/dev/null 2>&1; then
    pin=$(jq -r --arg k "$key" '.nodes[$k].certificate_public_key_sha256 // empty' "$STATE_FILE")
    if [[ -n "$pin" ]]; then
      jq --arg pin "$pin" '.tls.insecure=false | .tls.certificate_public_key_sha256=[$pin]' <<< "$base"
      return
    fi
  fi
  printf '%s\n' "$base"
}

write_mihomo_proxy_hy2() {
  cert_pinning_mihomo_filter hy2 "$(write_mihomo_proxy_hy2_pre_pinning "$@")"
}

write_mihomo_proxy_tuic() {
  cert_pinning_mihomo_filter tuic "$(write_mihomo_proxy_tuic_pre_pinning "$@")"
}

write_mihomo_proxy_anytls() {
  cert_pinning_mihomo_filter anytls "$(write_mihomo_proxy_anytls_pre_pinning "$@")"
}

write_mihomo_proxy_trojan() {
  cert_pinning_mihomo_filter trojan "$(write_mihomo_proxy_trojan_pre_pinning "$@")"
}

cert_pinning_post_deploy() {
  local key=$1
  cert_pinning_selection_to_node "$key" || true
  rebuild_node_uri "$key" || true
  render_node_info || true
  if declare -F refresh_client_exports_if_present >/dev/null 2>&1; then
    refresh_client_exports_if_present || true
  fi
  cert_pinning_show_node_guidance "$key"
}

deploy_hysteria2() {
  CERT_PINNING_CONTEXT=hy2
  deploy_hysteria2_pre_pinning "$@"
  cert_pinning_post_deploy hy2
  CERT_PINNING_CONTEXT=""
}

deploy_tuic() {
  CERT_PINNING_CONTEXT=tuic
  deploy_tuic_pre_pinning "$@"
  cert_pinning_post_deploy tuic
  CERT_PINNING_CONTEXT=""
}

deploy_anytls() {
  CERT_PINNING_CONTEXT=anytls
  deploy_anytls_pre_pinning "$@"
  cert_pinning_post_deploy anytls
  CERT_PINNING_CONTEXT=""
}

deploy_trojan() {
  CERT_PINNING_CONTEXT=trojan
  deploy_trojan_pre_pinning "$@"
  cert_pinning_post_deploy trojan
  CERT_PINNING_CONTEXT=""
}

deploy_cloudflare_ws() {
  CERT_PINNING_CONTEXT=ws
  deploy_cloudflare_ws_pre_pinning "$@"
  cert_pinning_post_deploy ws
  CERT_PINNING_CONTEXT=""
}

switch_certificate_tls() {
  local before_path=${CERT_PATH:-}
  switch_certificate_tls_pre_pinning "$@"
  local key
  # The selected node now references CERT_PATH. Use it to identify the changed node.
  if [[ -n ${CERT_PATH:-} ]]; then
    key=$(jq -r --arg p "$CERT_PATH" '.nodes | to_entries[] | select(.value.certificate_path==$p) | .key' "$STATE_FILE" 2>/dev/null | head -n1)
  else
    key=$(jq -r '.nodes | to_entries[] | select((.value.tls_enabled // true)==false) | .key' "$STATE_FILE" 2>/dev/null | head -n1)
  fi
  [[ -n "$key" ]] || { [[ -n "$before_path" ]] && key=$(jq -r --arg p "$before_path" '.nodes | to_entries[] | select(.value.certificate_path==$p) | .key' "$STATE_FILE" 2>/dev/null | head -n1); }
  if [[ -n "$key" ]]; then
    cert_pinning_selection_to_node "$key" || true
    rebuild_node_uri "$key" || true
    render_node_info || true
    refresh_client_exports_if_present || true
    cert_pinning_show_node_guidance "$key"
  fi
}

export_singbox_client() {
  cert_pinning_migrate_all
  export_singbox_client_pre_pinning "$@"
}

export_mihomo_client() {
  cert_pinning_migrate_all
  export_mihomo_client_pre_pinning "$@"
}

export_v2rayn_subscription() {
  cert_pinning_migrate_all
  export_v2rayn_subscription_pre_pinning "$@"
}

write_export_readme() {
  cert_pinning_migrate_all
  cert_pinning_export_certificates
  write_export_readme_pre_pinning "$@"
  {
    echo
    echo "TLS certificate verification:"
    echo "  IMPORTANT: Do NOT manually enable 'skip certificate verification' for configs generated here."
    echo "  Trusted certificates use normal system CA verification."
    echo "  Self-signed/untrusted certificates use certificate pinning when the target client supports it."
    echo "  sing-box client requires >= 1.13 for certificate_public_key_sha256."
    echo
    local key mode cert_hex spki cert_file
    for key in hy2 tuic anytls trojan ws; do
      jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || continue
      mode=$(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // "system"' "$STATE_FILE")
      echo "  [$key] verify_mode=$mode"
      if [[ "$mode" == pin ]]; then
        cert_hex=$(jq -r --arg k "$key" '.nodes[$k].certificate_sha256 // empty' "$STATE_FILE")
        spki=$(jq -r --arg k "$key" '.nodes[$k].certificate_public_key_sha256 // empty' "$STATE_FILE")
        cert_file="${CLIENT_EXPORT_CERT_DIR}/${key}-server.crt"
        echo "    certificate_sha256=$cert_hex"
        echo "    spki_sha256_base64=$spki"
        echo "    public_certificate=$cert_file"
        case "$key" in
          hy2) echo "    v2rayN: pinSHA256 is included in the URI; keep allowInsecure/skip verification OFF." ;;
          trojan) echo "    v2rayN/Xray: pcs is included in the URI; keep allowInsecure OFF." ;;
          tuic|anytls) echo "    v2rayN compatibility varies by version/core; prefer sing-box/Mihomo export or a trusted certificate." ;;
        esac
      elif [[ "$mode" == cloudflare-edge ]]; then
        echo "    client verifies Cloudflare edge certificate; keep skip verification OFF."
      else
        echo "    normal CA verification; keep skip verification OFF."
      fi
    done
    echo
    echo "Native Hysteria2 note: its own client may use insecure:true together with pinSHA256 by design."
    echo "That rule is specific to the native Hysteria2 client; do not copy it into sing-box/Mihomo/v2rayN settings."
  } >> "${CLIENT_EXPORT_DIR}/README.txt"
  chmod 600 "${CLIENT_EXPORT_DIR}/README.txt"
}

show_client_export_status() {
  show_client_export_status_pre_pinning "$@"
  if [[ -d "$CLIENT_EXPORT_CERT_DIR" ]]; then
    note "自签/Pin 节点的公开服务器证书副本：$CLIENT_EXPORT_CERT_DIR"
  fi
  note "导出配置的默认安全规则：客户端不要手动开启“跳过证书验证”。"
}

certificate_status() {
  certificate_status_pre_pinning "$@"
  echo
  headmsg "客户端证书验证策略"
  local key name mode
  for key in hy2 tuic anytls trojan ws; do
    jq -e --arg k "$key" '.nodes[$k] != null' "$STATE_FILE" >/dev/null 2>&1 || continue
    name=$(jq -r --arg k "$key" '.nodes[$k].name // $k' "$STATE_FILE")
    mode=$(jq -r --arg k "$key" '.nodes[$k].tls_verify_mode // "legacy"' "$STATE_FILE")
    case "$mode" in
      pin) ui_kv "$name" "证书 Pin · 不开启跳过验证" ;;
      cloudflare-edge) ui_kv "$name" "Cloudflare 边缘 CA 验证 · 不开启跳过验证" ;;
      system) ui_kv "$name" "系统 CA 验证 · 不开启跳过验证" ;;
      *) ui_kv "$name" "旧配置 · 建议运行 sb export 迁移" ;;
    esac
  done
}

ui_dashboard() {
  ui_dashboard_pre_pinning "$@"
  cert_pinning_legacy_notice
}
