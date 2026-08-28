#!/usr/bin/env bash
set -euo pipefail

for cmd in sing-box jq openssl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing dependency: $cmd" >&2; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -keyout "$work/key.pem" -out "$work/cert.pem" \
  -subj '/CN=example.com' -addext 'subjectAltName=DNS:example.com' >/dev/null 2>&1

uuid=$(sing-box generate uuid)
short_id=$(sing-box generate rand --hex 8)
keypair=$(sing-box generate reality-keypair)
private_key=$(awk '/PrivateKey/ {print $NF; exit}' <<< "$keypair" | tr -d '"')

jq -n \
  --arg uuid "$uuid" --arg private_key "$private_key" --arg short_id "$short_id" \
  '{log:{level:"error"},inbounds:[{type:"vless",tag:"vless-reality-in",listen:"::",listen_port:24443,users:[{name:"main",uuid:$uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:"www.microsoft.com",reality:{enabled:true,handshake:{server:"www.microsoft.com",server_port:443},private_key:$private_key,short_id:[$short_id],max_time_difference:"1m"}}}],outbounds:[{type:"direct",tag:"direct"}]}' \
  > "$work/reality.json"

jq -n \
  --arg cert "$work/cert.pem" --arg key "$work/key.pem" \
  '{log:{level:"error"},inbounds:[{type:"hysteria2",tag:"hysteria2-in",listen:"::",listen_port:24444,users:[{name:"main",password:"test-password"}],obfs:{type:"salamander",password:"test-obfs-password"},tls:{enabled:true,server_name:"example.com",certificate_path:$cert,key_path:$key},masquerade:"https://www.microsoft.com"}],outbounds:[{type:"direct",tag:"direct"}]}' \
  > "$work/hysteria2.json"

jq -n \
  --arg uuid "$uuid" --arg cert "$work/cert.pem" --arg key "$work/key.pem" \
  '{log:{level:"error"},inbounds:[{type:"vless",tag:"vless-ws-tls-in",listen:"::",listen_port:24445,users:[{name:"main",uuid:$uuid}],tls:{enabled:true,server_name:"example.com",certificate_path:$cert,key_path:$key},transport:{type:"ws",path:"/ci-test"}}],outbounds:[{type:"direct",tag:"direct"}]}' \
  > "$work/ws-tls.json"

jq -n \
  --arg uuid "$uuid" \
  '{log:{level:"error"},inbounds:[{type:"vless",tag:"vless-ws-plain-in",listen:"::",listen_port:24447,users:[{name:"main",uuid:$uuid}],transport:{type:"ws",path:"/ci-test-plain"}}],outbounds:[{type:"direct",tag:"direct"}]}' \
  > "$work/ws-no-tls.json"

jq -n \
  --arg uuid "$uuid" --arg cert "$work/cert.pem" --arg key "$work/key.pem" \
  '{log:{level:"error"},inbounds:[{type:"tuic",tag:"tuic-in",listen:"::",listen_port:24446,users:[{name:"main",uuid:$uuid,password:"test-tuic-password"}],congestion_control:"bbr",auth_timeout:"3s",zero_rtt_handshake:false,heartbeat:"10s",tls:{enabled:true,server_name:"example.com",alpn:["h3"],certificate_path:$cert,key_path:$key}}],outbounds:[{type:"direct",tag:"direct"}]}' \
  > "$work/tuic.json"

for config in "$work"/*.json; do
  echo "==> sing-box check: $(basename "$config")"
  sing-box check -c "$config"
done

echo "All representative sing-box configurations passed."
