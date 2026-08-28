#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_VERSION="1.1.0"
REPO="Cpiooc/sing-box-oneclick"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
SCRIPT_URL="${RAW_BASE}/install.sh"

APP_DIR="/etc/sing-box-oneclick"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATE_FILE="${APP_DIR}/state.json"
BACKUP_DIR="${APP_DIR}/backups"
NODE_INFO="/root/sing-box-node-info.txt"
MANAGER_DIR="/usr/local/lib/sing-box-oneclick"
MANAGER_FILE="${MANAGER_DIR}/install.sh"
MANAGER_LINK="/usr/local/bin/sb"
BBR_SYSCTL="/etc/sysctl.d/99-sing-box-oneclick-bbr.conf"
FAIL2BAN_JAIL="/etc/fail2ban/jail.d/sing-box-oneclick.conf"
CERTBOT_HOOK="/etc/letsencrypt/renewal-hooks/deploy/sing-box-oneclick-restart.sh"

C_RESET='\033[0m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'

MODULES=(
  "lib/common.sh"
  "lib/protocols.sh"
  "lib/tuic.sh"
  "lib/security.sh"
  "lib/maintenance.sh"
  "lib/menu.sh"
)

_boot_info() { echo -e "${C_GREEN}[+]${C_RESET} $*"; }
_boot_warn() { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
_boot_die() { echo -e "${C_RED}[x]${C_RESET} $*" >&2; exit 1; }

bootstrap_require_root_os() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || _boot_die "请使用 root 运行此脚本。"
  [[ -r /etc/os-release ]] || _boot_die "无法读取 /etc/os-release。"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) _boot_die "当前版本仅支持 Debian / Ubuntu。检测到：${PRETTY_NAME:-unknown}" ;;
  esac
}

bootstrap_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi
  _boot_info "安装启动依赖 curl / CA 证书..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl ca-certificates
}

install_bundle_from_github() {
  bootstrap_require_root_os
  bootstrap_curl

  local stage backup rel src dst
  stage=$(mktemp -d)
  backup=$(mktemp -d)
  _boot_info "从 GitHub 获取 sing-box-oneclick v${SCRIPT_VERSION} 组件..."
  for rel in "install.sh" "${MODULES[@]}" "VERSION"; do
    src="${RAW_BASE}/${rel}"
    dst="${stage}/${rel}"
    install -d -m 755 "$(dirname "$dst")"
    curl -fsSL --proto '=https' --tlsv1.2 "$src" -o "$dst" || _boot_die "下载失败：$src"
  done

  bash -n "${stage}/install.sh" || _boot_die "远端 install.sh Bash 语法检查失败。"
  for rel in "${MODULES[@]}"; do
    bash -n "${stage}/${rel}" || _boot_die "远端 ${rel} Bash 语法检查失败。"
  done

  if [[ -d "$MANAGER_DIR" ]]; then
    cp -a "$MANAGER_DIR/." "$backup/" 2>/dev/null || true
  fi

  install -d -m 755 "$MANAGER_DIR/lib"
  if ! install -m 0755 "${stage}/install.sh" "$MANAGER_FILE"; then
    _boot_die "安装主脚本失败。"
  fi
  for rel in "${MODULES[@]}"; do
    if ! install -m 0644 "${stage}/${rel}" "${MANAGER_DIR}/${rel}"; then
      _boot_warn "组件安装失败，尝试恢复旧管理脚本。"
      rm -rf "$MANAGER_DIR"
      install -d -m 755 "$MANAGER_DIR"
      cp -a "$backup/." "$MANAGER_DIR/" 2>/dev/null || true
      _boot_die "更新失败。"
    fi
  done
  install -m 0644 "${stage}/VERSION" "${MANAGER_DIR}/VERSION"
  ln -sfn "$MANAGER_FILE" "$MANAGER_LINK"
  rm -rf "$stage" "$backup"
  _boot_info "管理命令已安装：sb"
}

bootstrap_require_root_os
bootstrap_curl

if [[ "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")" != "$MANAGER_FILE" ]]; then
  install_bundle_from_github
  exec "$MANAGER_FILE" "$@"
fi

for rel in "${MODULES[@]}"; do
  [[ -r "${MANAGER_DIR}/${rel}" ]] || {
    _boot_warn "本地组件缺失：${rel}，尝试从 GitHub 修复。"
    install_bundle_from_github
    exec "$MANAGER_FILE" "$@"
  }
  # shellcheck source=/dev/null
  . "${MANAGER_DIR}/${rel}"
done

main "$@"
