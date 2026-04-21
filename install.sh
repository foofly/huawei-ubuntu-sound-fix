#!/bin/bash

# Detect immutable/atomic OS (OSTree-based: Fedora Silverblue, Kinoite, etc.)
ATOMIC=0
if [ -f /run/ostree-booted ]; then
    ATOMIC=1
fi

if command -v apt &>/dev/null; then
    echo "Using apt to install dependencies..."
    sudo apt update
    sudo apt install -y alsa-tools alsa-utils git
elif command -v pacman &>/dev/null; then
    echo "Using pacman to install dependencies..."
    sudo pacman -Sy alsa-tools alsa-utils git --noconfirm
elif command -v eopkg &>/dev/null; then
    echo "Using eopkg to install dependencies..."
    sudo eopkg up
    sudo eopkg it alsa-tools alsa-utils git -y
elif command -v transactional-update &>/dev/null; then
    echo "Using transactional-update to install dependencies (atomic desktop)..."
    sudo transactional-update pkg install -y alsa-tools alsa-utils hda-verb
    echo "NOTE: A reboot is required for installed packages to take effect."
    ATOMIC=1
elif command -v zypper &>/dev/null; then
    echo "Using zypper to install dependencies..."
    sudo zypper install -y alsa-tools alsa-utils hda-verb git
elif [ $ATOMIC -eq 1 ] && command -v rpm-ostree &>/dev/null; then
    echo "Using rpm-ostree to install dependencies (atomic desktop)..."
    sudo rpm-ostree install -y alsa-tools alsa-utils
    echo "NOTE: A reboot is required for installed packages to take effect."
elif command -v dnf &>/dev/null; then
    echo "Using dnf to install dependencies..."
    sudo dnf install -y alsa-tools alsa-utils git
elif [ -f /etc/NIXOS ]; then
    echo "NixOS detected. Automatic installation is not supported on NixOS."
    echo "Please install alsa-tools and alsa-utils via configuration.nix,"
    echo "then manually copy the service files and enable them."
    exit 1
else
    echo "Neither apt, pacman, eopkg, transactional-update, zypper, rpm-ostree, dnf, nor NixOS found. Cannot install dependencies."
    exit 1
fi

# On atomic systems /usr/local/bin may be read-only; use /var/usrlocal/bin as fallback
INSTALL_BIN_DIR="/usr/local/bin"
if [ $ATOMIC -eq 1 ] && [ ! -w /usr/local/bin ] 2>/dev/null; then
    INSTALL_BIN_DIR="/var/usrlocal/bin"
    sudo mkdir -p "$INSTALL_BIN_DIR"
fi

echo "Copying files..."
sudo cp huawei-soundcard-headphones-monitor.sh "$INSTALL_BIN_DIR/"
sudo cp huawei-soundcard-headphones-monitor.service /etc/systemd/system/

# Update service file to use the actual install path if it differs from default
if [ "$INSTALL_BIN_DIR" != "/usr/local/bin" ]; then
    sudo sed -i "s|/usr/local/bin/|$INSTALL_BIN_DIR/|g" /etc/systemd/system/huawei-soundcard-headphones-monitor.service
fi

echo "Setting rights..."
sudo chmod +x "$INSTALL_BIN_DIR/huawei-soundcard-headphones-monitor.sh"

echo "Setting up daemon..."
sudo systemctl daemon-reload
if [ $ATOMIC -eq 1 ]; then
    sudo systemctl enable huawei-soundcard-headphones-monitor.service
    echo "NOTE: Service will start automatically after reboot."
else
    sudo systemctl enable --now huawei-soundcard-headphones-monitor.service
fi

echo "Complete!"
