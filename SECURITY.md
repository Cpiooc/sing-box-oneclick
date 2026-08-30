# Security

## Sensitive information

Do **not** commit or post any live credentials to this repository, public issues, forums, screenshots, or third-party conversion services. This includes:

- Reality private/public key material, UUIDs and Short IDs used by a live node
- Hysteria2 / AnyTLS / Trojan passwords and Hysteria2 obfuscation passwords
- Shadowsocks keys
- complete private share links or QR codes
- HTTPS subscription Tokens or complete subscription URLs
- Cloudflare API tokens / Global API Keys
- SSH private keys or VPS passwords
- live `/etc/sing-box/config.json`
- live `/etc/sing-box-oneclick/state.json`
- live `/etc/sing-box-oneclick/exports/`

Credentials are generated locally on the VPS. The project does not intentionally upload them to GitHub or send them to a third-party subscription converter.

## Safe display defaults

`sb nodes` is intentionally a **masked** view. UUIDs, passwords/keys and complete share URIs are not printed in full by default.

Use `sb reveal` only when you intentionally need complete credentials. `sb qr` also exposes the complete node credential through the QR payload and displays a warning first.

The full local node information file remains root-only (`600`).

## Manager update integrity

v1.7 manager updates are designed to avoid mixing files from different moments on the moving `main` branch:

1. resolve `main` to one exact 40-character Git commit SHA;
2. download every manager file from that same commit;
3. require an entry for every bundle file in `SHA256SUMS`;
4. verify the downloaded bytes with SHA-256;
5. run Bash syntax checks;
6. install into a commit-specific release directory;
7. atomically switch the stable manager symlink only after verification succeeds.

`sb doctor` can re-check the installed manager files against `SHA256SUMS`.

SHA-256 protects bundle consistency and detects corruption/tampering relative to the repository manifest. It is **not an independent code-signing scheme**: the GitHub repository/account and HTTPS delivery remain part of the trust chain.

## Backups and safe diff

Important configuration changes create a local backup before applying the new configuration. v1.7 keeps the most recent 30 backups by default.

The built-in backup Diff redacts fields whose names contain credential-like keys such as password, UUID, private/public key, Short ID, Token and URI before printing differences. Do not assume arbitrary user-added fields are automatically secret; review custom configuration carefully.

## `sb doctor`

`sb doctor` is read-only by design. It reports health and consistency problems but does not automatically restart sing-box, alter firewall rules or rewrite node configuration.

Checks include service/config health, state/config port drift, permissions, certificates, UFW, time sync, HTTPS subscription service, HY2 port-hopping redirect state, backup count and manager SHA-256 integrity.

## Hysteria2 port hopping

HY2 port hopping is optional and disabled by default. When enabled, the script creates a Linux nftables/iptables UDP redirect from the configured hopping range to the real Hysteria2 listen port.

Security considerations:

- the VPS provider Security Group / cloud firewall must allow the chosen UDP range;
- a larger range increases exposed UDP surface, so the script limits one configured range to at most 20,000 ports;
- existing local UDP listeners inside the selected range are rejected during setup;
- disabling/removing HY2 removes the script-managed redirect rules and persistence unit;
- port hopping is a workaround for per-port UDP throttling/blocking, not a general speed or security feature.

## HTTPS private subscription

The optional HTTPS subscription service uses bearer-style random URLs. Treat the full URL exactly like a password.

Security properties include:

- HTTPS only, using TLS 1.2 / TLS 1.3;
- 256-bit random access Token generated with OpenSSL;
- exact subscription paths; unknown paths return 404;
- GET / HEAD only;
- `Cache-Control: no-store` and related anti-cache headers;
- Nginx access logging disabled so the Token is not persisted in normal access logs;
- request/connection limits per client IP;
- dedicated low-privilege Nginx worker;
- original exports remain root-only; the Web worker sees restricted publish copies only;
- publish copies are deleted when the service is disabled;
- Token rotation invalidates old URLs after successful reload;
- self-signed / intentionally untrusted certificates are not accepted for normal HTTPS subscription setup.

A CDN that terminates HTTPS can still observe the requested URL. If that is outside your threat model, use DNS-only/direct subscription mode instead.

## Design principles

- Candidate sing-box configurations are checked before replacing active configuration.
- Configuration/state are backed up before important changes.
- Failed runtime apply triggers an automatic rollback attempt.
- Sensitive files use restrictive permissions.
- Reload is preferred when supported; restart is the fallback. Reload may still reset some active connections.
- UFW setup preserves detected SSH ports and does not blindly reset the firewall.
- Nodes marked `firewall: both`, such as Shadowsocks, are reconciled as both TCP and UDP.
- The script does not automatically disable SSH password/root login, change the SSH port, replace the VPS kernel, reboot the VPS, or install a restart watchdog.
- Cloudflare API credentials are not required.
- The HTTPS subscription service does not take over an existing Nginx site; it runs as a separate systemd-managed Nginx instance.

## Reporting a security issue

Avoid posting live credentials, complete subscription URLs, QR codes or server secrets in a public issue. Reproduce problems with placeholder values whenever possible.

## One-line installer

The one-line command executes the bootstrap `install.sh` as root. v1.7 then locks the actual manager bundle to a commit and verifies `SHA256SUMS`, but users who want to inspect the bootstrap itself can still use:

```bash
curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh -o install.sh
bash -n install.sh
less install.sh
sudo bash install.sh
```
