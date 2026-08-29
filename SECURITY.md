# Security

## Sensitive information

Do **not** commit any of the following to this repository or to a public issue:

- Reality private keys
- Hysteria2 passwords / obfuscation passwords
- VLESS UUIDs or complete private share links you intend to keep secret
- HTTPS subscription Tokens or complete subscription URLs
- Cloudflare API tokens / Global API Keys
- SSH private keys or VPS passwords
- `/etc/sing-box/config.json` copied from a live server
- `/etc/sing-box-oneclick/state.json` copied from a live server
- `/etc/sing-box-oneclick/exports/` copied from a live server

The installer generates node credentials and HTTPS subscription Tokens locally on the VPS. They are not intentionally uploaded to GitHub or sent to a third-party subscription converter.

## HTTPS private subscription

The optional HTTPS subscription service is designed around bearer-style random URLs. Treat the full URL exactly like a password.

Security properties include:

- HTTPS only, using TLS 1.2 / TLS 1.3.
- A 256-bit random access Token generated with OpenSSL.
- Exact subscription paths; unknown paths return 404.
- GET / HEAD only for subscription resources.
- `Cache-Control: no-store` and related anti-cache headers.
- Nginx access logging disabled so the Token is not persisted in normal access logs / journald.
- Request and connection limits per client IP.
- A dedicated low-privilege Nginx worker user.
- Original exports remain root-only; the Web worker only sees restricted publish copies.
- Published copies are deleted when the HTTPS subscription service is disabled.
- Token rotation invalidates the old URLs immediately after a successful reload.
- Self-signed / intentionally untrusted certificates are not accepted for normal HTTPS subscription setup.

Cloudflare or another CDN may still observe the requested URL when it terminates HTTPS at the edge. If that is not acceptable for your threat model, use DNS-only/direct mode instead.

## Reporting a security issue

If you find a security problem, avoid posting live credentials, full subscription URLs, Tokens, or server addresses in a public issue. Reproduce the problem with placeholder values whenever possible.

## Design principles

- Candidate sing-box configurations are checked before replacing the active configuration.
- Existing configuration/state are backed up before changes.
- A failed runtime apply triggers an automatic rollback attempt.
- Sensitive local files are written with restrictive permissions.
- The script prefers reload when supported and falls back to restart.
- The script does not automatically disable SSH password/root login or change the SSH port, because doing so can lock the administrator out of the VPS.
- The script does not replace the VPS kernel merely to enable BBR.
- Cloudflare API credentials are not required by the installer.
- The HTTPS subscription service does not take over an existing Nginx site configuration; it runs as a separate systemd-managed Nginx instance.

## `curl | bash`

The one-line install command is convenient, but it executes the current `main` branch as root. For higher assurance, download and inspect the script first:

```bash
curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh -o install.sh
bash -n install.sh
less install.sh
sudo bash install.sh
```
