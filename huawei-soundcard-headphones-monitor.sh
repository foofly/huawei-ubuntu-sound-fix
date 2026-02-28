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

function get_sink_name() {
    pactl list sinks short 2>/dev/null | awk '/sofhdadsp/ {print $2; exit}'
}

function switch_to_headphones() {
    move_output_to_headphones
    hda 0x17 0x70C 0x0000   # disable speaker (EAPD/BTL)
    hda 0x1  0x717 0x2      # pin widget control: output mode
    hda 0x1  0x716 0x2      # pin sense: enable
    hda 0x1  0x715 0x0      # GPIO: clear pin

    local sink
    sink=$(get_sink_name)
    if [ -n "${sink}" ]; then
        pactl set-sink-port "${sink}" "[Out] Headphones" 2>/dev/null || true
    else
        echo "Warning: sofhdadsp sink not found via pactl — skipping port switch" >&2
    fi
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
