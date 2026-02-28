#!/bin/bash

ATOMIC=0

if command -v apt &>/dev/null; then
    echo "Using apt to install dependencies..."
    sudo apt update
    sudo apt install -y alsa-tools alsa-utils pulseaudio-utils git
elif
    command -v pacman &>/dev/null; then
    echo "Using pacman to install dependencies..."
    sudo pacman -Sy alsa-tools alsa-utils git --noconfirm
elif
    command -v eopkg &>/dev/null; then
    echo "Using eopkg to install dependencies..."
    sudo eopkg up
    sudo eopkg it alsa-tools alsa-utils git -y
elif
    command -v transactional-update &>/dev/null; then
    echo "Using transactional-update to install dependencies (atomic desktop)..."
    sudo transactional-update pkg install -y alsa-tools alsa-utils hda-verb
    echo "NOTE: A reboot is required for installed packages to take effect."
    ATOMIC=1
elif
    command -v zypper &>/dev/null; then
    echo "Using zypper to install dependencies..."
    sudo zypper install -y alsa-tools alsa-utils hda-verb git
elif
    [ -f /run/ostree-booted ] && command -v rpm-ostree &>/dev/null; then
    echo "Using rpm-ostree to install dependencies (atomic desktop)..."
    sudo rpm-ostree install -y alsa-tools alsa-utils
    echo "NOTE: A reboot is required for installed packages to take effect."
    ATOMIC=1
elif
    command -v dnf &>/dev/null; then
    echo "Using dnf to install dependencies..."
    sudo dnf install -y alsa-tools alsa-utils git
elif
    [ -f /etc/NIXOS ]; then
    echo "NixOS detected. Automatic installation is not supported on NixOS."
    echo "Please install alsa-tools and alsa-utils via configuration.nix,"
    echo "then manually copy the service files and enable them."
    exit 1
else
    echo "Neither apt, pacman, eopkg, transactional-update, zypper, rpm-ostree, dnf, nor NixOS found. Cannot install dependencies."
fi

echo "Copying files..."
sudo cp huawei-soundcard-headphones-monitor.sh /usr/local/bin/
sudo cp huawei-soundcard-headphones-monitor.service /etc/systemd/system/

echo "Setting rights..."
sudo chmod +x /usr/local/bin/huawei-soundcard-headphones-monitor.sh
sudo chmod +x /etc/systemd/system/huawei-soundcard-headphones-monitor.service

echo "Enabling and starting service..."
if [ "$ATOMIC" -eq 1 ]; then
    sudo systemctl enable huawei-soundcard-headphones-monitor.service
    echo "NOTE: Service will start automatically after reboot."
else
    sudo systemctl enable --now huawei-soundcard-headphones-monitor.service
fi

echo "Complete!"
