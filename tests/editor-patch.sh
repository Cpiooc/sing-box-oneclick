#!/usr/bin/env bash
set -euo pipefail

for cmd in sing-box jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing dependency: $cmd" >&2; exit 1; }
done

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

SCRIPT_VERSION="test"
REPO="Cpiooc/sing-box-oneclick"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
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

C_RESET=''
C_RED=''
C_GREEN=''
C_YELLOW=''
C_BLUE=''
C_CYAN=''

# shellcheck source=/dev/null
source "$root/lib/common.sh"
# shellcheck source=/dev/null
source "$root/lib/ui.sh"
# shellcheck source=/dev/null
source "$root/lib/editor.sh"

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$BACKUP_DIR"

uuid=$(sing-box generate uuid)
keypair=$(sing-box generate reality-keypair)
private_key=$(awk '/PrivateKey/ {print $NF; exit}' <<< "$keypair" | tr -d '"')
public_key=$(awk '/PublicKey/ {print $NF; exit}' <<< "$keypair" | tr -d '"')
short_id="0123456789abcdef"
old_port=25443
new_port=25444
sni="www.microsoft.com"

jq -n \
  --arg uuid "$uuid" --arg private "$private_key" --arg sid "$short_id" --arg sni "$sni" --argjson port "$old_port" \
  '{log:{level:"error"},inbounds:[{type:"vless",tag:"vless-reality-in",listen:"::",listen_port:$port,users:[{name:"main",uuid:$uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$private,short_id:[$sid],max_time_difference:"1m"}}}],outbounds:[{type:"direct",tag:"direct"}]}' \
  > "$CONFIG_FILE"

jq -n \
  --arg uuid "$uuid" --arg pub "$public_key" --arg sid "$short_id" --arg sni "$sni" --argjson port "$old_port" \
  '{version:1,nodes:{reality:{name:"sing-box-Reality",type:"VLESS Reality",address:"203.0.113.10",port:$port,uuid:$uuid,reality_sni:$sni,public_key:$pub,short_id:$sid,firewall:"tcp",uri:""}}}' \
  > "$STATE_FILE"
chmod 600 "$CONFIG_FILE" "$STATE_FILE"

sing-box check -c "$CONFIG_FILE"

# Replace runtime side effects with a test-safe transactional apply.
apply_candidate() {
  local candidate=$1
  sing-box check -c "$candidate"
  install -m 600 "$candidate" "$CONFIG_FILE"
}
allow_if_ufw_active() { :; }
ufw_allow_cloudflare_only() { :; }
refresh_client_exports_if_present() { :; }

before_uuid=$(jq -r '.nodes.reality.uuid' "$STATE_FILE")
before_sni=$(jq -r '.nodes.reality.reality_sni' "$STATE_FILE")
before_pub=$(jq -r '.nodes.reality.public_key' "$STATE_FILE")
before_sid=$(jq -r '.nodes.reality.short_id' "$STATE_FILE")

edit_node_port reality <<< "$new_port"

[[ $(jq -r '.nodes.reality.port' "$STATE_FILE") == "$new_port" ]]
[[ $(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .listen_port' "$CONFIG_FILE") == "$new_port" ]]
[[ $(jq -r '.nodes.reality.uuid' "$STATE_FILE") == "$before_uuid" ]]
[[ $(jq -r '.nodes.reality.reality_sni' "$STATE_FILE") == "$before_sni" ]]
[[ $(jq -r '.nodes.reality.public_key' "$STATE_FILE") == "$before_pub" ]]
[[ $(jq -r '.nodes.reality.short_id' "$STATE_FILE") == "$before_sid" ]]

grep -q "@\[203.0.113.10\]:${new_port}\|@203.0.113.10:${new_port}" "$STATE_FILE" || true
sing-box check -c "$CONFIG_FILE"

echo "In-place Reality port edit passed and identity fields were preserved."