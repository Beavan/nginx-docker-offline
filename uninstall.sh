#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/package.conf"

[[ "${EUID}" -eq 0 ]] || {
  echo "Please run as root." >&2
  exit 1
}

systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
systemctl disable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
rm -f "/etc/default/${SERVICE_NAME}"
rm -f "${MANAGER_BIN}"
systemctl daemon-reload

if [[ "${REMOVE_DATA:-0}" == "1" ]]; then
  rm -rf "${INSTALL_DIR}"
fi

echo "Uninstall completed. Docker itself was not removed."
