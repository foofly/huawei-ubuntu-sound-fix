#!/bin/bash
set -euo pipefail

SERVICE_NAME="huawei-soundcard-headphones-monitor"
SCRIPT_FILE="${SERVICE_NAME}.sh"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# The installer picks whichever prefix was writable, and earlier versions of
# this project used /var/usrlocal/bin, so clean up all of them.
BIN_CANDIDATES=(
    "/usr/local/bin/${SCRIPT_FILE}"
    "/var/lib/${SERVICE_NAME}/bin/${SCRIPT_FILE}"
    "/var/usrlocal/bin/${SCRIPT_FILE}"
)

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    command -v sudo >/dev/null || { echo "Error: not root and sudo unavailable." >&2; exit 1; }
    SUDO=(sudo)
fi

echo "Stopping daemon..."
"${SUDO[@]}" systemctl stop "${SERVICE_NAME}.service" || true
"${SUDO[@]}" systemctl disable "${SERVICE_NAME}.service" || true

echo "Removing program..."
for path in "${BIN_CANDIDATES[@]}"; do
    "${SUDO[@]}" rm -f "$path"
done
"${SUDO[@]}" rmdir --ignore-fail-on-non-empty "/var/lib/${SERVICE_NAME}/bin" \
    "/var/lib/${SERVICE_NAME}" 2>/dev/null || true

echo "Removing service..."
"${SUDO[@]}" rm -f "$UNIT_PATH"
"${SUDO[@]}" systemctl daemon-reload

cat <<MSG

Uninstalled. Goodbye 😿

The alsa-tools / alsa-utils packages were left installed. To remove them on an
atomic system:

    rpm-ostree uninstall alsa-tools alsa-utils          # Fedora Atomic
    transactional-update pkg remove alsa-tools alsa-utils   # MicroOS/Aeon
MSG
