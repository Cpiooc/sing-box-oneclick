#!/usr/bin/env bash
set -euo pipefail

for cmd in sing-box jq base64; do
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

source "$root/lib/common.sh"
source "$root/lib/ui.sh"
source "$root/lib/editor.sh"
source "$root/lib/extra-protocols.sh"

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$BACKUP_DIR"

ss16=$(ss_password_for_method 2022-blake3-aes-128-gcm)
ss32=$(ss_password_for_method 2022-blake3-aes-256-gcm)
[[ $(printf '%s' "$ss16" | base64 -d | wc -c) -eq 16 ]]
[[ $(printf '%s' "$ss32" | base64 -d | wc -c) -eq 32 ]]

jq -n --arg sskey "$ss16" '{version:1,nodes:{
  anytls:{name:"AnyTLS",address:"1.2.3.4",domain:"tls.example.com",port:8444,password:"anytls-pass",insecure:false,uri:""},
  trojan:{name:"Trojan",address:"trojan.example.com",domain:"trojan.example.com",port:8445,password:"trojan-pass",insecure:true,uri:""},
  ss:{name:"Shadowsocks",address:"ss.example.com",port:8388,method:"2022-blake3-aes-128-gcm",password:$sskey,uri:""}
}}' > "$STATE_FILE"
chmod 600 "$STATE_FILE"

rebuild_node_uri anytls
rebuild_node_uri trojan
rebuild_node_uri ss

jq -e '.nodes.anytls.uri | startswith("anytls://")' "$STATE_FILE" >/dev/null
jq -e '.nodes.trojan.uri | startswith("trojan://")' "$STATE_FILE" >/dev/null
jq -e '.nodes.trojan.uri | contains("allowInsecure=1")' "$STATE_FILE" >/dev/null
jq -e '.nodes.ss.uri | startswith("ss://")' "$STATE_FILE" >/dev/null
jq -e '.nodes.ss.uri | contains("2022-blake3-aes-128-gcm")' "$STATE_FILE" >/dev/null

[[ $(node_tag_for_key anytls) == anytls-in ]]
[[ $(node_tag_for_key trojan) == trojan-in ]]
[[ $(node_tag_for_key ss) == shadowsocks-in ]]
[[ $(node_proto_for_key anytls) == tcp ]]
[[ $(node_proto_for_key trojan) == tcp ]]
[[ $(node_label_for_key ss) == Shadowsocks ]]

current=$(singbox_version_number)
version_ge "$current" 1.12.0

echo "AnyTLS/Trojan/Shadowsocks regression checks passed."
