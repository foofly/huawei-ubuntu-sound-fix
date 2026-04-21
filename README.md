# Huawei Matebook 14s / 16s soundcard fix

Fork of [Smoren/huawei-ubuntu-sound-fix](https://github.com/Smoren/huawei-ubuntu-sound-fix) with added support for immutable/atomic distros and PipeWire audio systems.

## Changes in this fork

- **Fedora Atomic** (Silverblue, Kinoite, etc.) — uses `rpm-ostree` for package installation; detects immutable filesystem and installs to the correct path
- **openSUSE MicroOS / Aeon / Kalpa** — uses `transactional-update`
- **PipeWire support** — audio port switching now works on PipeWire systems (e.g. Fedora Kinoite); the daemon detects the active desktop session and runs `pactl` in the correct user context instead of failing as root
- **NixOS** — install script detects NixOS and prints manual instructions instead of failing silently
- Improved `uninstall.sh` (disables service, cleans up both possible install paths)

## Problem

The headphone and speaker channels are mixed up in the sound card driver for Linux.

When headphones are connected, the system outputs from speakers. When disconnected, it tries to use the headphones. A daemon monitors jack state and uses `hda-verb` to switch routing at the hardware level.

For full technical details see the [upstream issue](https://github.com/thesofproject/linux/issues/3350#issuecomment-1301070327).

## Supported distros

| Distro | Package manager used |
|---|---|
| Ubuntu / Debian | `apt` |
| Arch / Manjaro | `pacman` |
| Solus | `eopkg` |
| Fedora | `dnf` |
| Fedora Atomic (Silverblue, Kinoite, …) | `rpm-ostree` |
| openSUSE Tumbleweed / Leap | `zypper` |
| openSUSE MicroOS / Aeon / Kalpa | `transactional-update` |
| NixOS | manual (see below) |

## Install

```bash
bash install.sh
```

> **Fedora Atomic / openSUSE MicroOS**: a **reboot is required** after running the installer. The service will start automatically after reboot.

> **NixOS**: automatic installation is not supported. Install `alsa-tools` and `alsa-utils` via `configuration.nix`, then manually copy the service files and enable them.

## Uninstall

```bash
bash uninstall.sh
```

## Daemon control

```bash
systemctl status huawei-soundcard-headphones-monitor
systemctl restart huawei-soundcard-headphones-monitor
systemctl start huawei-soundcard-headphones-monitor
systemctl stop huawei-soundcard-headphones-monitor
```

## Credits

Original fix and daemon by [Smoren](https://github.com/Smoren). Hardware analysis from [this comment](https://github.com/thesofproject/linux/issues/3350#issuecomment-1301070327).
