#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

APP_DIR="$work/app"
CONFIG_FILE="$work/config.json"
CORE_STATE_DIR="$work/core-manager"
CORE_BACKUP_DIR="$CORE_STATE_DIR/backups"
C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_DIM=''; C_BOLD=''; C_MAGENTA=''
cleanup_files=()

have() { command -v "$1" >/dev/null 2>&1; }
info() { :; }
warn() { :; }
err() { :; }
note() { :; }
headmsg() { :; }
ui_kv() { :; }
ui_group() { :; }
ui_item() { :; }
ui_group_end() { :; }
install_deps() { :; }
backup_all() { :; }
download_checked_script() { cp "$work/fake-installer.sh" "$2"; }

# shellcheck source=/dev/null
source "$root/lib/core-manager.sh"

# Version normalization.
[[ $(core_normalize_version 1.13.19) == 1.13.19 ]]
[[ $(core_normalize_version v1.13.19) == 1.13.19 ]]
[[ $(core_normalize_version 1.14.0-rc.4) == 1.14.0-rc.4 ]]
! core_normalize_version '1.13' >/dev/null 2>&1
! core_normalize_version '../1.13.19' >/dev/null 2>&1

# GitHub release parsing: latest stable and prerelease detection.
core_api_get() {
  case "$1" in
    /releases/latest)
      printf '%s' '{"tag_name":"v1.13.19","draft":false,"prerelease":false}'
      ;;
    /releases/tags/v1.13.19)
      printf '%s' '{"tag_name":"v1.13.19","draft":false,"prerelease":false}'
      ;;
    /releases/tags/v1.14.0-rc.4)
      printf '%s' '{"tag_name":"v1.14.0-rc.4","draft":false,"prerelease":true}'
      ;;
    /releases\?per_page=40)
      printf '%s' '[{"tag_name":"v1.13.19","draft":false,"prerelease":false,"published_at":"2026-08-01T00:00:00Z"},{"tag_name":"v1.14.0-rc.4","draft":false,"prerelease":true,"published_at":"2026-08-30T00:00:00Z"}]'
      ;;
    *) return 1 ;;
  esac
}
[[ $(core_latest_stable_version) == 1.13.19 ]]
[[ $(core_release_kind 1.13.19) == stable ]]
[[ $(core_release_kind 1.14.0-rc.4) == prerelease ]]
core_release_exists 1.13.19

# Official installer must receive the exact supported --version argument.
cat > "$work/fake-installer.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$work/installer-args.txt"
EOF
chmod +x "$work/fake-installer.sh"
core_run_official_installer 1.13.19
[[ $(cat "$work/installer-args.txt") == '--version 1.13.19' ]]

# High-level transaction simulation.
MOCK_CURRENT_VERSION=1.13.18
RESTORE_COUNT=0
INSTALL_MODE=success
CONFIG_OK=1
RESTART_OK=1
LAST_INSTALL_TARGET=''

core_current_version() { printf '%s' "$MOCK_CURRENT_VERSION"; }
core_release_exists() { return 0; }
core_release_kind() { printf '%s' stable; }
core_confirm_version_change() { return 0; }
core_capture_snapshot() { printf '%s' "$work/snapshot-1.13.18"; }
core_run_official_installer() {
  LAST_INSTALL_TARGET=$1
  case "$INSTALL_MODE" in
    success) MOCK_CURRENT_VERSION=$1; return 0 ;;
    fail) return 1 ;;
    mismatch) MOCK_CURRENT_VERSION=9.9.9; return 0 ;;
  esac
}
core_config_check() { [[ "$CONFIG_OK" == 1 ]]; }
core_restart_if_configured() { [[ "$RESTART_OK" == 1 ]]; }
core_restore_after_failure() {
  RESTORE_COUNT=$((RESTORE_COUNT + 1))
  MOCK_CURRENT_VERSION=1.13.18
  return 0
}
core_status() { :; }

# Successful upgrade.
core_install_version 1.13.19
[[ "$MOCK_CURRENT_VERSION" == 1.13.19 ]]
[[ "$LAST_INSTALL_TARGET" == 1.13.19 ]]
[[ "$RESTORE_COUNT" == 0 ]]

# Config incompatibility after downgrade/update must restore old core.
MOCK_CURRENT_VERSION=1.13.18
CONFIG_OK=0
RESTORE_COUNT=0
if core_install_version 1.13.17; then
  echo 'expected config validation failure' >&2
  exit 1
fi
[[ "$RESTORE_COUNT" == 1 ]]
[[ "$MOCK_CURRENT_VERSION" == 1.13.18 ]]
CONFIG_OK=1

# Service failure must restore old core.
MOCK_CURRENT_VERSION=1.13.18
RESTART_OK=0
RESTORE_COUNT=0
if core_install_version 1.13.19; then
  echo 'expected service validation failure' >&2
  exit 1
fi
[[ "$RESTORE_COUNT" == 1 ]]
[[ "$MOCK_CURRENT_VERSION" == 1.13.18 ]]
RESTART_OK=1

# Installer failure must restore old core.
MOCK_CURRENT_VERSION=1.13.18
INSTALL_MODE=fail
RESTORE_COUNT=0
if core_install_version 1.13.19; then
  echo 'expected installer failure' >&2
  exit 1
fi
[[ "$RESTORE_COUNT" == 1 ]]
[[ "$MOCK_CURRENT_VERSION" == 1.13.18 ]]
INSTALL_MODE=success

# CLI explicit install dispatch.
MOCK_CURRENT_VERSION=1.13.18
core_cli install 1.13.19
[[ "$MOCK_CURRENT_VERSION" == 1.13.19 ]]

echo 'sing-box core version manager validation passed.'
