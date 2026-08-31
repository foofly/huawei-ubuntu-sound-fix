#!/bin/bash
set -euo pipefail

# Installs the Huawei soundcard headphones monitor daemon.
#
# Works on classic distros (apt/pacman/eopkg/zypper/dnf) and on immutable /
# atomic ones (Fedora Silverblue/Kinoite/Bazzite, openSUSE MicroOS/Aeon,
# SteamOS). Atomic systems ship the classic package manager binary too, so
# they must be detected *before* it, otherwise we try to write to a read-only
# /usr and fail.
#
# Set DRY_RUN=1 to print privileged commands instead of running them.

SERVICE_NAME="huawei-soundcard-headphones-monitor"
SCRIPT_FILE="${SERVICE_NAME}.sh"
UNIT_FILE="${SERVICE_NAME}.service"
UNIT_DIR="/etc/systemd/system"
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN="${DRY_RUN:-0}"
needs_reboot=0

die() {
    echo "Error: $*" >&2
    exit 1
}

# Runs a command as root, or echoes it under DRY_RUN.
run() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] $*"
        return 0
    fi
    "${SUDO[@]}" "$@"
}

# Only the distro id, without sourcing untrusted values into our shell.
os_id() {
    [ -r /etc/os-release ] || return 0
    grep -E '^(ID|ID_LIKE)=' /etc/os-release | cut -d= -f2- | tr -d '"' | tr '\n' ' '
}

setup_privileges() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=()
        return
    fi
    command -v sudo >/dev/null || die "not running as root and sudo is not available."
    SUDO=(sudo)
    # Prompt once up front rather than at each step.
    [ "$DRY_RUN" = "1" ] || sudo -v || die "could not obtain root privileges."
}

# The daemon needs hda-verb (alsa-tools) and amixer (alsa-utils). Many atomic
# base images already carry them, and skipping the install avoids a package
# layering step plus a reboot.
missing_packages() {
    local missing=()
    command -v hda-verb >/dev/null 2>&1 || missing+=(alsa-tools)
    command -v amixer   >/dev/null 2>&1 || missing+=(alsa-utils)
    echo "${missing[@]:-}"
}

usr_is_readonly() {
    command -v findmnt >/dev/null 2>&1 || return 1
    findmnt -no OPTIONS /usr 2>/dev/null | grep -qE '(^|,)ro(,|$)'
}

# Platforms where the whole approach is invalid -- not just the package step --
# because they do not accept third-party files in /usr/local/bin and
# /etc/systemd/system. Checked before anything else, since these fail even when
# the dependencies happen to be present.
check_supported_platform() {
    local id
    id="$(os_id)"

    if [ -f /etc/NIXOS ]; then
        cat >&2 <<'MSG'

NixOS detected. This installer cannot manage a declarative system.

Add alsa-tools and alsa-utils to environment.systemPackages, then define the
daemon as a systemd.services unit in your configuration.nix or flake rather
than copying files into /usr/local/bin and /etc/systemd/system.
MSG
        exit 1
    fi

    # Match on the distro id only. Heuristics like "has snap but no apt" also
    # match any Fedora or Arch box with snapd installed.
    if [[ " $id " == *" ubuntu-core "* ]]; then
        cat >&2 <<'MSG'

Ubuntu Core is not supported.

This fix needs to drop a systemd unit into /etc/systemd/system and issue raw
HDA verbs against /dev/snd/hwC0D0 as root. Ubuntu Core allows neither: third
parties cannot add system units, and no snap interface grants raw HDA codec
access. Supporting it would require a differently designed snap, not this
installer.
MSG
        exit 1
    fi
}

install_dependencies() {
    local pkgs
    read -r -a pkgs <<< "$(missing_packages)"

    if [ "${#pkgs[@]}" -eq 0 ]; then
        echo "Dependencies already present (hda-verb, amixer). Skipping package install."
        return 0
    fi

    echo "Missing dependencies: ${pkgs[*]}"
    local id
    id="$(os_id)"

    # --- Immutable / atomic systems first ------------------------------------
    # These still ship dnf/zypper/pacman, so checking them later would match
    # the wrong branch and fail against a read-only /usr.

    if [ -f /run/ostree-booted ] && command -v rpm-ostree >/dev/null 2>&1; then
        echo "Detected Fedora Atomic (rpm-ostree). Layering dependencies..."
        # 77 means "no change" (already layered), which is success for us.
        local rc=0
        run rpm-ostree install --idempotent --allow-inactive -y "${pkgs[@]}" || rc=$?
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 77 ]; then
            die "rpm-ostree install failed (exit $rc)."
        fi
        needs_reboot=1
        return 0
    fi

    if command -v transactional-update >/dev/null 2>&1; then
        echo "Detected openSUSE MicroOS/Aeon (transactional-update). Installing into new snapshot..."
        run transactional-update --non-interactive pkg install "${pkgs[@]}" \
            || die "transactional-update pkg install failed."
        needs_reboot=1
        return 0
    fi

    if [[ " $id " == *" steamos "* ]] || command -v steamos-readonly >/dev/null 2>&1; then
        # Deliberately not automating steamos-readonly disable: the pacman
        # keyring is frequently unusable on SteamOS and anything installed this
        # way is wiped by the next SteamOS update.
        cat >&2 <<MSG

SteamOS detected, and ${pkgs[*]} is missing.

This installer will not unlock the read-only root for you. Install the
dependency manually:

    sudo steamos-readonly disable
    sudo pacman-key --init
    sudo pacman-key --populate archlinux holo
    sudo pacman -Sy ${pkgs[*]}
    sudo steamos-readonly enable

Then re-run this installer. Note that SteamOS updates wipe manually installed
packages, so this must be repeated after each system update.
MSG
        exit 1
    fi

    # Match on the distro id only. Heuristics like "has snap but no apt" or
    # "/snap/core exists" also match any Fedora or Arch box with snapd
    # installed, which must fall through to its own package manager.
    if [[ " $id " == *" ubuntu-core "* ]]; then
        cat >&2 <<'MSG'

Ubuntu Core is not supported.

This fix needs to drop a systemd unit into /etc/systemd/system and issue raw
HDA verbs against /dev/snd/hwC0D0 as root. Ubuntu Core allows neither: third
parties cannot add system units, and no snap interface grants raw HDA codec
access. Supporting it would require a differently designed snap, not this
installer.
MSG
        exit 1
    fi

    # --- Classic package managers --------------------------------------------

    if command -v apt >/dev/null 2>&1; then
        echo "Using apt to install dependencies..."
        run apt update || die "apt update failed."
        run apt install -y "${pkgs[@]}" || die "apt install failed."
    elif command -v pacman >/dev/null 2>&1; then
        echo "Using pacman to install dependencies..."
        run pacman -Sy --noconfirm "${pkgs[@]}" || die "pacman install failed."
    elif command -v eopkg >/dev/null 2>&1; then
        echo "Using eopkg to install dependencies..."
        run eopkg up || die "eopkg up failed."
        run eopkg it -y "${pkgs[@]}" || die "eopkg install failed."
    elif command -v zypper >/dev/null 2>&1; then
        echo "Using zypper to install dependencies..."
        run zypper install -y "${pkgs[@]}" || die "zypper install failed."
    elif command -v dnf >/dev/null 2>&1; then
        echo "Using dnf to install dependencies..."
        run dnf install -y "${pkgs[@]}" || die "dnf install failed."
    elif usr_is_readonly; then
        die "/usr is read-only and no supported atomic package manager was found.
Install ${pkgs[*]} using your distribution's mechanism, then re-run this installer."
    else
        die "no supported package manager found (apt, pacman, eopkg, zypper, dnf,
rpm-ostree, transactional-update, NixOS). Install ${pkgs[*]} manually, then re-run."
    fi
}

# /usr/local is writable and persistent on Fedora Atomic (symlink to
# /var/usrlocal) and on MicroOS (its own btrfs subvolume). On SteamOS and other
# hosts with a read-only /usr/local we fall back to /var.
pick_bindir() {
    # Probe as root, since the caller may not be able to write there directly.
    if [ "$DRY_RUN" = "1" ]; then
        # Don't mutate the filesystem while dry-running; report the likely target.
        if [ -d /usr/local/bin ] || [ -d /usr/local ]; then
            echo /usr/local/bin
        else
            echo "/var/lib/${SERVICE_NAME}/bin"
        fi
    elif "${SUDO[@]}" mkdir -p /usr/local/bin 2>/dev/null \
        && "${SUDO[@]}" test -w /usr/local/bin; then
        echo /usr/local/bin
    else
        echo "/var/lib/${SERVICE_NAME}/bin"
    fi
}

install_files() {
    local bindir="$1"

    echo "Installing to ${bindir}..."
    run install -d -m 0755 "$bindir"
    run install -m 0755 "${SRC_DIR}/${SCRIPT_FILE}" "${bindir}/${SCRIPT_FILE}"

    # The unit ships with a placeholder so ExecStart can follow the prefix we
    # actually chose.
    echo "Installing unit to ${UNIT_DIR}/${UNIT_FILE}..."
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] render ${UNIT_FILE} with @BINDIR@=${bindir} into ${UNIT_DIR}"
    else
        sed "s|@BINDIR@|${bindir}|g" "${SRC_DIR}/${UNIT_FILE}" \
            | "${SUDO[@]}" tee "${UNIT_DIR}/${UNIT_FILE}" >/dev/null
        "${SUDO[@]}" chmod 0644 "${UNIT_DIR}/${UNIT_FILE}"
    fi

    # Files written under /var get var_t on SELinux systems; systemd needs a
    # sane label to execute them.
    if command -v restorecon >/dev/null 2>&1; then
        run restorecon -F "${bindir}/${SCRIPT_FILE}" "${UNIT_DIR}/${UNIT_FILE}" || true
    fi
}

enable_service() {
    echo "Setting up daemon..."
    run systemctl daemon-reload || die "systemctl daemon-reload failed."
    run systemctl enable "$SERVICE_NAME" || die "systemctl enable failed."

    if [ "$needs_reboot" = "1" ]; then
        cat <<MSG

Installed, but a reboot is required.

Dependencies were staged into a new system deployment/snapshot, so hda-verb is
not available in the currently running one yet. The service is enabled and will
start automatically after you reboot:

    systemctl reboot

MSG
        return 0
    fi

    run systemctl restart "$SERVICE_NAME" || die "failed to start ${SERVICE_NAME}."
    echo "Complete!"
}

main() {
    [ -f "${SRC_DIR}/${SCRIPT_FILE}" ] || die "${SCRIPT_FILE} not found next to installer."
    [ -f "${SRC_DIR}/${UNIT_FILE}" ]   || die "${UNIT_FILE} not found next to installer."

    check_supported_platform
    setup_privileges
    install_dependencies

    local bindir
    bindir="$(pick_bindir)"
    install_files "$bindir"
    enable_service
}

main "$@"
