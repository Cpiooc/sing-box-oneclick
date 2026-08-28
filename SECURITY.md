# Security

## Sensitive information

Do **not** commit any of the following to this repository or to a public issue:

- Reality private keys
- Hysteria2 passwords / obfuscation passwords
- VLESS UUIDs or complete private share links you intend to keep secret
- Cloudflare API tokens / Global API Keys
- SSH private keys or VPS passwords
- `/etc/sing-box/config.json` copied from a live server
- `/etc/sing-box-oneclick/state.json` copied from a live server

The installer generates node credentials locally on the VPS. They are not intentionally uploaded to GitHub.

## Reporting a security issue

If you find a security problem, avoid posting live credentials or server addresses in a public issue. Reproduce the problem with placeholder values whenever possible.

## Design principles

- Candidate sing-box configurations are checked before replacing the active configuration.
- Existing configuration/state are backed up before changes.
- A failed restart triggers an automatic rollback attempt.
- Sensitive local files are written with restrictive permissions.
- The script does not automatically disable SSH password/root login or change the SSH port, because doing so can lock the administrator out of the VPS.
- The script does not replace the VPS kernel merely to enable BBR.
- Cloudflare API credentials are not required by the installer.

## `curl | bash`

The one-line install command is convenient, but it executes the current `main` branch as root. For higher assurance, download and inspect the script first:

```bash
curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh -o install.sh
bash -n install.sh
less install.sh
sudo bash install.sh
```
