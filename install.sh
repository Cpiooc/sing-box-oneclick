#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_VERSION="0.2.0"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
BACKUP_DIR="${CONFIG_DIR}/backup"
NODE_INFO="/root/sing-box-node-info.txt"
BBR_SYSCTL="/etc/sysctl.d/99-sing-box-bbr.conf"

C_RESET='\033[0m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'

info() { echo -e "${C_GREEN}[+]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[x]${C_RESET} $*" >&2; }
headmsg() { echo -e "${C_BLUE}$*${C_RESET}"; }

die() { err "$*"; exit 1; }

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
    *) die "当前版本仅支持 Debian / Ubuntu。检测到: ${PRETTY_NAME:-unknown}" ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

install_deps() {
  info "安装/检查基础依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl ca-certificates openssl jq dnsutils iproute2 procps util-linux
}

install_singbox() {
  install_deps
  if have sing-box; then
    info "sing-box 已安装：$(sing-box version 2>/dev/null | head -n1 || true)"
    read -r -p "是否执行官方安装脚本进行更新/修复？[y/N]: " ans
    if [[ ${ans,,} == "y" || ${ans,,} == "yes" ]]; then
      curl -fsSL https://sing-box.app/install.sh | sh
    fi
  else
    info "通过 sing-box 官方安装脚本安装..."
    curl -fsSL https://sing-box.app/install.sh | sh
  fi
  have sing-box || die "sing-box 安装失败。"
  systemctl daemon-reload
  info "完成：$(sing-box version 2>/dev/null | head -n1 || true)"
}

ensure_singbox() {
  if ! have sing-box; then
    warn "尚未安装 sing-box。"
    install_singbox
  fi
}

is_ipv4() {
  [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=.
  local -a octets
  read -r -a octets <<< "$1"
  local x
  for x in "${octets[@]}"; do
    (( x >= 0 && x <= 255 )) || return 1
  done
}

is_ipv6() {
  [[ $1 == *:* ]] || return 1
  [[ $1 =~ ^[0-9A-Fa-f:]+$ ]]
}

is_hostname() {
  [[ ${#1} -le 253 ]] || return 1
  [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

validate_port() {
  [[ $1 =~ ^[0-9]+$ ]] || return 1
  (( $1 >= 1 && $1 <= 65535 ))
}

port_in_use() {
  ss -H -lnt "sport = :$1" 2>/dev/null | grep -q .
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

check_reality_target() {
  local host=$1
  info "检查 Reality 握手目标 ${host}:443 ..."
  if ! timeout 10 openssl s_client -connect "${host}:443" -servername "$host" -tls1_3 -brief </dev/null >/tmp/sbox-reality-tls-check.$$ 2>&1; then
    warn "无法确认 ${host}:443 的 TLS 1.3 握手。Reality 目标可能不合适，或 VPS 到该站点网络异常。"
    sed -n '1,12p' /tmp/sbox-reality-tls-check.$$ 2>/dev/null || true
    rm -f /tmp/sbox-reality-tls-check.$$
    read -r -p "仍要继续？[y/N]: " ans
    [[ ${ans,,} == "y" || ${ans,,} == "yes" ]] || die "已取消。请更换 Reality SNI。"
    return 0
  fi
  rm -f /tmp/sbox-reality-tls-check.$$
  info "Reality 握手目标可建立 TLS 1.3 连接。"
}

check_domain_target() {
  local host=$1
  if is_ipv4 "$host" || is_ipv6 "$host"; then
    info "节点地址使用 IP：$host"
    return 0
  fi

  is_hostname "$host" || die "节点地址不是有效的 IPv4/IPv6/域名：$host"

  local v4 v6 resolved4 resolved6 matched=0
  v4=$(public_ipv4)
  v6=$(public_ipv6)
  resolved4=$(dig +short A "$host" 2>/dev/null | grep -E '^[0-9.]+$' | sort -u || true)
  resolved6=$(dig +short AAAA "$host" 2>/dev/null | grep ':' | sort -u || true)

  echo
  headmsg "===== 域名解析检查 ====="
  echo "节点域名 : $host"
  echo "本机 IPv4: ${v4:-无}"
  echo "本机 IPv6: ${v6:-无}"
  echo "DNS A     : ${resolved4:-无}"
  echo "DNS AAAA  : ${resolved6:-无}"

  if [[ -n "$v4" ]] && grep -Fxq "$v4" <<< "$resolved4"; then matched=1; fi
  if [[ -n "$v6" ]] && grep -Fxq "$v6" <<< "$resolved6"; then matched=1; fi

  if (( matched == 1 )); then
    info "域名至少有一个 A/AAAA 记录直接指向本 VPS。适合直连 Reality。"
  else
    warn "该域名没有直接解析到本 VPS 公网 IP。"
    warn "如果你在 Cloudflare 开了橙云，普通 Cloudflare HTTP/HTTPS 代理不能直接转发原生 VLESS Reality/TCP。"
    warn "Reality 通常应使用 DNS only（灰云）；若你明确使用 Cloudflare Spectrum，则可忽略此提示。"
    read -r -p "仍要继续使用这个节点地址？[y/N]: " ans
    [[ ${ans,,} == "y" || ${ans,,} == "yes" ]] || die "已取消。请先修正 DNS/Cloudflare 代理状态。"
  fi
}

backup_config() {
  mkdir -p "$BACKUP_DIR"
  if [[ -f "$CONFIG_FILE" ]]; then
    local dst="${BACKUP_DIR}/config.$(date +%Y%m%d-%H%M%S).json"
    cp -a "$CONFIG_FILE" "$dst"
    chmod 600 "$dst" || true
    info "旧配置已备份：$dst"
  fi
}

generate_reality_keypair() {
  local out
  out=$(sing-box generate reality-keypair)
  REALITY_PRIVATE=$(awk '/PrivateKey/ {print $NF; exit}' <<< "$out" | tr -d '"')
  REALITY_PUBLIC=$(awk '/PublicKey/ {print $NF; exit}' <<< "$out" | tr -d '"')
  [[ -n "${REALITY_PRIVATE:-}" && -n "${REALITY_PUBLIC:-}" ]] || die "Reality 密钥生成失败。"
}

write_reality_config() {
  local port=$1 uuid=$2 sni=$3 private_key=$4 short_id=$5
  mkdir -p "$CONFIG_DIR"

  jq -n \
    --arg uuid "$uuid" \
    --arg sni "$sni" \
    --arg private_key "$private_key" \
    --arg short_id "$short_id" \
    --argjson port "$port" \
    '{
      log: {
        level: "warn",
        timestamp: true
      },
      inbounds: [
        {
          type: "vless",
          tag: "vless-reality-in",
          listen: "::",
          listen_port: $port,
          users: [
            {
              name: "main",
              uuid: $uuid,
              flow: "xtls-rprx-vision"
            }
          ],
          tls: {
            enabled: true,
            server_name: $sni,
            reality: {
              enabled: true,
              handshake: {
                server: $sni,
                server_port: 443
              },
              private_key: $private_key,
              short_id: [$short_id],
              max_time_difference: "1m"
            }
          }
        }
      ],
      outbounds: [
        {
          type: "direct",
          tag: "direct"
        }
      ]
    }' > "$CONFIG_FILE"

  chmod 600 "$CONFIG_FILE"
}

uri_host() {
  if is_ipv6 "$1"; then
    printf '[%s]' "$1"
  else
    printf '%s' "$1"
  fi
}

save_node_info() {
  local node_addr=$1 port=$2 uuid=$3 sni=$4 pub=$5 short_id=$6
  local host
  host=$(uri_host "$node_addr")
  local name="sing-box-Reality"
  local uri="vless://${uuid}@${host}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pub}&sid=${short_id}&type=tcp#${name}"

  umask 077
  cat > "$NODE_INFO" <<INFO
==============================
sing-box VLESS Reality
==============================

节点地址: ${node_addr}
端口: ${port}
UUID: ${uuid}
Flow: xtls-rprx-vision
Reality SNI: ${sni}
Reality Public Key: ${pub}
Short ID: ${short_id}
传输: TCP

==============================
VLESS 分享链接
==============================
${uri}
INFO
  chmod 600 "$NODE_INFO"

  echo
  headmsg "===== 节点部署完成 ====="
  cat "$NODE_INFO"
  echo
  warn "节点信息文件权限已设为 600；其中 UUID/公钥/Short ID 仍应按凭据管理，不要公开发布。"
}

sync_time() {
  if have timedatectl; then
    timedatectl set-ntp true >/dev/null 2>&1 || true
    info "已尝试启用系统 NTP 自动校时。"
    timedatectl status 2>/dev/null | sed -n '1,8p' || true
  fi
}

deploy_reality() {
  ensure_singbox
  install_deps

  local port node_addr sni uuid short_id
  echo
  headmsg "===== 部署 VLESS + Reality ====="
  show_ip_info

  read -r -p "节点地址（可填 VPS IP，或 Cloudflare 托管的灰云/DNS-only 域名）: " node_addr
  [[ -n "$node_addr" ]] || die "节点地址不能为空。"
  check_domain_target "$node_addr"

  read -r -p "监听端口 [443]: " port
  port=${port:-443}
  validate_port "$port" || die "端口必须为 1-65535。"

  if port_in_use "$port"; then
    warn "TCP 端口 $port 当前已被占用："
    ss -lntp "sport = :$port" || true
    die "请选择其他端口，或先处理端口占用。"
  fi

  read -r -p "Reality SNI/握手域名 [www.microsoft.com]: " sni
  sni=${sni:-www.microsoft.com}
  is_hostname "$sni" || die "Reality SNI 必须是有效域名。"
  check_reality_target "$sni"

  sync_time
  uuid=$(sing-box generate uuid)
  short_id=$(sing-box generate rand --hex 8)
  generate_reality_keypair

  backup_config
  write_reality_config "$port" "$uuid" "$sni" "$REALITY_PRIVATE" "$short_id"

  info "执行 sing-box 配置语法检查..."
  sing-box check -c "$CONFIG_FILE" || die "配置检查失败；未启动服务。"

  systemctl enable sing-box >/dev/null 2>&1 || true
  systemctl restart sing-box
  sleep 1

  if ! systemctl is-active --quiet sing-box; then
    err "sing-box 启动失败，最近日志如下："
    journalctl -u sing-box --no-pager -n 80 || true
    die "部署失败。旧配置备份位于 $BACKUP_DIR。"
  fi

  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "${port}/tcp" >/dev/null
    info "检测到 UFW 已启用，已放行 TCP/$port。"
  else
    warn "未自动启用系统防火墙。若 VPS 使用云厂商安全组，请手动放行 TCP/$port。"
  fi

  save_node_info "$node_addr" "$port" "$uuid" "$sni" "$REALITY_PUBLIC" "$short_id"

  echo
  read -r -p "是否现在启用/验证 BBR？[Y/n]: " bbr_ans
  if [[ -z "$bbr_ans" || ${bbr_ans,,} == "y" || ${bbr_ans,,} == "yes" ]]; then
    enable_bbr
  fi
}

bbr_status() {
  echo
  headmsg "===== BBR 状态 ====="
  echo "内核版本: $(uname -r)"
  local virt_show
  virt_show=$(systemd-detect-virt 2>/dev/null || true)
  echo "虚拟化  : ${virt_show:-none/unknown}"
  echo "可用拥塞控制算法: $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)"
  echo "当前拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  echo "默认 qdisc       : $(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  echo

  local cc qdisc available
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
  qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || true)
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)

  if grep -qw bbr <<< "$available" && [[ "$cc" == "bbr" ]]; then
    info "BBR 已作为系统当前 TCP 拥塞控制算法生效。"
  else
    warn "BBR 当前未完全生效。"
  fi

  if [[ "$qdisc" == "fq" ]]; then
    info "默认 qdisc = fq。"
  else
    warn "默认 qdisc 不是 fq。现代内核 BBR 不一定强制要求 fq，但 fq 通常是推荐搭配。"
  fi

  if lsmod 2>/dev/null | grep -q '^tcp_bbr'; then
    info "tcp_bbr 内核模块已加载。"
  elif grep -qw bbr <<< "$available"; then
    info "系统可用 BBR；它可能被编译进内核而不是作为独立模块加载。"
  fi

  echo
  echo "实际 TCP 连接 BBR 详情（有连接时才有意义）："
  ss -tin 2>/dev/null | grep -A2 -B1 -i 'bbr' | head -n 30 || echo "当前未观察到带 BBR 状态的活动 TCP 连接。"
}

enable_bbr() {
  install_deps
  echo
  headmsg "===== 启用 BBR ====="

  local virt available
  virt=$(systemd-detect-virt 2>/dev/null || true)
  case "$virt" in
    openvz|lxc|docker|podman)
      warn "检测到容器/受限虚拟化环境：${virt}。宿主机可能不允许修改拥塞控制算法。"
      ;;
  esac

  modprobe tcp_bbr 2>/dev/null || true
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
  if ! grep -qw bbr <<< "$available"; then
    warn "当前内核未报告 BBR 可用。"
    warn "脚本不会为了 BBR 自动替换/升级内核，以避免导致 VPS 无法启动。"
    bbr_status
    return 0
  fi

  cat > "$BBR_SYSCTL" <<'SYSCTL'
# Managed by sing-box-oneclick.sh
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL

  sysctl --system >/dev/null
  info "BBR sysctl 已应用并持久化到 $BBR_SYSCTL"
  bbr_status
}

firewall_setup() {
  install_deps
  if ! have ufw; then
    apt-get install -y ufw
  fi

  local ssh_port="22"
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    ssh_port=$(ss -tnp 2>/dev/null | awk '/sshd/ && /ESTAB/ {split($4,a,":"); print a[length(a)]; exit}' || true)
    ssh_port=${ssh_port:-22}
  elif [[ -r /etc/ssh/sshd_config ]]; then
    ssh_port=$(awk 'tolower($1)=="port" && $2 ~ /^[0-9]+$/ {p=$2} END{print p+0}' /etc/ssh/sshd_config)
    [[ "$ssh_port" == "0" ]] && ssh_port=22
  fi

  echo
  headmsg "===== UFW 安全配置 ====="
  echo "检测到 SSH 端口: $ssh_port"
  warn "启用防火墙前请确认云厂商安全组也允许 SSH/$ssh_port。"
  read -r -p "确认启用 UFW，并先放行 SSH/$ssh_port？[y/N]: " ans
  [[ ${ans,,} == "y" || ${ans,,} == "yes" ]] || { warn "已取消。"; return 0; }

  ufw allow "${ssh_port}/tcp" >/dev/null

  if [[ -f "$CONFIG_FILE" ]]; then
    local p
    p=$(jq -r '.inbounds[]? | select(.listen_port != null) | .listen_port' "$CONFIG_FILE" 2>/dev/null | head -n1 || true)
    if validate_port "${p:-}"; then
      ufw allow "${p}/tcp" >/dev/null || true
      info "已放行 sing-box TCP/$p。"
    fi
  fi

  ufw --force enable >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw status verbose
}

security_audit() {
  echo
  headmsg "===== 基础安全自检 ====="
  echo "系统       : ${PRETTY_NAME:-unknown}"
  echo "内核       : $(uname -r)"
  echo "sing-box   : $(sing-box version 2>/dev/null | head -n1 || echo 未安装)"
  echo "服务状态   : $(systemctl is-active sing-box 2>/dev/null || true)"
  echo "配置权限   : $(stat -c '%a %U:%G' "$CONFIG_FILE" 2>/dev/null || echo 不存在)"
  echo "节点信息权限: $(stat -c '%a %U:%G' "$NODE_INFO" 2>/dev/null || echo 不存在)"
  echo "时间同步   : $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
  echo "UFW        : $(ufw status 2>/dev/null | head -n1 || echo 未安装)"
  echo

  if [[ -f "$CONFIG_FILE" ]]; then
    sing-box check -c "$CONFIG_FILE" && info "sing-box 配置检查通过。" || warn "sing-box 配置检查失败。"
    echo
    echo "监听端口："
    ss -lntup 2>/dev/null | grep -E 'sing-box|LISTEN' | head -n 30 || true
  fi

  echo
  warn "脚本不会自动关闭 SSH 密码登录、修改 SSH 端口或禁用 root，因为这些操作若判断失误可能把你锁在 VPS 外。"
  warn "更严格的 SSH 加固应在确认密钥登录可用后单独执行。"
}

show_status() {
  ensure_singbox
  echo
  systemctl status sing-box --no-pager -l || true
  echo
  if [[ -f "$CONFIG_FILE" ]]; then
    sing-box check -c "$CONFIG_FILE" || true
  fi
}

show_logs() {
  ensure_singbox
  journalctl -u sing-box -n 100 --no-pager
}

show_node() {
  if [[ -r "$NODE_INFO" ]]; then
    cat "$NODE_INFO"
  else
    warn "尚未找到节点信息文件：$NODE_INFO"
  fi
}

update_singbox() {
  ensure_singbox
  backup_config
  info "执行官方安装脚本更新 sing-box..."
  curl -fsSL https://sing-box.app/install.sh | sh
  if [[ -f "$CONFIG_FILE" ]]; then
    sing-box check -c "$CONFIG_FILE" || die "更新后配置校验失败。请从 $BACKUP_DIR 恢复配置或检查版本兼容性。"
    systemctl restart sing-box
  fi
  sing-box version
}

restore_config() {
  mkdir -p "$BACKUP_DIR"
  mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'config.*.json' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
  if (( ${#files[@]} == 0 )); then
    warn "没有找到备份。"
    return 0
  fi

  echo "可用备份："
  local i
  for i in "${!files[@]}"; do
    printf '%d) %s\n' "$((i+1))" "${files[$i]}"
  done
  read -r -p "选择要恢复的序号: " n
  [[ "$n" =~ ^[0-9]+$ ]] || die "无效序号。"
  (( n >= 1 && n <= ${#files[@]} )) || die "无效序号。"

  cp -a "${files[$((n-1))]}" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  sing-box check -c "$CONFIG_FILE" || die "备份配置本身校验失败。"
  systemctl restart sing-box
  info "已恢复并重启 sing-box。"
}

uninstall_singbox() {
  warn "此操作会停止 sing-box，并删除当前配置与节点信息。备份目录默认也会删除。"
  read -r -p "请输入 DELETE 确认卸载: " ans
  [[ "$ans" == "DELETE" ]] || { warn "已取消。"; return 0; }

  systemctl stop sing-box 2>/dev/null || true
  systemctl disable sing-box 2>/dev/null || true

  if have apt-get; then
    apt-get remove -y sing-box 2>/dev/null || true
  fi

  rm -rf "$CONFIG_DIR"
  rm -f "$NODE_INFO"
  info "已卸载脚本管理的 sing-box 配置。BBR 设置作为系统网络设置保留不动。"
}

menu() {
  while true; do
    clear || true
    cat <<MENU
====================================================
  sing-box 一键部署/管理脚本 v${SCRIPT_VERSION}
  Debian / Ubuntu
====================================================
  1. 安装 / 修复 sing-box
  2. 部署 VLESS + Reality（支持 IP/域名）
  3. 查看节点信息
  4. 查看 sing-box 状态并校验配置
  5. 查看最近日志
  6. 更新 sing-box（先备份配置）

  7. 启用 BBR + fq
  8. 验证 BBR
  9. 配置 UFW 防火墙
 10. 基础安全自检
 11. 恢复配置备份

 12. 卸载 sing-box
  0. 退出
====================================================
MENU
    read -r -p "请选择: " choice
    case "$choice" in
      1) install_singbox; pause ;;
      2) deploy_reality; pause ;;
      3) show_node; pause ;;
      4) show_status; pause ;;
      5) show_logs; pause ;;
      6) update_singbox; pause ;;
      7) enable_bbr || true; pause ;;
      8) bbr_status; pause ;;
      9) firewall_setup; pause ;;
      10) security_audit; pause ;;
      11) restore_config; pause ;;
      12) uninstall_singbox; pause ;;
      0) exit 0 ;;
      *) warn "无效选择。"; sleep 1 ;;
    esac
  done
}

trap 'err "脚本在第 ${LINENO} 行发生错误。"' ERR
require_root
load_os
menu
