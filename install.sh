#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_VERSION="1.8.4"
REPO="Cpiooc/sing-box-oneclick"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
REPO_API="https://api.github.com/repos/${REPO}"
SCRIPT_URL="${RAW_BASE}/install.sh"

APP_DIR="/etc/sing-box-oneclick"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATE_FILE="${APP_DIR}/state.json"
BACKUP_DIR="${APP_DIR}/backups"
NODE_INFO="/root/sing-box-node-info.txt"
MANAGER_DIR="/usr/local/lib/sing-box-oneclick"
MANAGER_RELEASE_ROOT="/usr/local/lib/sing-box-oneclick-releases"
MANAGER_FILE="${MANAGER_DIR}/install.sh"
MANAGER_LINK="/usr/local/bin/sb"
BBR_SYSCTL="/etc/sysctl.d/99-sing-box-oneclick-bbr.conf"
FAIL2BAN_JAIL="/etc/fail2ban/jail.d/sing-box-oneclick.conf"
CERTBOT_HOOK="/etc/letsencrypt/renewal-hooks/deploy/sing-box-oneclick-restart.sh"
BUNDLE_MANIFEST="SHA256SUMS"

C_RESET='\033[0m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'

MODULES=(
  "lib/common.sh"
  "lib/ui.sh"
  "lib/protocols.sh"
  "lib/tuic.sh"
  "lib/security.sh"
  "lib/bbr-manager.sh"
  "lib/maintenance.sh"
  "lib/core-manager.sh"
  "lib/tls-manager.sh"
  "lib/tls-safe.sh"
  "lib/runtime.sh"
  "lib/editor.sh"
  "lib/extra-protocols.sh"
  "lib/client-export.sh"
  "lib/client-extra.sh"
  "lib/hy2-hop.sh"
  "lib/subscription.sh"
  "lib/subscription-hooks.sh"
  "lib/views.sh"
  "lib/views-extra.sh"
  "lib/usability.sh"
  "lib/firewall-v17.sh"
  "lib/menu.sh"
  "lib/cert-pinning.sh"
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

resolve_repo_commit() {
  local json sha
  json=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 15 \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: sing-box-oneclick' \
    "${REPO_API}/commits/main") || return 1
  sha=$(grep -oE '"sha"[[:space:]]*:[[:space:]]*"[0-9a-f]{40}"' <<< "$json" | head -n1 | cut -d'"' -f4)
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s' "$sha"
}

bundle_files() {
  printf '%s\n' install.sh
  printf '%s\n' "${MODULES[@]}"
  printf '%s\n' VERSION
}

verify_staged_bundle() {
  local stage=$1 rel expected actual
  [[ -s "${stage}/${BUNDLE_MANIFEST}" ]] || _boot_die "远端缺少 ${BUNDLE_MANIFEST}，拒绝安装未校验整包。"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    expected=$(awk -v f="$rel" '$2==f {print $1; exit}' "${stage}/${BUNDLE_MANIFEST}")
    [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || _boot_die "SHA256 清单缺少或格式错误：$rel"
    [[ -f "${stage}/${rel}" ]] || _boot_die "整包缺少文件：$rel"
    actual=$(sha256sum "${stage}/${rel}" | awk '{print $1}')
    [[ "${actual,,}" == "${expected,,}" ]] || _boot_die "SHA256 校验失败：$rel"
  done < <(bundle_files)

  bash -n "${stage}/install.sh" || _boot_die "远端 install.sh Bash 语法检查失败。"
  while IFS= read -r rel; do
    [[ "$rel" == lib/*.sh ]] || continue
    bash -n "${stage}/${rel}" || _boot_die "远端 ${rel} Bash 语法检查失败。"
  done < <(bundle_files)
}

cleanup_old_manager_releases() {
  local current=$1 dir kept=0
  [[ -d "$MANAGER_RELEASE_ROOT" ]] || return 0
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$dir" == "$current" ]] && { kept=$((kept+1)); continue; }
    if (( kept < 3 )); then
      kept=$((kept+1))
      continue
    fi
    rm -rf -- "$dir" 2>/dev/null || true
  done < <(find "$MANAGER_RELEASE_ROOT" -mindepth 1 -maxdepth 1 -type d -name '[0-9a-f]*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
}

activate_manager_release() {
  local release_dir=$1 ref=$2 tmp_link legacy
  install -d -m 755 "$MANAGER_RELEASE_ROOT"

  if [[ -e "$MANAGER_DIR" && ! -L "$MANAGER_DIR" ]]; then
    legacy="${MANAGER_RELEASE_ROOT}/legacy-$(date +%Y%m%d-%H%M%S)"
    mv "$MANAGER_DIR" "$legacy" || _boot_die "无法迁移旧管理器目录。"
    _boot_info "旧管理器已保留：$legacy"
  fi

  tmp_link="${MANAGER_DIR}.new.$$"
  rm -f "$tmp_link"
  ln -s "$release_dir" "$tmp_link" || _boot_die "无法创建新版本链接。"
  if [[ -L "$MANAGER_DIR" || -e "$MANAGER_DIR" ]]; then
    mv -Tf "$tmp_link" "$MANAGER_DIR" || _boot_die "原子切换管理器版本失败。"
  else
    mv -T "$tmp_link" "$MANAGER_DIR" || _boot_die "启用管理器版本失败。"
  fi

  ln -sfn "$MANAGER_FILE" "$MANAGER_LINK"
  printf '%s\n' "$ref" > "${release_dir}/COMMIT"
  chmod 644 "${release_dir}/COMMIT"
  cleanup_old_manager_releases "$release_dir"
}

install_bundle_from_github() {
  bootstrap_require_root_os
  bootstrap_curl

  local ref=${1:-} stage base rel dst release_dir short
  if [[ -z "$ref" ]]; then
    ref=$(resolve_repo_commit) || _boot_die "无法从 GitHub 锁定 main 的 commit SHA。请检查网络后重试。"
  fi
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || _boot_die "无效的 Git commit：$ref"
  short=${ref:0:12}
  base="https://raw.githubusercontent.com/${REPO}/${ref}"
  stage=$(mktemp -d)

  _boot_info "锁定 GitHub 提交 ${short}，下载同一版本整包..."
  curl -fsSL --proto '=https' --tlsv1.2 "${base}/${BUNDLE_MANIFEST}" -o "${stage}/${BUNDLE_MANIFEST}" \
    || _boot_die "下载 ${BUNDLE_MANIFEST} 失败。"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    dst="${stage}/${rel}"
    install -d -m 755 "$(dirname "$dst")"
    curl -fsSL --proto '=https' --tlsv1.2 "${base}/${rel}" -o "$dst" \
      || _boot_die "下载失败：${rel}"
  done < <(bundle_files)

  verify_staged_bundle "$stage"
  _boot_info "SHA256 + Bash 语法检查通过。"

  release_dir="${MANAGER_RELEASE_ROOT}/${ref}"
  rm -rf "${release_dir}.tmp"
  install -d -m 755 "${release_dir}.tmp/lib"
  cp -a "${stage}/." "${release_dir}.tmp/"
  chmod 0755 "${release_dir}.tmp/install.sh"
  chmod 0644 "${release_dir}.tmp/VERSION" "${release_dir}.tmp/${BUNDLE_MANIFEST}"
  for rel in "${MODULES[@]}"; do chmod 0644 "${release_dir}.tmp/${rel}"; done
  rm -rf "$release_dir"
  mv "${release_dir}.tmp" "$release_dir"

  activate_manager_release "$release_dir" "$ref"
  rm -rf "$stage"
  _boot_info "管理命令已安装：sb（v${SCRIPT_VERSION} · ${short}）"
}

bootstrap_require_root_os
bootstrap_curl

_current_script=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
_manager_script=$(readlink -f "$MANAGER_FILE" 2>/dev/null || printf '%s' "$MANAGER_FILE")
if [[ "$_current_script" != "$_manager_script" ]]; then
  install_bundle_from_github
  exec "$MANAGER_FILE" "$@"
fi
unset _current_script _manager_script

for rel in "${MODULES[@]}"; do
  [[ -r "${MANAGER_DIR}/${rel}" ]] || {
    _boot_warn "本地组件缺失：${rel}，尝试从 GitHub 获取完整校验整包。"
    install_bundle_from_github
    exec "$MANAGER_FILE" "$@"
  }
  # shellcheck source=/dev/null
  . "${MANAGER_DIR}/${rel}"
done

main "$@"
