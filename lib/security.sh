#!/usr/bin/env bash
# shellcheck shell=bash

allow_if_ufw_active() {
  local port=$1 proto=$2
  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "${port}/${proto}" >/dev/null || true
    info "UFW 已放行 ${proto^^}/$port。"
  else
    warn "UFW 当前未启用。请确认云厂商安全组已放行 ${proto^^}/$port。"
  fi
}

detect_ssh_ports() {
  local ports=""
  if have sshd; then
    ports=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2}' | sort -nu | paste -sd, - || true)
  fi
  if [[ -z "$ports" && -r /etc/ssh/sshd_config ]]; then
    ports=$(awk 'tolower($1)=="port" && $2 ~ /^[0-9]+$/ {print $2}' /etc/ssh/sshd_config | sort -nu | paste -sd, - || true)
  fi
  printf '%s' "${ports:-22}"
}

fetch_cloudflare_ranges() {
  CF_V4=$(curl -fsSL --max-time 10 https://www.cloudflare.com/ips-v4 2>/dev/null || true)
  CF_V6=$(curl -fsSL --max-time 10 https://www.cloudflare.com/ips-v6 2>/dev/null || true)
  [[ -n "$CF_V4" && -n "$CF_V6" ]]
}

ufw_allow_cloudflare_only() {
  local port=$1 cidr
  fetch_cloudflare_ranges || { warn "无法获取 Cloudflare 官方 IP 段，改为普通放行 TCP/$port。"; ufw allow "${port}/tcp" >/dev/null; return 0; }

  ufw --force delete allow "${port}/tcp" >/dev/null 2>&1 || true
  info "仅允许 Cloudflare 官方边缘 IP 访问 TCP/$port..."
  while IFS= read -r cidr; do
    [[ -n "$cidr" ]] && ufw allow from "$cidr" to any port "$port" proto tcp >/dev/null
  done <<< "$CF_V4"
  if grep -Eq '^IPV6=(yes|YES)$' /etc/default/ufw 2>/dev/null; then
    while IFS= read -r cidr; do
      [[ -n "$cidr" ]] && ufw allow from "$cidr" to any port "$port" proto tcp >/dev/null
    done <<< "$CF_V6"
  else
    note "UFW IPv6 未启用，跳过 Cloudflare IPv6 源地址规则。"
  fi
}

firewall_setup() {
  install_deps
  have ufw || apt-get install -y ufw
  ensure_state

  local ssh_ports client_ip p proto key cf
  ssh_ports=$(detect_ssh_ports)
  client_ip=${SSH_CONNECTION%% *}

  echo
  headmsg "===== UFW 防火墙安全配置 ====="
  echo "检测到 SSH 端口: $ssh_ports"
  [[ -n "${client_ip:-}" ]] && echo "当前 SSH 客户端: $client_ip"
  warn "启用 UFW 前，请确认 VPS 厂商安全组已放行 SSH 端口。"
  read -r -p "确认继续？[y/N]: " ans
  [[ ${ans,,} == "y" || ${ans,,} == "yes" ]] || { warn "已取消。"; return 0; }

  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null

  IFS=',' read -r -a _ssh_arr <<< "$ssh_ports"
  for p in "${_ssh_arr[@]}"; do
    validate_port "$p" && ufw allow "${p}/tcp" >/dev/null
  done

  if [[ -f "$STATE_FILE" ]]; then
    mapfile -t _keys < <(jq -r '.nodes | keys[]' "$STATE_FILE")
    for key in "${_keys[@]}"; do
      p=$(jq -r --arg k "$key" '.nodes[$k].port // empty' "$STATE_FILE")
      proto=$(jq -r --arg k "$key" '.nodes[$k].firewall // empty' "$STATE_FILE")
      cf=$(jq -r --arg k "$key" '.nodes[$k].cloudflare // false' "$STATE_FILE")
      validate_port "$p" || continue
      case "$proto" in
        tcp)
          if [[ "$cf" == "true" ]]; then
            read -r -p "Cloudflare WS 节点 TCP/$p 是否仅允许 Cloudflare IP 访问？[Y/n]: " lock_cf
            if [[ -z "$lock_cf" || ${lock_cf,,} == "y" || ${lock_cf,,} == "yes" ]]; then
              ufw_allow_cloudflare_only "$p"
            else
              ufw allow "${p}/tcp" >/dev/null
            fi
          else
            ufw allow "${p}/tcp" >/dev/null
          fi
          ;;
        udp) ufw allow "${p}/udp" >/dev/null ;;
      esac
    done

    if jq -e '.nodes | to_entries | any(.value.certificate == true)' "$STATE_FILE" >/dev/null 2>&1; then
      ufw allow 80/tcp >/dev/null
      note "已保留 TCP/80 用于 Let's Encrypt 自动续期；平时没有服务监听时不会主动响应。"
    fi
  fi

  ufw --force enable >/dev/null
  ufw status numbered
}

fail2ban_setup() {
  apt-get update
  apt-get install -y fail2ban

  local ssh_ports client_ip
  ssh_ports=$(detect_ssh_ports)
  client_ip=${SSH_CONNECTION%% *}

  cat > "$FAIL2BAN_JAIL" <<EOF
[sshd]
enabled = true
port = ${ssh_ports}
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
ignoreip = 127.0.0.1/8 ::1 ${client_ip:-}
EOF

  systemctl enable --now fail2ban
  systemctl restart fail2ban
  info "Fail2ban SSH 防护已启用。当前会话 IP 已加入 ignoreip（若可检测）。"
  fail2ban-client status sshd || true
}

enable_security_updates() {
  apt-get update
  apt-get install -y unattended-upgrades

  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

  systemctl enable --now unattended-upgrades.service >/dev/null 2>&1 || true
  info "已启用 Debian/Ubuntu unattended-upgrades。未配置自动重启 VPS。"
}

bbr_status() {
  echo
  headmsg "===== BBR 状态 ====="
  local available cc qdisc virt
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
  qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || true)
  virt=$(systemd-detect-virt 2>/dev/null || true)

  echo "内核版本            : $(uname -r)"
  echo "虚拟化              : ${virt:-none/unknown}"
  echo "可用拥塞控制算法    : ${available:-unknown}"
  echo "当前拥塞控制算法    : ${cc:-unknown}"
  echo "默认 qdisc          : ${qdisc:-unknown}"

  if grep -qw bbr <<< "$available" && [[ "$cc" == "bbr" ]]; then
    info "BBR 已作为当前 TCP 拥塞控制算法生效。"
  else
    warn "BBR 当前未完全生效。"
  fi

  [[ "$qdisc" == "fq" ]] && info "默认 qdisc = fq。" || warn "默认 qdisc 不是 fq。"

  if lsmod 2>/dev/null | grep -q '^tcp_bbr'; then
    info "tcp_bbr 模块已加载。"
  elif grep -qw bbr <<< "$available"; then
    info "BBR 可用；它可能直接编译进内核。"
  fi

  echo
  echo "活动 TCP 连接中的 BBR 信息（有连接时才会显示）："
  ss -tin 2>/dev/null | grep -A2 -B1 -i 'bbr' | head -n 30 || echo "当前未观察到带 BBR 状态的活动 TCP 连接。"
  note "Linux TCP BBR 作用于 TCP；Hysteria2/QUIC/UDP 不使用这里的 TCP BBR。"
}

enable_bbr() {
  install_deps
  local virt available
  virt=$(systemd-detect-virt 2>/dev/null || true)
  case "$virt" in
    openvz|lxc|docker|podman)
      warn "检测到容器/受限虚拟化环境：$virt，宿主机可能禁止修改拥塞控制算法。"
      ;;
  esac

  modprobe tcp_bbr 2>/dev/null || true
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
  if ! grep -qw bbr <<< "$available"; then
    warn "当前内核未报告 BBR 可用。为避免启动风险，本脚本不会自动替换 VPS 内核。"
    bbr_status
    return 0
  fi

  cat > "$BBR_SYSCTL" <<'EOF'
# Managed by Cpiooc/sing-box-oneclick
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

  sysctl --system >/dev/null
  info "BBR + fq 已持久化到 $BBR_SYSCTL"
  bbr_status
}

security_audit() {
  ensure_state
  echo
  headmsg "===== 安全与运行自检 ====="
  echo "系统            : ${PRETTY_NAME:-unknown}"
  echo "内核            : $(uname -r)"
  echo "虚拟化          : $(systemd-detect-virt 2>/dev/null || echo unknown)"
  echo "sing-box        : $(sing-box version 2>/dev/null | head -n1 || echo 未安装)"
  echo "服务状态        : $(systemctl is-active sing-box 2>/dev/null || echo 未安装)"
  echo "开机启动        : $(systemctl is-enabled sing-box 2>/dev/null || echo 未启用)"
  echo "配置权限        : $(stat -c '%a %U:%G' "$CONFIG_FILE" 2>/dev/null || echo 不存在)"
  echo "状态文件权限    : $(stat -c '%a %U:%G' "$STATE_FILE" 2>/dev/null || echo 不存在)"
  echo "节点信息权限    : $(stat -c '%a %U:%G' "$NODE_INFO" 2>/dev/null || echo 不存在)"
  echo "时间同步        : $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
  echo "UFW             : $(ufw status 2>/dev/null | head -n1 || echo 未安装)"
  echo "Fail2ban        : $(systemctl is-active fail2ban 2>/dev/null || echo 未安装)"
  echo "自动安全更新    : $(systemctl is-active unattended-upgrades 2>/dev/null || echo 未启用)"

  echo
  bbr_status

  if [[ -f "$CONFIG_FILE" && -x "$(command -v sing-box 2>/dev/null || true)" ]]; then
    echo
    if sing-box check -c "$CONFIG_FILE"; then
      info "sing-box 配置检查通过。"
    else
      warn "sing-box 配置检查失败。"
    fi
  fi

  echo
  headmsg "===== 当前监听 ====="
  ss -lntup 2>/dev/null | grep -E 'sing-box|:22 |:80 |:443 |:8443 ' | head -n 60 || true

  echo
  headmsg "===== 证书 ====="
  local key domain cert
  mapfile -t _certkeys < <(jq -r '.nodes | to_entries[] | select(.value.certificate==true) | .key' "$STATE_FILE")
  if (( ${#_certkeys[@]} == 0 )); then
    echo "无脚本管理的 TLS 证书节点。"
  else
    for key in "${_certkeys[@]}"; do
      domain=$(jq -r --arg k "$key" '.nodes[$k].domain' "$STATE_FILE")
      cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
      echo "${domain}:"
      openssl x509 -in "$cert" -noout -subject -issuer -dates 2>/dev/null || warn "无法读取证书：$cert"
    done
  fi

  echo
  warn "脚本不会自动关闭 SSH 密码登录、禁用 root 或强改 SSH 端口，以避免误操作导致 VPS 失联。"
}
