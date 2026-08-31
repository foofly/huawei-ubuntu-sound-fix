#!/bin/bash
set -eo pipefail

# HARDWARE NOTES
# Huawei MateBook 14s/16s HDA codec quirk:
#   0x01 - Audio Function Group
#   0x10 - Headphones DAC (used by both outputs due to hardware coupling)
#   0x11 - Speaker DAC
#   0x16 - Headphone Jack (connection select controls both 0x16 and 0x17)
#   0x17 - Internal Speaker (ignores its own connection select; mirrors 0x16)
# Must explicitly disable speaker via EAPD/BTL and manage GPIO manually.
# See: https://github.com/thesofproject/linux/issues/3350#issuecomment-1301070327

pidof -o %PPID -x "$0" >/dev/null && echo "Script $0 already running" && exit 1

function get_sound_card_index() {
    local idx
    idx=$(grep -m1 'sof-hda-dsp' /proc/asound/cards | grep -Eo '^\s*[0-9]+')
    echo "${idx#"${idx%%[![:space:]]*}"}"
}

# Allow ALSA to finish enumerating and PipeWire/PulseAudio session to settle
sleep 2

card_index=$(get_sound_card_index)
if [ -z "${card_index}" ]; then
    echo "sof-hda-dsp card not found in /proc/asound/cards — aborting" >&2
    exit 1
fi

HDA_DEVICE="/dev/snd/hwC${card_index}D0"

function hda() {
    hda-verb "${HDA_DEVICE}" "$@" >/dev/null 2>&1
}

function move_output_to_speaker()    { hda 0x16 0x701 0x0001; }
function move_output_to_headphones() { hda 0x16 0x701 0x0000; }

function switch_to_speaker() {
    move_output_to_speaker
    hda 0x17 0x70C 0x0002   # enable speaker (EAPD/BTL)
    hda 0x1  0x715 0x2      # disable headphone GPIO
}

# This daemon runs as root, which has no route to the desktop user's sound
# server, so every pactl call has to be re-entered into that user's session.
function find_desktop_uid() {
    local sid uid type
    while read -r sid uid _; do
        [ -n "$sid" ] || continue
        type=$(loginctl show-session "$sid" -p Type --value 2>/dev/null) || continue
        if [ "$type" = "wayland" ] || [ "$type" = "x11" ]; then
            echo "$uid"
            return 0
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
    return 0
}

function as_desktop_user() {
    local uid="$1"
    shift
    runuser -u "#${uid}" -- env "XDG_RUNTIME_DIR=/run/user/${uid}" "$@"
}

# Every sink on this card shares the "hda_dsp" substring, HDMI ones included,
# so they must be excluded explicitly or HDMI wins on output order. Matching by
# pattern rather than a hardcoded PCI path keeps this working across machines
# and across PulseAudio vs PipeWire naming.
function get_sink_name() {
    local uid="$1"
    as_desktop_user "$uid" pactl list sinks short 2>/dev/null \
        | awk '$2 ~ /sofhdadsp|sof-hda-dsp|hda_dsp/ && $2 !~ /[Hh][Dd][Mm][Ii]/ { print $2; exit }'
}

function set_audio_port() {
    local port="$1"
    local uid sink

    uid=$(find_desktop_uid)
    if [ -z "$uid" ] || [ ! -d "/run/user/${uid}" ]; then
        return 0
    fi

    sink=$(get_sink_name "$uid")
    if [ -z "$sink" ]; then
        echo "Warning: sofhdadsp sink not found via pactl - skipping port switch" >&2
        return 0
    fi

    # Best-effort: the hda-verb routing above is what actually fixes the audio,
    # and this script runs under set -e.
    as_desktop_user "$uid" pactl set-sink-port "$sink" "$port" >/dev/null 2>&1 || true
}

function switch_to_headphones() {
    move_output_to_headphones
    hda 0x17 0x70C 0x0000   # disable speaker (EAPD/BTL)
    hda 0x1  0x717 0x2      # pin widget control: output mode
    hda 0x1  0x716 0x2      # pin sense: enable
    hda 0x1  0x715 0x0      # GPIO: clear pin

    set_audio_port "[Out] Headphones"
}

old_status=0

function check_and_apply_state() {
    local status
    if amixer "-c${card_index}" get Headphone 2>/dev/null | grep -q "off"; then
        status=1
    else
        status=2
    fi
    if [ "${status}" -ne "${old_status}" ]; then
        case "${status}" in
            1) echo "Headphones disconnected — switching to speaker";   switch_to_speaker ;;
            2) echo "Headphones connected — switching to headphones"; switch_to_headphones ;;
        esac
        old_status=${status}
    fi
}

check_and_apply_state

alsactl monitor | while IFS= read -r _line; do
    check_and_apply_state
done
