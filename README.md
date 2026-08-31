# Huawei MateBook Audio Fix

**Headphones play through the speakers, and unplugging them silences everything.**
This fixes that on Huawei MateBook 14s / 16s, on both traditional and immutable
Linux distributions.

## Is this your problem?

Symptom: with headphones plugged in, audio still comes out of the speakers, and
unplugging them leaves you with no sound at all.

The quirk lives in the **codec**, not the chassis, so that is what to check:

```bash
grep -h '^Codec:' /proc/asound/card*/codec#*
```

If that lists `Conexant CX11880` on a Huawei MateBook, this applies to you. The
installer and the daemon both check for it and refuse otherwise, since the raw
HDA verbs target that codec's specific widgets (`0x10`/`0x11` DACs, `0x16`
headphone pin, `0x17` speaker) and address unrelated hardware elsewhere.

Model codes seen affected so far — the same codec ships under several, so this
list is illustrative rather than a whitelist:

| `product_name` | Notes |
| --- | --- |
| `HKF-WXX` | MateBook 14s; upstream's development machine |
| `CREF-16` | MateBook 16s; reported upstream |
| `HKD-WXX` | Confirmed working, and the only hardware this fork is tested on |

```bash
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_family /sys/class/dmi/id/product_name
```

Override the check with `FORCE_UNSUPPORTED_MODEL=1` if you are certain, but note
that a wrong guess can leave you with no audio until a full power cycle — a warm
reboot does **not** reset the codec, and the service re-applies on every boot
until disabled. Recovery is `bash uninstall.sh` followed by a cold boot.

> **Do not try to diagnose this from the codec dump's connection selects.** It is
> tempting to check which DAC pin `0x17` reports, but widget `0x17` *ignores its
> own connection select and follows `0x16`* — that is the whole bug. The register
> shows the nominal value, not the effective routing, so an affected machine can
> look correctly routed. Trust the symptom.

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
| HDA codec writes on real hardware | Verified on a MateBook `HKD-WXX` (Conexant CX11880) — correct routing with and without headphones, surviving idle periods and reboots |
| Poll interval / power-save tuning | Verified — 0.20% of one core at `POLL_INTERVAL=3` with `power_save=0`, versus 3.2% at 0.3s |
| **Other model codes (`HKF-WXX`, `CREF-16`)** | **Not verified** by this fork — inherited from upstream reports |
| **Atomic layering then reboot** | **Not verified** on a real Silverblue/Kinoite/MicroOS install |

Reports from other model codes are very welcome — please include
your model, distro, `journalctl -u huawei-soundcard-headphones-monitor` output
and `pactl list sinks short`.

## How it works

A daemon polls the headphone jack and **continuously re-asserts** the HDA
routing verbs, by default every 0.3s (`POLL_INTERVAL`). It discovers the sound
card index and the audio sink at runtime, and works with both PulseAudio and
PipeWire through `pactl`. Because the daemon runs as root, `pactl` calls are
re-entered into the desktop user's session via `runuser`.

### Why it polls instead of using events

The constant re-assertion is the fix, not an inefficiency. The codec resets its
connection select whenever it powers down, silently undoing the routing.
Re-writing it on a short interval simply out-paces that.

An event-driven version using `alsactl monitor` was tried and reverted: applying
the verbs only on plug/unplug meant the fix was lost within seconds of the codec
going idle.

### Poll interval and power saving

Because the resets are caused by codec power-down, the installer disables it via
`/etc/modprobe.d/huawei-matebook-audio-fix.conf` (`snd_hda_intel power_save=0`),
and the daemon picks its interval from that setting:

| `power_save` | Default `POLL_INTERVAL` | Measured CPU |
| --- | --- | --- |
| `0` (set by the installer) | 3s | ~0.35% of one core |
| `1` (kernel default) | 0.3s | ~3.2% of one core |

Deriving the interval this way means the two settings cannot drift apart — before
the reboot that activates the modprobe option, the daemon still uses the safe
0.3s interval, and relaxes automatically afterwards. Override explicitly with
`POLL_INTERVAL` if you want to tune it yourself; `uninstall.sh` restores the
default power-saving behaviour.

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
