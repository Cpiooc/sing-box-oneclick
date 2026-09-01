#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

APP_DIR="${tmp}/app"
STATE_FILE="${APP_DIR}/state.json"
SUBSCRIPTION_CONFIG="${tmp}/subscription-nginx.conf"
SUBSCRIPTION_UNIT="${tmp}/subscription.service"
SUBSCRIPTION_PUBLISH_DIR="${tmp}/publish"
SUBSCRIPTION_RUNTIME_DIR="${tmp}/run"
SUBSCRIPTION_CERTBOT_HOOK="${tmp}/certbot-hook.sh"
SUBSCRIPTION_USER="$(id -un)"
CLIENT_EXPORT_DIR="${tmp}/exports"
CLIENT_EXPORT_MARKER="${CLIENT_EXPORT_DIR}/.auto-refresh"
C_RESET=''
C_RED=''
C_GREEN=''
C_YELLOW=''
C_BLUE=''
C_CYAN=''
C_BOLD=''
C_DIM=''
C_WHITE=''
C_MAGENTA=''

# Minimal UI helpers used by the subscription readiness/diagnostic layer.
note() { :; }
warn() { :; }

# Deliberately do NOT pre-create SUBSCRIPTION_RUNTIME_DIR. A fresh VPS has no
# /run/sing-box-oneclick-subscription before the dedicated service first starts.
mkdir -p "$APP_DIR" "$SUBSCRIPTION_PUBLISH_DIR" "$CLIENT_EXPORT_DIR"
printf '%s\n' '{"version":1,"nodes":{}}' > "$STATE_FILE"

# shellcheck source=/dev/null
source "${root}/lib/subscription.sh"
# shellcheck source=/dev/null
source "${root}/lib/subscription-hooks.sh"

cert="${tmp}/cert.pem"
key="${tmp}/key.pem"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 1 \
  -keyout "$key" -out "$cert" -subj '/CN=sub.example.com' \
  -addext 'subjectAltName=DNS:sub.example.com' >/dev/null 2>&1

touch "${SUBSCRIPTION_PUBLISH_DIR}/sing-box-client.json"
touch "${SUBSCRIPTION_PUBLISH_DIR}/mihomo.yaml"
touch "${SUBSCRIPTION_PUBLISH_DIR}/v2rayn-subscription.txt"
touch "${SUBSCRIPTION_PUBLISH_DIR}/v2rayn-subscription-base64.txt"

token="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
write_subscription_nginx_config "sub.example.com" 9443 "$token" "$cert" "$key" "$SUBSCRIPTION_USER"
[[ ! -d "$SUBSCRIPTION_RUNTIME_DIR" ]]
validate_subscription_nginx_config
[[ -d "$SUBSCRIPTION_RUNTIME_DIR" ]]

grep -Fq 'ssl_protocols TLSv1.2 TLSv1.3;' "$SUBSCRIPTION_CONFIG"
grep -Fq 'ssl_session_tickets off;' "$SUBSCRIPTION_CONFIG"
grep -Fq 'Cache-Control "no-store, no-cache, must-revalidate"' "$SUBSCRIPTION_CONFIG"
grep -Fq 'access_log off;' "$SUBSCRIPTION_CONFIG"
grep -Fq 'error_log stderr error;' "$SUBSCRIPTION_CONFIG"
grep -Fq 'log_not_found off;' "$SUBSCRIPTION_CONFIG"
! grep -Fq 'access_log /dev/stdout combined;' "$SUBSCRIPTION_CONFIG"
grep -Fq "location = /${token}/sing-box" "$SUBSCRIPTION_CONFIG"
grep -Fq "location = /${token}/mihomo" "$SUBSCRIPTION_CONFIG"
grep -Fq "location = /${token}/v2rayn" "$SUBSCRIPTION_CONFIG"
grep -Fq 'location / {' "$SUBSCRIPTION_CONFIG"
grep -Fq 'return 404;' "$SUBSCRIPTION_CONFIG"

# Regression: Type=simple can report active before the first HTTPS request is
# actually ready. The health check must retry instead of failing on one curl.
health_curl_attempts=0
systemctl() {
  [[ ${1:-} == is-active ]] && return 0
  return 0
}
ss() {
  printf '%s\n' 'LISTEN 0 511 0.0.0.0:9443 0.0.0.0:*'
}
curl() {
  health_curl_attempts=$((health_curl_attempts + 1))
  (( health_curl_attempts >= 3 ))
}
sleep() { :; }

subscription_local_healthcheck "sub.example.com" 9443 "$token"
[[ "$health_curl_attempts" -eq 3 ]]

printf 'HTTPS subscription nginx configuration and delayed-readiness checks passed.\n'
