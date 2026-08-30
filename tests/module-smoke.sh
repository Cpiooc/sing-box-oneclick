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
SUBSCRIPTION_CONFIG="${APP_DIR}/subscription-nginx.conf"
SUBSCRIPTION_UNIT="${APP_DIR}/subscription.service"
SUBSCRIPTION_PUBLISH_DIR="${APP_DIR}/subscription-publish"
SUBSCRIPTION_RUNTIME_DIR="${APP_DIR}/subscription-run"
SUBSCRIPTION_CERTBOT_HOOK="${APP_DIR}/subscription-certbot-hook.sh"
SUBSCRIPTION_USER="$(id -un)"

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
  editor.sh
  extra-protocols.sh
  client-export.sh
  client-extra.sh
  subscription.sh
  subscription-hooks.sh
  views.sh
  views-extra.sh
  menu.sh
)

for module in "${modules[@]}"; do
  # shellcheck source=/dev/null
  source "${root}/lib/${module}"
done

required=(
  main menu ui_banner ui_dashboard ui_node_overview ui_cli_help ui_group ui_item ui_group_end
  deploy_reality deploy_hysteria2 deploy_tuic deploy_cloudflare_ws
  deploy_anytls deploy_trojan deploy_shadowsocks
  switch_certificate_tls select_certificate_mode
  edit_node_parameters edit_node_port edit_ss_port rebuild_node_uri
  client_export_menu export_singbox_client export_mihomo_client export_v2rayn_subscription
  generate_all_client_exports refresh_client_exports_if_present
  subscription_menu enable_https_subscription show_https_subscription_status
  show_subscription_urls rotate_subscription_token refresh_https_subscription disable_https_subscription
  write_subscription_nginx_config publish_subscription_payloads subscription_enabled
  apply_candidate apply_runtime_change singbox_can_reload
  show_status show_nodes show_qr_codes show_logs network_diagnostics
  bbr_status certificate_status security_audit
  backup_now restore_backup safe_update_singbox self_update firewall_setup_v16
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
[[ "$(type -t edit_node_parameters)" == "function" ]]
[[ "$(type -t generate_all_client_exports)" == "function" ]]
[[ "$(type -t subscription_menu)" == "function" ]]
[[ "$(type -t deploy_anytls)" == "function" ]]
[[ "$(type -t deploy_trojan)" == "function" ]]
[[ "$(type -t deploy_shadowsocks)" == "function" ]]

rm -rf "$APP_DIR"
echo "All modules loaded and required functions are present."
