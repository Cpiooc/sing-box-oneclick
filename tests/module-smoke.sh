#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

SCRIPT_VERSION="test"
REPO="Cpiooc/sing-box-oneclick"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
APP_DIR="/tmp/sb-oneclick-test"
CONFIG_DIR="${APP_DIR}/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATE_FILE="${APP_DIR}/state.json"
BACKUP_DIR="${APP_DIR}/backups"
NODE_INFO="${APP_DIR}/node-info.txt"
MANAGER_DIR="${APP_DIR}/manager"
MANAGER_FILE="${MANAGER_DIR}/install.sh"
MANAGER_LINK="${APP_DIR}/sb"
BBR_SYSCTL="${APP_DIR}/bbr.conf"
FAIL2BAN_JAIL="${APP_DIR}/fail2ban.conf"
CERTBOT_HOOK="${APP_DIR}/certbot-hook.sh"

C_RESET=''
C_RED=''
C_GREEN=''
C_YELLOW=''
C_BLUE=''
C_CYAN=''

modules=(
  common.sh
  ui.sh
  protocols.sh
  tuic.sh
  security.sh
  maintenance.sh
  tls-manager.sh
  tls-safe.sh
  runtime.sh
  views.sh
  menu.sh
)

for module in "${modules[@]}"; do
  # shellcheck source=/dev/null
  source "${root}/lib/${module}"
done

required=(
  main menu ui_banner ui_dashboard ui_node_overview ui_cli_help
  deploy_reality deploy_hysteria2 deploy_tuic deploy_cloudflare_ws
  switch_certificate_tls select_certificate_mode
  apply_candidate apply_runtime_change singbox_can_reload
  show_status show_nodes show_qr_codes show_logs network_diagnostics
  bbr_status certificate_status security_audit
  backup_now restore_backup safe_update_singbox self_update
)

for fn in "${required[@]}"; do
  declare -F "$fn" >/dev/null || {
    echo "missing function after module load: $fn" >&2
    exit 1
  }
done

[[ "$(type -t apply_candidate)" == "function" ]]
[[ "$(type -t show_status)" == "function" ]]
[[ "$(type -t bbr_status)" == "function" ]]

rm -rf "$APP_DIR"
echo "All modules loaded and required functions are present."
