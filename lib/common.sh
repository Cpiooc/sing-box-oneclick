#!/usr/bin/env bash
# shellcheck shell=bash

info() { echo -e "${C_GREEN}[+]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[x]${C_RESET} $*" >&2; }
headmsg() { echo -e "${C_BLUE}$*${C_RESET}"; }
note() { echo -e "${C_CYAN}[*]${C_RESET} $*"; }
die() { err "$*"; exit 1; }

cleanup_files=()
cleanup() {
  local f
  for f in "${cleanup_files[@]:-}"; do
    [[ -n "$f" ]] && rm -f -- "$f" 2>/dev/null || true
  done
}
trap cleanup EXIT

on_error() {
  local rc=$?
  err "脚本在第 ${BASH_LINENO[0]:-${LINENO}} 行发生错误（退出码 ${rc}）。"
  exit "$rc"
}
trap on_error ERR

pause() {
  echo
  read -r -p "按 Enter 返回菜单..." _ || true
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 运行此脚本。"
}

load_os() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "当前版本仅支持 Debian / Ubuntu。检测到：${PRETTY_NAME:-unknown}" ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

ensure_dirs() {
  install -d -m 700 "$APP_DIR" "$BACKUP_DIR"
  install -d -m 755 "$CONFIG_DIR"
}

ensure_state() {
  ensure_dirs
  if [[ ! -f "$STATE_FILE" ]]; then
    printf '%s\n' '{"version":1,"nodes":{}}' > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
  elif ! jq -e '.version and (.nodes | type == "object")' "$STATE_FILE" >/dev/null 2>&1; then
    die "状态文件损坏：$STATE_FILE"
  fi
}

install_deps() {
  info "安装/检查基础依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl ca-certificates openssl jq dnsutils iproute2 procps util-linux qrencode python3
}

download_checked_script() {
  local url=$1 dst=$2
  curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$dst"
  bash -n "$dst" || die "下载的脚本语法检查失败：$url"
}

install_singbox_core() {
  install_deps

  local tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")

  info "下载 sing-box 官方安装脚本..."
  download_checked_script "https://sing-box.app/install.sh" "$tmp"
  bash "$tmp"

  have sing-box || die "sing-box 安装失败。"
  systemctl daemon-reload
  info "sing-box：$(sing-box version 2>/dev/null | head -n1 || true)"
}

install_singbox() {
  if have sing-box; then
    info "sing-box 已安装：$(sing-box version 2>/dev/null | head -n1 || true)"
    read -r -p "是否通过官方安装脚本更新/修复？[y/N]: " ans
    if [[ ${ans,,} == "y" || ${ans,,} == "yes" ]]; then
      safe_update_singbox
    fi
  else
    install_singbox_core
  fi
}

ensure_singbox() {
  if ! have sing-box; then
    warn "尚未安装 sing-box，将先安装。"
    install_singbox_core
  fi
}

is_ipv4() {
  [[ ${1:-} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=.
  local -a octets
  read -r -a octets <<< "$1"
  local x
  for x in "${octets[@]}"; do
    (( 10#$x >= 0 && 10#$x <= 255 )) || return 1
  done
}

is_ipv6() {
  [[ ${1:-} == *:* ]] || return 1
  have python3 || return 0
  python3 - "$1" <<'PY' >/dev/null 2>&1
import ipaddress, sys
ipaddress.IPv6Address(sys.argv[1])
PY
}

is_hostname() {
  local h=${1:-}
  [[ ${#h} -le 253 ]] || return 1
  [[ $h =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

validate_port() {
  [[ ${1:-} =~ ^[0-9]+$ ]] || return 1
  (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

uri_encode() {
  jq -rn --arg v "$1" '$v|@uri'
}

uri_host() {
  if is_ipv6 "$1"; then
    printf '[%s]' "$1"
  else
    printf '%s' "$1"
  fi
}

random_hex() {
  local bytes=${1:-16}
  openssl rand -hex "$bytes"
}

public_ipv4() {
  curl -4 -fsS --max-time 6 https://api.ipify.org 2>/dev/null || true
}

public_ipv6() {
  curl -6 -fsS --max-time 6 https://api64.ipify.org 2>/dev/null || true
}

show_ip_info() {
  local v4 v6
  v4=$(public_ipv4)
  v6=$(public_ipv6)
  echo "公网 IPv4: ${v4:-未检测到}"
  echo "公网 IPv6: ${v6:-未检测到}"
}

domain_records() {
  local host=$1
  DOMAIN_A=$(dig +short A "$host" 2>/dev/null | grep -E '^[0-9.]+$' | sort -u || true)
  DOMAIN_AAAA=$(dig +short AAAA "$host" 2>/dev/null | grep ':' | sort -u || true)
}

check_domain() {
  local host=$1 mode=${2:-direct}
  if is_ipv4 "$host" || is_ipv6 "$host"; then
    [[ "$mode" == "direct" ]] || die "该模式要求使用域名，不能使用 IP。"
    info "节点地址使用 IP：$host"
    return 0
  fi

  is_hostname "$host" || die "不是有效域名：$host"
  domain_records "$host"

  local v4 v6 matched=0
  v4=$(public_ipv4)
  v6=$(public_ipv6)

  echo
  headmsg "===== DNS / Cloudflare 检查 ====="
  echo "域名      : $host"
  echo "VPS IPv4  : ${v4:-无}"
  echo "VPS IPv6  : ${v6:-无}"
  echo "DNS A     : ${DOMAIN_A:-无}"
  echo "DNS AAAA  : ${DOMAIN_AAAA:-无}"

  [[ -n "$DOMAIN_A" || -n "$DOMAIN_AAAA" ]] || die "域名没有可用的 A/AAAA 记录。"

  if [[ -n "$v4" ]] && grep -Fxq "$v4" <<< "$DOMAIN_A"; then matched=1; fi
  if [[ -n "$v6" ]] && grep -Fxq "$v6" <<< "$DOMAIN_AAAA"; then matched=1; fi

  case "$mode" in
    direct)
      if (( matched == 1 )); then
        info "域名直接指向本 VPS，适合 Reality / Hysteria2。"
      else
        warn "域名没有直接解析到本 VPS。若使用 Cloudflare，这通常表示已开启橙云/CDN。"
        warn "Reality 和普通 Hysteria2 不应走 Cloudflare 普通橙云代理；请使用 DNS only（灰云），除非你明确使用 Spectrum。"
        read -r -p "仍要继续？[y/N]: " ans
        [[ ${ans,,} == "y" || ${ans,,} == "yes" ]] || die "已取消，请先修正 DNS/Cloudflare 状态。"
      fi
      ;;
    cloudflare)
      if (( matched == 1 )); then
        warn "当前域名直接指向 VPS，看起来像灰云。VLESS WS+TLS 可用，但若想走 Cloudflare CDN，请在 Cloudflare 开启 Proxied（橙云）。"
      else
        info "域名没有直接暴露 VPS IP，符合 Cloudflare 橙云/反代模式的常见表现。"
      fi
      ;;
    *)
      die "未知域名检查模式：$mode"
      ;;
  esac
}

sync_time() {
  if have timedatectl; then
    timedatectl set-ntp true >/dev/null 2>&1 || true
    local synced
    synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)
    info "系统时间同步状态：${synced}"
  fi
}

current_tag_port() {
  local tag=$1
  [[ -f "$CONFIG_FILE" ]] || return 0
  jq -r --arg tag "$tag" '.inbounds[]? | select(.tag==$tag) | .listen_port // empty' "$CONFIG_FILE" 2>/dev/null | head -n1
}

port_in_use_by_other() {
  local proto=$1 port=$2 tag=${3:-}
  local old_port=""
  old_port=$(current_tag_port "$tag")
  if [[ "$old_port" == "$port" ]]; then
    return 1
  fi

  case "$proto" in
    tcp) ss -H -lnt "sport = :$port" 2>/dev/null | grep -q . ;;
    udp) ss -H -lnu "sport = :$port" 2>/dev/null | grep -q . ;;
    *) die "未知协议：$proto" ;;
  esac
}

show_port_owner() {
  local proto=$1 port=$2
  case "$proto" in
    tcp) ss -lntp "sport = :$port" 2>/dev/null || true ;;
    udp) ss -lnup "sport = :$port" 2>/dev/null || true ;;
  esac
}

check_reality_target() {
  local host=$1 tmp
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  info "检查 Reality 握手目标 ${host}:443 ..."
  if ! timeout 10 openssl s_client -connect "${host}:443" -servername "$host" -tls1_3 -brief </dev/null >"$tmp" 2>&1; then
    warn "无法确认 ${host}:443 的 TLS 1.3 握手。目标可能不合适，或 VPS 到该站点网络异常。"
    sed -n '1,12p' "$tmp" || true
    read -r -p "仍要继续？[y/N]: " ans
    [[ ${ans,,} == "y" || ${ans,,} == "yes" ]] || die "已取消，请更换 Reality SNI。"
  else
    info "Reality 握手目标 TLS 1.3 正常。"
  fi
}

base_config() {
  jq -n '{
    log:{level:"warn",timestamp:true},
    inbounds:[],
    outbounds:[{type:"direct",tag:"direct"}]
  }'
}

make_candidate_with_inbound() {
  local tag=$1 inbound_json=$2 candidate=$3
  ensure_dirs

  local source
  if [[ -f "$CONFIG_FILE" ]]; then
    jq empty "$CONFIG_FILE" || die "现有 sing-box 配置不是有效 JSON：$CONFIG_FILE"
    source=$CONFIG_FILE
  else
    source=$(mktemp)
    cleanup_files+=("$source")
    base_config > "$source"
  fi

  jq --arg tag "$tag" --argjson inbound "$inbound_json" '
    .inbounds = (((.inbounds // []) | map(select(.tag != $tag))) + [$inbound])
    | .outbounds = (.outbounds // [])
    | if ((.outbounds | map(.tag // "") | index("direct")) != null)
      then .
      else .outbounds += [{"type":"direct","tag":"direct"}]
      end
  ' "$source" > "$candidate"
}

make_candidate_without_inbound() {
  local tag=$1 candidate=$2
  [[ -f "$CONFIG_FILE" ]] || die "没有 sing-box 配置。"
  jq --arg tag "$tag" '
    .inbounds = ((.inbounds // []) | map(select(.tag != $tag)))
  ' "$CONFIG_FILE" > "$candidate"
}

backup_all() {
  ensure_state
  local stamp dir
  stamp=$(date +%Y%m%d-%H%M%S)
  dir="${BACKUP_DIR}/${stamp}"
  install -d -m 700 "$dir"
  [[ -f "$CONFIG_FILE" ]] && cp -a "$CONFIG_FILE" "$dir/config.json"
  [[ -f "$STATE_FILE" ]] && cp -a "$STATE_FILE" "$dir/state.json"
  [[ -f "$NODE_INFO" ]] && cp -a "$NODE_INFO" "$dir/node-info.txt"
  LAST_BACKUP_DIR="$dir"
  info "已创建备份：$dir"
}

rollback_from_last_backup() {
  local dir=${LAST_BACKUP_DIR:-}
  [[ -n "$dir" && -d "$dir" ]] || return 1

  warn "正在自动回滚到部署前配置..."
  if [[ -f "$dir/config.json" ]]; then
    cp -a "$dir/config.json" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    systemctl restart sing-box 2>/dev/null || true
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
  if ! systemctl restart sing-box; then
    rollback_from_last_backup || true
    die "${label} 启动失败，已尝试自动回滚。"
  fi

  sleep 1
  if ! systemctl is-active --quiet sing-box; then
    journalctl -u sing-box --no-pager -n 80 || true
    rollback_from_last_backup || true
    die "${label} 启动后未保持 active，已尝试自动回滚。"
  fi

  info "${label} 已应用，sing-box 运行正常。"
}

state_set_node() {
  local key=$1 json=$2 tmp
  ensure_state
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg key "$key" --argjson value "$json" '.nodes[$key]=$value' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  render_node_info
}

state_remove_node() {
  local key=$1 tmp
  ensure_state
  tmp=$(mktemp)
  cleanup_files+=("$tmp")
  jq --arg key "$key" 'del(.nodes[$key])' "$STATE_FILE" > "$tmp"
  install -m 600 "$tmp" "$STATE_FILE"
  render_node_info
}

render_node_info() {
  ensure_state
  {
    echo "=============================================="
    echo "sing-box-oneclick 节点信息"
    echo "生成时间: $(date -Is 2>/dev/null || date)"
    echo "=============================================="
    echo
    jq -r '
      .nodes | to_entries[] |
      "【\(.value.name // .key)】\n" +
      "类型: \(.value.type // .key)\n" +
      (if .value.address then "地址: \(.value.address)\n" else "" end) +
      (if .value.port then "端口: \(.value.port)\n" else "" end) +
      (if .value.domain then "域名/SNI: \(.value.domain)\n" else "" end) +
      (if .value.reality_sni then "Reality SNI: \(.value.reality_sni)\n" else "" end) +
      (if .value.uuid then "UUID: \(.value.uuid)\n" else "" end) +
      (if .value.password then "密码: \(.value.password)\n" else "" end) +
      (if .value.obfs_password then "Obfs 密码: \(.value.obfs_password)\n" else "" end) +
      (if .value.public_key then "Reality Public Key: \(.value.public_key)\n" else "" end) +
      (if .value.short_id then "Short ID: \(.value.short_id)\n" else "" end) +
      (if .value.path then "Path: \(.value.path)\n" else "" end) +
      "\n分享链接:\n\(.value.uri // "无")\n\n----------------------------------------------\n"
    ' "$STATE_FILE"
  } > "$NODE_INFO"
  chmod 600 "$NODE_INFO"
}

show_nodes() {
  ensure_state
  render_node_info
  if [[ $(jq '.nodes | length' "$STATE_FILE") -eq 0 ]]; then
    warn "尚未创建脚本管理的节点。"
    return 0
  fi
  cat "$NODE_INFO"
}

show_qr_codes() {
  ensure_state
  have qrencode || apt-get install -y qrencode
  local keys key uri name
  mapfile -t keys < <(jq -r '.nodes | keys[]' "$STATE_FILE")
  if (( ${#keys[@]} == 0 )); then
    warn "没有节点。"
    return 0
  fi

  for key in "${keys[@]}"; do
    uri=$(jq -r --arg key "$key" '.nodes[$key].uri // empty' "$STATE_FILE")
    name=$(jq -r --arg key "$key" '.nodes[$key].name // $key' "$STATE_FILE")
    [[ -n "$uri" ]] || continue
    echo
    headmsg "===== ${name} ====="
    qrencode -t ANSIUTF8 "$uri" || true
    echo "$uri"
  done
}
