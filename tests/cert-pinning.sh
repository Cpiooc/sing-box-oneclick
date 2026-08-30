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
BBR_STATE_FILE="$APP_DIR/bbr-state.json"
CORE_STATE_DIR="$APP_DIR/core-manager"
CORE_BACKUP_DIR="$CORE_STATE_DIR/backups"
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

modules=(
  common ui protocols tuic security bbr-manager maintenance core-manager tls-manager tls-safe runtime editor
  extra-protocols client-export client-extra hy2-hop subscription subscription-hooks views views-extra usability firewall-v17 menu cert-pinning
)
for module in "${modules[@]}"; do
  # shellcheck source=/dev/null
  source "$root/lib/${module}.sh"
done

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$BACKUP_DIR"
cert="$work/server.crt"
key="$work/server.key"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -keyout "$key" -out "$cert" -subj '/CN=203.0.113.10' \
  -addext 'subjectAltName=IP:203.0.113.10' >/dev/null 2>&1

spki=$(certificate_spki_sha256_base64 "$cert")
cert_hex=$(certificate_sha256_hex "$cert")
cert_colon=$(certificate_sha256_colon "$cert")
[[ -n "$spki" ]]
[[ "$cert_hex" =~ ^[0-9a-f]{64}$ ]]
[[ "$cert_colon" =~ ^([0-9A-F]{2}:){31}[0-9A-F]{2}$ ]]

jq -n \
  --arg cert "$cert" --arg key "$key" \
  '{
    version:1,
    nodes:{
      hy2:{name:"HY2 Pin",type:"Hysteria2",address:"203.0.113.10",domain:"203.0.113.10",port:443,password:"hy2-password",obfs_password:"obfs-password",uri:"hysteria2://old",firewall:"udp",certificate:true,tls_enabled:true,certificate_mode:"self-signed",certificate_path:$cert,key_path:$key,insecure:true},
      tuic:{name:"TUIC Pin",type:"TUIC v5",address:"203.0.113.10",domain:"203.0.113.10",port:8443,uuid:"11111111-1111-4111-8111-111111111111",password:"tuic-password",congestion_control:"bbr",uri:"tuic://old",firewall:"udp",certificate:true,tls_enabled:true,certificate_mode:"self-signed",certificate_path:$cert,key_path:$key,insecure:true},
      anytls:{name:"AnyTLS Pin",type:"AnyTLS",address:"203.0.113.10",domain:"203.0.113.10",port:8444,password:"anytls-password",uri:"anytls://old",firewall:"tcp",certificate:true,tls_enabled:true,certificate_mode:"self-signed",certificate_path:$cert,key_path:$key,insecure:true},
      trojan:{name:"Trojan Pin",type:"Trojan",address:"203.0.113.10",domain:"203.0.113.10",port:8445,password:"trojan-password",uri:"trojan://old",firewall:"tcp",certificate:true,tls_enabled:true,certificate_mode:"self-signed",certificate_path:$cert,key_path:$key,insecure:true},
      ws:{name:"CF WS",type:"VLESS WebSocket (Cloudflare)",address:"cf.example.com",domain:"cf.example.com",port:8443,uuid:"22222222-2222-4222-8222-222222222222",path:"/test",uri:"vless://old",firewall:"tcp",cloudflare:true,certificate:true,tls_enabled:true,certificate_mode:"self-signed",certificate_path:$cert,key_path:$key,insecure:true}
    }
  }' > "$STATE_FILE"
chmod 600 "$STATE_FILE"

# Avoid filesystem rendering noise; this test validates state and export behavior.
render_node_info() { :; }

cert_pinning_migrate_all

for node in hy2 tuic anytls trojan; do
  [[ $(jq -r --arg k "$node" '.nodes[$k].tls_verify_mode' "$STATE_FILE") == pin ]]
  [[ $(jq -r --arg k "$node" '.nodes[$k].insecure' "$STATE_FILE") == false ]]
  [[ $(jq -r --arg k "$node" '.nodes[$k].certificate_public_key_sha256' "$STATE_FILE") == "$spki" ]]
  [[ $(jq -r --arg k "$node" '.nodes[$k].certificate_sha256' "$STATE_FILE") == "$cert_hex" ]]
done
[[ $(jq -r '.nodes.ws.tls_verify_mode' "$STATE_FILE") == cloudflare-edge ]]
[[ $(jq -r '.nodes.ws.insecure' "$STATE_FILE") == false ]]

rebuild_node_uri hy2
hy2_uri=$(jq -r '.nodes.hy2.uri' "$STATE_FILE")
[[ "$hy2_uri" == *pinSHA256=* ]]
[[ "$hy2_uri" != *insecure=1* ]]

rebuild_node_uri trojan
trojan_uri=$(jq -r '.nodes.trojan.uri' "$STATE_FILE")
[[ "$trojan_uri" == *pcs=* ]]
[[ "$trojan_uri" != *allowInsecure=1* ]]
[[ "$trojan_uri" != *allow_insecure=1* ]]

for node in hy2 tuic anytls trojan; do
  outbound=$(singbox_outbound_for_key "$node")
  [[ $(jq -r '.tls.insecure' <<< "$outbound") == false ]]
  [[ $(jq -r '.tls.certificate_public_key_sha256[0]' <<< "$outbound") == "$spki" ]]
done

for node in hy2 tuic anytls trojan; do
  case "$node" in
    hy2) mihomo=$(write_mihomo_proxy_hy2) ;;
    tuic) mihomo=$(write_mihomo_proxy_tuic) ;;
    anytls) mihomo=$(write_mihomo_proxy_anytls) ;;
    trojan) mihomo=$(write_mihomo_proxy_trojan) ;;
  esac
  grep -Fq "fingerprint: '$cert_colon'" <<< "$mihomo"
  grep -Fq 'skip-cert-verify: false' <<< "$mihomo"
  ! grep -Fq 'skip-cert-verify: true' <<< "$mihomo"
done

# IP defaults must actually select self-signed, matching the beginner prompt.
select_def=$(declare -f select_certificate_mode)
[[ "$select_def" == *'default_choice=2'* ]]
[[ "$select_def" == *'自动启用证书 Pin'* ]]

cert_pinning_export_certificates
for node in hy2 tuic anytls trojan; do
  [[ -s "$CLIENT_EXPORT_CERT_DIR/${node}-server.crt" ]]
done

write_export_readme
grep -Fq "Do NOT manually enable 'skip certificate verification'" "$CLIENT_EXPORT_DIR/README.txt"
grep -Fq 'sing-box client requires >= 1.13' "$CLIENT_EXPORT_DIR/README.txt"
grep -Fq 'pinSHA256 is included' "$CLIENT_EXPORT_DIR/README.txt"
grep -Fq 'pcs is included' "$CLIENT_EXPORT_DIR/README.txt"

# Generated direct-TLS exports must not regress to the dangerous old defaults.
! grep -R -Fq 'skip-cert-verify: true' "$CLIENT_EXPORT_DIR" || { echo 'unexpected skip-cert-verify:true in exports' >&2; exit 1; }
! grep -R -Fq '"insecure":true' "$CLIENT_EXPORT_DIR" || { echo 'unexpected insecure:true in exports' >&2; exit 1; }

printf '%s\n' 'Certificate pinning, migration, client exports and beginner verification guidance passed.'
