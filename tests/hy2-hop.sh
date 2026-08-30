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
C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''

for module in common ui protocols tuic security maintenance tls-manager tls-safe runtime editor extra-protocols client-export client-extra hy2-hop firewall-v17; do
  # shellcheck source=/dev/null
  source "$root/lib/${module}.sh"
done

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$BACKUP_DIR"
cat > "$STATE_FILE" <<'JSON'
{
  "version": 1,
  "nodes": {
    "hy2": {
      "name": "sing-box-Hysteria2",
      "type": "Hysteria2",
      "address": "hy2.example.com",
      "domain": "hy2.example.com",
      "port": 443,
      "password": "test-password",
      "obfs_password": "test-obfs",
      "firewall": "udp",
      "certificate": true,
      "tls_enabled": true,
      "certificate_mode": "acme",
      "insecure": false,
      "uri": "",
      "port_hopping": {
        "enabled": true,
        "range_start": 20000,
        "range_end": 30000,
        "hop_interval": 30,
        "backend": "nft"
      }
    }
  }
}
JSON
chmod 600 "$STATE_FILE"

rebuild_node_uri hy2
uri=$(jq -r '.nodes.hy2.uri' "$STATE_FILE")
[[ "$uri" == hysteria2://* ]]
[[ "$uri" == *':20000-30000/'* ]]
[[ "$uri" == *'obfs=salamander'* ]]

outbound=$(singbox_outbound_for_key hy2)
[[ $(jq -r '.server_ports[0]' <<< "$outbound") == '20000:30000' ]]
[[ $(jq -r '.hop_interval' <<< "$outbound") == '30s' ]]
[[ $(jq 'has("server_port")' <<< "$outbound") == false ]]

jq -n --argjson outbound "$outbound" '{
  log:{level:"error"},
  dns:{servers:[{type:"local",tag:"local"}],final:"local"},
  inbounds:[{type:"mixed",tag:"mixed-in",listen:"127.0.0.1",listen_port:2080}],
  outbounds:[$outbound,{type:"direct",tag:"direct"}],
  route:{final:"proxy-hy2",default_domain_resolver:"local",auto_detect_interface:true}
}' > "$work/hy2-hop-client.json"
sing-box check -c "$work/hy2-hop-client.json"

mihomo=$(write_mihomo_proxy_hy2)
grep -q '^    ports: 20000-30000$' <<< "$mihomo"
grep -q '^    hop-interval: 30$' <<< "$mihomo"

a=$(hy2_hop_nft_config 20000 30000 443)
grep -q 'udp dport 20000-30000 redirect to :443' <<< "$a"

echo "Hysteria2 port hopping URI, sing-box schema, Mihomo export and nftables rule passed."
