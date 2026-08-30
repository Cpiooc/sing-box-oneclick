#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

SCRIPT_VERSION="test"
REPO="Cpiooc/sing-box-oneclick"
APP_DIR="$work/app"
CONFIG_DIR="$work/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
STATE_FILE="$APP_DIR/state.json"
BACKUP_DIR="$APP_DIR/backups"
NODE_INFO="$work/node-info.txt"
MANAGER_DIR="$work/manager"
MANAGER_FILE="$MANAGER_DIR/install.sh"
MANAGER_LINK="$work/sb"
BBR_SYSCTL="$work/99-sing-box-oneclick-bbr.conf"
BBR_STATE_FILE="$work/bbr-state.json"
FAIL2BAN_JAIL="$work/fail2ban.conf"
CERTBOT_HOOK="$work/certbot-hook.sh"
C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_WHITE=''; C_MAGENTA=''; C_GRAY=''
cleanup_files=()

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "$MANAGER_DIR"

# shellcheck source=/dev/null
source "$root/lib/common.sh"
# shellcheck source=/dev/null
source "$root/lib/ui.sh"
# shellcheck source=/dev/null
source "$root/lib/security.sh"
# shellcheck source=/dev/null
source "$root/lib/bbr-manager.sh"

MOCK_CC="cubic"
MOCK_QDISC="fq_codel"
MOCK_AVAILABLE="reno cubic bbr"

sysctl() {
  case "${1:-}" in
    -n)
      case "${2:-}" in
        net.ipv4.tcp_congestion_control) printf '%s\n' "$MOCK_CC" ;;
        net.core.default_qdisc) printf '%s\n' "$MOCK_QDISC" ;;
        net.ipv4.tcp_available_congestion_control) printf '%s\n' "$MOCK_AVAILABLE" ;;
        *) return 1 ;;
      esac
      ;;
    -w)
      case "${2:-}" in
        net.ipv4.tcp_congestion_control=*) MOCK_CC=${2#*=}; printf '%s = %s\n' 'net.ipv4.tcp_congestion_control' "$MOCK_CC" ;;
        net.core.default_qdisc=*) MOCK_QDISC=${2#*=}; printf '%s = %s\n' 'net.core.default_qdisc' "$MOCK_QDISC" ;;
        *) return 1 ;;
      esac
      ;;
    --system)
      if [[ -f "$BBR_SYSCTL" ]]; then
        local_cc=$(awk -F= '/^[[:space:]]*net\.ipv4\.tcp_congestion_control/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "$BBR_SYSCTL")
        local_qdisc=$(awk -F= '/^[[:space:]]*net\.core\.default_qdisc/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "$BBR_SYSCTL")
        [[ -n "$local_cc" ]] && MOCK_CC=$local_cc
        [[ -n "$local_qdisc" ]] && MOCK_QDISC=$local_qdisc
      fi
      ;;
    *) return 1 ;;
  esac
}

install_deps() { :; }
modprobe() { :; }
systemd-detect-virt() { printf '%s\n' none; }
lsmod() { :; }
ss() { :; }

# 1) Fresh enable must save the previous settings, then disable restores them.
enable_bbr
[[ "$MOCK_CC" == "bbr" ]]
[[ "$MOCK_QDISC" == "fq" ]]
[[ -f "$BBR_SYSCTL" ]]
[[ -f "$BBR_STATE_FILE" ]]
[[ $(stat -c '%a' "$BBR_STATE_FILE") == 600 ]]
[[ $(jq -r '.previous_cc' "$BBR_STATE_FILE") == "cubic" ]]
[[ $(jq -r '.previous_qdisc' "$BBR_STATE_FILE") == "fq_codel" ]]
[[ $(jq -r '.baseline_known' "$BBR_STATE_FILE") == true ]]

disable_bbr
[[ "$MOCK_CC" == "cubic" ]]
[[ "$MOCK_QDISC" == "fq_codel" ]]
[[ ! -e "$BBR_SYSCTL" ]]
[[ ! -e "$BBR_STATE_FILE" ]]

# 2) Legacy script-managed BBR has no baseline. Disable should choose a safe
# non-BBR CC but must not guess/overwrite the old qdisc.
cat > "$BBR_SYSCTL" <<'EOF'
# Managed by Cpiooc/sing-box-oneclick
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
MOCK_CC="bbr"
MOCK_QDISC="fq"
rm -f "$BBR_STATE_FILE"
disable_bbr
[[ "$MOCK_CC" == "cubic" ]]
[[ "$MOCK_QDISC" == "fq" ]]
[[ ! -e "$BBR_SYSCTL" ]]

# 3) BBR enabled by another tool must not be changed automatically.
MOCK_CC="bbr"
MOCK_QDISC="fq"
rm -f "$BBR_SYSCTL" "$BBR_STATE_FILE"
disable_bbr
[[ "$MOCK_CC" == "bbr" ]]
[[ "$MOCK_QDISC" == "fq" ]]

echo "BBR enable, restore, legacy fallback and external-management safeguards passed."
