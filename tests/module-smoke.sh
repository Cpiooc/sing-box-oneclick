#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

SCRIPT_VERSION="test"
REPO="Cpiooc/sing-box-oneclick"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
REPO_API="https://api.github.com/repos/${REPO}"
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
BBR_STATE_FILE="${APP_DIR}/bbr-state.json"
CORE_STATE_DIR="${APP_DIR}/core-manager"
CORE_BACKUP_DIR="${CORE_STATE_DIR}/backups"
FAIL2BAN_JAIL="${APP_DIR}/fail2ban.conf"
CERTBOT_HOOK="${APP_DIR}/certbot-hook.sh"
SUBSCRIPTION_CONFIG="${APP_DIR}/subscription-nginx.conf"
SUBSCRIPTION_UNIT="${APP_DIR}/subscription.service"
SUBSCRIPTION_PUBLISH_DIR="${APP_DIR}/subscription-publish"
SUBSCRIPTION_RUNTIME_DIR="${APP_DIR}/subscription-run"
SUBSCRIPTION_CERTBOT_HOOK="${APP_DIR}/subscription-certbot-hook.sh"
SUBSCRIPTION_USER="$(id -un)"
HY2_HOP_UNIT="${APP_DIR}/hy2-hop.service"

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
  bbr-manager.sh
  maintenance.sh
  core-manager.sh
  tls-manager.sh
  tls-safe.sh
  runtime.sh
  editor.sh
  extra-protocols.sh
  client-export.sh
  client-extra.sh
  hy2-hop.sh
  subscription.sh
  subscription-hooks.sh
  views.sh
  views-extra.sh
  usability.sh
  firewall-v17.sh
  menu.sh
  cert-pinning.sh
)

for module in "${modules[@]}"; do
  # shellcheck source=/dev/null
  source "${root}/lib/${module}"
done

required=(
  main menu ui_banner ui_dashboard ui_node_overview ui_cli_help ui_group ui_item ui_group_end
  manager_local_commit manager_remote_commit_quick manager_check_update manager_update_notice
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
  show_status show_nodes reveal_nodes show_qr_codes show_logs network_diagnostics
  enable_bbr disable_bbr bbr_status bbr_menu bbr_cli certificate_status security_audit doctor
  core_current_version core_latest_stable_version core_install_version core_update_latest core_rollback core_list_versions core_status core_menu core_cli
  backup_now backup_menu backup_diff prune_backups restore_backup safe_update_singbox self_update
  firewall_setup_v17 reconcile_managed_ufw_rules
  hy2_port_hopping_menu hy2_hop_cli hy2_hop_status hy2_hop_apply_from_state
  certificate_spki_sha256_base64 certificate_sha256_hex certificate_sha256_colon
  cert_pinning_migrate_all cert_pinning_show_node_guidance cert_pinning_export_certificates
)

for fn in "${required[@]}"; do
  declare -F "$fn" >/dev/null || {
    echo "missing function after module load: $fn" >&2
    exit 1
  }
done

[[ "$(type -t apply_candidate)" == "function" ]]
[[ "$(type -t show_status)" == "function" ]]
[[ "$(type -t doctor)" == "function" ]]
[[ "$(type -t bbr_cli)" == "function" ]]
[[ "$(type -t core_cli)" == "function" ]]
[[ "$(type -t edit_node_parameters)" == "function" ]]
[[ "$(type -t generate_all_client_exports)" == "function" ]]
[[ "$(type -t subscription_menu)" == "function" ]]
[[ "$(type -t deploy_anytls)" == "function" ]]
[[ "$(type -t deploy_trojan)" == "function" ]]
[[ "$(type -t deploy_shadowsocks)" == "function" ]]
[[ "$(type -t hy2_port_hopping_menu)" == "function" ]]
[[ "$(type -t manager_check_update)" == "function" ]]
[[ "$(type -t cert_pinning_migrate_all)" == "function" ]]

rm -rf "$APP_DIR"
echo "All v1.8.3 modules loaded and required functions are present."
