#!/usr/bin/env bash
set -euo pipefail

for cmd in sing-box jq openssl base64; do
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
# shellcheck source=/dev/null
source "$root/lib/client-export.sh"

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$BACKUP_DIR"

uuid1=$(sing-box generate uuid)
uuid2=$(sing-box generate uuid)
uuid3=$(sing-box generate uuid)
keypair=$(sing-box generate reality-keypair)
public_key=$(awk '/PublicKey/ {print $NF; exit}' <<< "$keypair" | tr -d '"')

jq -n \
  --arg uuid1 "$uuid1" --arg uuid2 "$uuid2" --arg uuid3 "$uuid3" --arg pub "$public_key" \
  '{
    version:1,
    nodes:{
      reality:{
        name:"sing-box-Reality",type:"VLESS Reality",address:"reality.example.com",port:443,
        uuid:$uuid1,reality_sni:"www.microsoft.com",public_key:$pub,short_id:"0123456789abcdef",
        firewall:"tcp",uri:""
      },
      hy2:{
        name:"sing-box-Hysteria2",type:"Hysteria2",address:"hy2.example.com",domain:"hy2.example.com",port:443,
        password:"test-hy2-password",obfs_password:"test-obfs-password",firewall:"udp",certificate:true,
        tls_enabled:true,certificate_mode:"self-signed",insecure:true,uri:""
      },
      tuic:{
        name:"sing-box-TUIC",type:"TUIC v5",address:"tuic.example.com",domain:"tuic.example.com",port:8443,
        uuid:$uuid2,password:"test-tuic-password",congestion_control:"bbr",firewall:"udp",certificate:true,
        tls_enabled:true,certificate_mode:"self-signed",insecure:true,uri:""
      },
      ws:{
        name:"sing-box-CF-WS",type:"VLESS WebSocket (Cloudflare)",address:"ws.example.com",domain:"ws.example.com",port:8443,
        uuid:$uuid3,path:"/ci-test",firewall:"tcp",cloudflare:true,certificate:true,tls_enabled:true,
        certificate_mode:"acme",insecure:false,uri:""
      }
    }
  }' > "$STATE_FILE"
chmod 600 "$STATE_FILE"

CLIENT_EXPORT_QUIET=true
generate_all_client_exports

exports="$APP_DIR/exports"
for f in sing-box-client.json mihomo.yaml v2rayn-subscription.txt v2rayn-subscription-base64.txt README.txt; do
  [[ -s "$exports/$f" ]] || { echo "missing export: $f" >&2; exit 1; }
done

sing-box check -c "$exports/sing-box-client.json"

grep -q 'reality-opts:' "$exports/mihomo.yaml"
grep -q 'type: hysteria2' "$exports/mihomo.yaml"
grep -q 'type: tuic' "$exports/mihomo.yaml"
grep -q 'network: ws' "$exports/mihomo.yaml"

[[ $(wc -l < "$exports/v2rayn-subscription.txt") -eq 4 ]]
grep -q '^vless://' "$exports/v2rayn-subscription.txt"
grep -q '^hysteria2://' "$exports/v2rayn-subscription.txt"
grep -q '^tuic://' "$exports/v2rayn-subscription.txt"

for f in sing-box-client.json mihomo.yaml v2rayn-subscription.txt v2rayn-subscription-base64.txt README.txt; do
  [[ $(stat -c '%a' "$exports/$f") == 600 ]] || { echo "bad permissions: $f" >&2; exit 1; }
done
[[ $(stat -c '%a' "$exports") == 700 ]]

echo "Client export files generated and validated successfully."