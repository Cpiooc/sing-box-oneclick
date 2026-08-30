#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

SCRIPT_VERSION="test"
REPO="Cpiooc/sing-box-oneclick"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
REPO_API="https://api.github.com/repos/${REPO}"
APP_DIR="$work/app"
CONFIG_DIR="$work/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
STATE_FILE="$APP_DIR/state.json"
BACKUP_DIR="$APP_DIR/backups"
NODE_INFO="$work/node-info.txt"
MANAGER_DIR="$work/manager"
MANAGER_FILE="$MANAGER_DIR/install.sh"
MANAGER_LINK="$work/sb"
BBR_SYSCTL="$work/bbr.conf"
FAIL2BAN_JAIL="$work/fail2ban.conf"
CERTBOT_HOOK="$work/certbot-hook.sh"
SUBSCRIPTION_CONFIG="$APP_DIR/subscription-nginx.conf"
SUBSCRIPTION_UNIT="$APP_DIR/subscription.service"
SUBSCRIPTION_PUBLISH_DIR="$APP_DIR/subscription-publish"
SUBSCRIPTION_RUNTIME_DIR="$APP_DIR/subscription-run"
SUBSCRIPTION_CERTBOT_HOOK="$APP_DIR/subscription-certbot-hook.sh"
SUBSCRIPTION_USER="$(id -un)"
HY2_HOP_UNIT="$APP_DIR/hy2-hop.service"
C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_WHITE=''; C_MAGENTA=''; C_GRAY=''

for module in common ui protocols tuic security maintenance tls-manager tls-safe runtime editor extra-protocols client-export client-extra hy2-hop subscription subscription-hooks views views-extra usability firewall-v17 menu; do
  # shellcheck source=/dev/null
  source "$root/lib/${module}.sh"
done

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "$MANAGER_DIR"
cat > "$STATE_FILE" <<'JSON'
{
  "version": 1,
  "nodes": {
    "ss": {
      "name": "sing-box-Shadowsocks",
      "type": "Shadowsocks",
      "address": "ss.example.com",
      "port": 8388,
      "method": "2022-blake3-aes-128-gcm",
      "password": "very-secret-password",
      "uri": "ss://very-secret",
      "firewall": "both",
      "tls_enabled": false,
      "certificate": false
    }
  }
}
JSON
chmod 600 "$STATE_FILE"

masked=$(mask_secret 'abcdefghijklmnop')
[[ "$masked" != 'abcdefghijklmnop' ]]
[[ "$masked" == abcd*mnop ]]

cat > "$work/redact.json" <<'JSON'
{"uuid":"1234","password":"secret","uri":"scheme://secret","nested":{"token":"abc","safe":"ok"}}
JSON
redacted=$(redact_json_for_diff "$work/redact.json")
[[ $(jq -r '.uuid' <<< "$redacted") == '***REDACTED***' ]]
[[ $(jq -r '.password' <<< "$redacted") == '***REDACTED***' ]]
[[ $(jq -r '.uri' <<< "$redacted") == '***REDACTED***' ]]
[[ $(jq -r '.nested.token' <<< "$redacted") == '***REDACTED***' ]]
[[ $(jq -r '.nested.safe' <<< "$redacted") == 'ok' ]]

for i in $(seq -w 1 35); do
  mkdir -p "$BACKUP_DIR/20260101-0000${i}"
done
BACKUP_KEEP_COUNT=30
prune_backups true
[[ $(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 30 ]]

ufw_log="$work/ufw.log"
ufw() {
  if [[ ${1:-} == status ]]; then
    echo 'Status: active'
    return 0
  fi
  printf '%s\n' "$*" >> "$ufw_log"
}
reconcile_managed_ufw_rules
grep -Fxq 'allow 8388/tcp' "$ufw_log"
grep -Fxq 'allow 8388/udp' "$ufw_log"

declare -F doctor >/dev/null
declare -F backup_menu >/dev/null
declare -F reveal_nodes >/dev/null
declare -F firewall_setup_v17 >/dev/null
declare -F doctor_check_systemd_resilience >/dev/null
declare -F manager_check_update >/dev/null
declare -F manager_update_notice >/dev/null
[[ $(declare -f doctor) == *doctor_check_systemd_resilience* ]]
[[ $(declare -f main) == *'update|self-update'* ]]

local_commit=1111111111111111111111111111111111111111
remote_commit=$local_commit
printf '%s\n' "$local_commit" > "$MANAGER_DIR/COMMIT"
manager_remote_commit_quick() { printf '%s' "$remote_commit"; }

manager_check_update
[[ "$MANAGER_UPDATE_STATE" == current ]]
[[ "$MANAGER_LOCAL_COMMIT" == "$local_commit" ]]
[[ "$MANAGER_REMOTE_COMMIT" == "$remote_commit" ]]
[[ -z "$(manager_update_notice)" ]]

remote_commit=2222222222222222222222222222222222222222
manager_check_update
[[ "$MANAGER_UPDATE_STATE" == available ]]
manager_update_notice > "$work/update-notice.txt"
grep -Fq '管理脚本有更新' "$work/update-notice.txt"
grep -Fq '111111111111 → 222222222222' "$work/update-notice.txt"
grep -Fq 'sb update' "$work/update-notice.txt"

manager_remote_commit_quick() { return 1; }
manager_check_update
[[ "$MANAGER_UPDATE_STATE" == offline ]]
[[ -z "$(manager_update_notice)" ]]

SYSTEMD_ENABLED=enabled
SYSTEMD_RESTART=on-failure
SYSTEMD_RESTART_USEC=10s
systemctl() {
  case "${1:-}" in
    is-enabled)
      printf '%s\n' "$SYSTEMD_ENABLED"
      [[ "$SYSTEMD_ENABLED" == enabled ]]
      ;;
    show)
      case "${4:-}" in
        Restart) printf '%s\n' "$SYSTEMD_RESTART" ;;
        RestartUSec) printf '%s\n' "$SYSTEMD_RESTART_USEC" ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

DOCTOR_OK=0; DOCTOR_WARN=0; DOCTOR_FAIL=0
doctor_check_systemd_resilience > "$work/doctor-systemd-ok.txt"
[[ "$DOCTOR_OK" -eq 2 ]]
[[ "$DOCTOR_WARN" -eq 0 ]]
grep -Fq 'sing-box 开机自启：enabled' "$work/doctor-systemd-ok.txt"
grep -Fq 'sing-box 崩溃自动恢复：on-failure / 10s' "$work/doctor-systemd-ok.txt"

SYSTEMD_ENABLED=disabled
SYSTEMD_RESTART=no
DOCTOR_OK=0; DOCTOR_WARN=0; DOCTOR_FAIL=0
doctor_check_systemd_resilience > "$work/doctor-systemd-warn.txt"
[[ "$DOCTOR_OK" -eq 0 ]]
[[ "$DOCTOR_WARN" -eq 2 ]]
grep -Fq 'systemctl enable sing-box' "$work/doctor-systemd-warn.txt"
grep -Fq '安装 / 修复 sing-box' "$work/doctor-systemd-warn.txt"

echo "Masking, redacted diff, backup retention, TCP+UDP UFW, update reminder and doctor systemd resilience checks passed."
