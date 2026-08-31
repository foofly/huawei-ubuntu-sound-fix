# Huawei MateBook Audio Fix

**Headphones play through the speakers, and unplugging them silences everything.**
This fixes that on Huawei MateBook 14s / 16s, on both traditional and immutable
Linux distributions.

## Is this your problem?

The fix targets one specific hardware quirk, and the installer **refuses to run
on unsupported models** because applying it elsewhere can leave you with no
audio until a cold boot.

**1. Check your model:**

```bash
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name
```

| Model | Product name |
| --- | --- |
| MateBook 14s | `HKF-WXX` |
| MateBook 16s | `CREF-16` |

**2. Check you actually have the fault** — this is the definitive test:

```bash
awk '/^Node 0x16 /,/^Node 0x18 /' /proc/asound/card*/codec#0 \
  | grep -E '^Node 0x1[67]|^ +0x1[01]'
```

The asterisk marks the DAC each pin is currently using:

```
Node 0x16 [Pin Complex] ...      <- headphone pin
     0x10* 0x11
Node 0x17 [Pin Complex] ...      <- speaker pin
     0x10  0x11*
```

* **`0x17` shows `0x11*`** — speaker and headphones already use separate DACs.
  Your machine **does not have this bug**, and installing will break working
  audio. Stop here.
* **`0x17` shows `0x10*`** — both outputs are collapsed onto the headphone DAC.
  That is the fault this fixes.

Other Huawei models (MateBook 14, D14, D15) are **not** covered. If you are
certain you want to proceed on an unlisted model, `FORCE_UNSUPPORTED_MODEL=1`
overrides both the installer and the daemon — but read the warning above first,
and know that recovery requires a full power cycle, not a reboot.

## Install

```bash
bash install.sh
```

Preview every privileged command without changing anything:

```bash
DRY_RUN=1 bash install.sh
```

Dependencies (`alsa-tools` for `hda-verb`, `alsa-utils` for `amixer` and
`alsactl`) are installed only if actually missing, so on images that already
ship them nothing is layered and no reboot is needed.

### Supported platforms

Atomic distributions still ship `dnf`, `zypper` or `pacman` even though `/usr`
is read-only, so the installer checks for the atomic tooling **first** —
otherwise the classic manager matches and then fails against a read-only root.

| Platform | Handling |
| --- | --- |
| Ubuntu / Debian, Arch, Fedora, openSUSE, Solus | Standard install via `apt`, `pacman`, `dnf`, `zypper` or `eopkg`. |
| Fedora Silverblue / Kinoite / Sericea / Bazzite | Detected via `/run/ostree-booted`; layered with `rpm-ostree`. **Reboot required** — the packages exist only in the next deployment. The service is enabled and starts automatically after reboot. |
| openSUSE MicroOS / Aeon / Kalpa | Installed into a new snapshot with `transactional-update`. **Reboot required.** |
| SteamOS | The daemon installs normally, but the installer will not unlock the read-only root for you: SteamOS keyrings are often unusable and anything installed that way is wiped by the next system update. If `hda-verb` is missing it prints the exact steps and exits. |
| NixOS | Not supported — a declarative system needs a proper module, not an imperative installer. The script explains what to add to `configuration.nix`, then exits. |
| Ubuntu Core | Not supported. Third parties cannot add units to `/etc/systemd/system`, and no snap interface grants raw HDA codec access on `/dev/snd/hwC0D0`. |

The daemon installs to `/usr/local/bin` where writable, falling back to
`/var/lib/huawei-soundcard-headphones-monitor/bin`. On ostree systems
`/usr/local` already points at `/var/usrlocal`, so both survive system updates.

## Uninstall

```bash
bash uninstall.sh
```

Stops and disables the service and removes the installed files, including the
legacy `/var/usrlocal/bin` path used by earlier versions. Layered packages are
left alone; the script prints the `rpm-ostree uninstall` /
`transactional-update pkg remove` commands if you want those gone too.

## Daemon control

```bash
systemctl status huawei-soundcard-headphones-monitor
systemctl restart huawei-soundcard-headphones-monitor
systemctl stop huawei-soundcard-headphones-monitor
journalctl -fu huawei-soundcard-headphones-monitor
```

The log prints a line on each transition, so plugging and unplugging headphones
while watching `journalctl -fu` is the quickest way to confirm it is working.

## Verification status

Be aware of what has and has not been tested:

| | Status |
| --- | --- |
| Installer branch selection | Verified — dry-run matrix across Fedora, Ubuntu, Arch, openSUSE, plus stubbed `rpm-ostree`, `transactional-update`, SteamOS, NixOS and Ubuntu Core |
| Shell correctness | Verified — `shellcheck` clean, `systemd-analyze verify` clean |
| Sink and session discovery | Verified on a PipeWire/Wayland host |
| **HDA codec writes on real hardware** | **Not verified** — no MateBook 14s/16s available |
| **Atomic layering then reboot** | **Not verified** on a real Silverblue/Kinoite/MicroOS install |

Reports from people with the actual hardware are very welcome — please include
your model, distro, `journalctl -u huawei-soundcard-headphones-monitor` output
and `pactl list sinks short`.

## How it works

An event-driven daemon watches for jack connect/disconnect events via
`alsactl monitor` — no polling loop — and issues the HDA verbs needed to route
audio correctly. It discovers the sound card index and the audio sink at
runtime, and works with both PulseAudio and PipeWire through `pactl`. Because
the daemon runs as root, `pactl` calls are re-entered into the desktop user's
session via `runuser`.

### The hardware quirk

Diagnosed in [thesofproject/linux#3350](https://github.com/thesofproject/linux/issues/3350#issuecomment-1301070327).
The relevant HDA widgets are:

| Widget | Role |
| --- | --- |
| `0x01` | Audio Function Group |
| `0x10` | Headphones DAC (both devices are really connected here) |
| `0x11` | Speaker DAC |
| `0x16` | Headphones Jack |
| `0x17` | Internal Speaker |

* Widgets `0x16` and `0x17` should connect to different DACs (`0x10` and `0x11`),
  but Internal Speaker `0x17` ignores the connection-select command and uses the
  value from Headphones Jack `0x16`.
* Headphone Jack `0x16` must be enabled with GPIO commands on Audio Group `0x01`.
* Internal Speaker `0x17` is coupled to `0x16`, so it must be explicitly disabled
  with the EAPD/BTL Enable command.

## Credits

Original project and the hardware reverse-engineering behind this fix:
**[Smoren](https://github.com/Smoren)** —
[Smoren/huawei-ubuntu-sound-fix](https://github.com/Smoren/huawei-ubuntu-sound-fix).
This repository is an independently maintained fork.

Upstream contributors whose work is included here: Arnaud Rebillout, Bill Kav,
KharLexis, maksimetny, Simone Checchia, Tim Kainz, Vladimir Kopylov and Wartybix.

## Licensing

The upstream project was published without a license, so it remains under
default copyright held by its contributors. No license can be added here
retroactively over other people's work. This fork exists as a GitHub fork under
the [GitHub Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#5-license-grant-to-other-users)
§D.5 fork grant. If you intend to redistribute this code elsewhere, please seek
clarification from the original authors first.
