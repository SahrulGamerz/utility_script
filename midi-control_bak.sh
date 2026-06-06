#!/usr/bin/env bash
set -u

# Sleep for 3s
sleep 3

################################
# MIDI CONFIG
################################
MIDI_PORT="32:0"

################################
# PIPEWIRE NODES
################################
MAIN_NODE="virt_output"
AUX_NODE="virt_aux_output"
HEADPHONES_NODE="alsa_output.pci-0000_0b_00.4.analog-stereo"
HEADPHONES_NODE_2="alsa_output.usb-TTGK_Technology_Co._Ltd_CX31993_MAX97220_PRO-00.analog-stereo"
#SPEAKERS_NODE="alsa_output.usb-GS3_GS3_20180508-00.analog-stereo"
#SPEAKERS_NODE="alsa_output.usb-0c76_USB_PnP_Audio_Device-00.analog-stereo"
#SPEAKERS_NODE="alsa_output.usb-0c76_USB_PnP_Audio_Device-00.2.pro-output-0"
#SPEAKERS_NODE="alsa_output.usb-0c76_USB_PnP_Audio_Device-00.2.pro-output-0"
SPEAKERS_NODE="alsa_output.usb-Jieli_Technology_USB_Composite_Device_4250313332393401-01.analog-stereo"
CAVA_NODE="cava_monitor"

################################
# AUDIO INPUT
################################
#MIC_MAIN="alsa_input.usb-0c76_USB_PnP_Audio_Device-00.2.pro-input-0"
MIC_MAIN="alsa_input.usb-0c76_USB_PnP_Audio_Device-00.mono-fallback"

################################
# MIDI MAP
################################
# Media
NOTE_PREV=68
NOTE_PLAY=67
NOTE_STOP=66
NOTE_NEXT=65

# AUX / routing
NOTE_AUX_SWITCH=69
NOTE_MIC_MUTE=70
NOTE_SPK_MUTE=71
NOTE_HP_MUTE=72

# CC
CC_HP_VOL=0
CC_SPK_VOL=1
CC_AUX_VOL=2

################################
# STATE
################################
STATE_FILE="$HOME/.cache/aux-target"
AUX_TARGET="$(cat "$STATE_FILE" 2>/dev/null || echo headphones)"

################################
# SMOOTHING CONFIG (FINAL)
################################
CC_DEADZONE=2
APPLY_INTERVAL=60
VOL_STEP=2

LAST_CC_HP=-1
LAST_CC_HP_2=-1
LAST_CC_SPK=-1
LAST_CC_AUX=-1
LAST_APPLY_TIME=0
LAST_APPLIED_VOL=""

################################
# HELPERS
################################
now_ms() { date +%s%3N; }

################################
# OSD (SAFE: DISCRETE EVENTS ONLY)
################################
osd() {
  dunstify \
    -a "MIDI Audio Router" \
    -t 900 \
    "$1"
}

################################
# MUTE STATE HELPERS
################################
sink_is_muted() {
  pactl get-sink-mute "$1" | grep -q "yes"
}

source_is_muted() {
  pactl get-source-mute "$1" | grep -q "yes"
}

toggle_hp_mute() {
  if sink_is_muted "$HEADPHONES_NODE"; then
    pactl set-sink-mute "$HEADPHONES_NODE" 0
    pactl set-sink-mute "$HEADPHONES_NODE_2" 0
    osd "🎧 Headphones Unmuted"
  else
    pactl set-sink-mute "$HEADPHONES_NODE" 1
    pactl set-sink-mute "$HEADPHONES_NODE_2" 1
    osd "🎧 Headphones Muted"
  fi
}

toggle_spk_mute() {
  if sink_is_muted "$SPEAKERS_NODE"; then
    pactl set-sink-mute "$SPEAKERS_NODE" 0
    osd "🔊 Speakers Unmuted"
  else
    pactl set-sink-mute "$SPEAKERS_NODE" 1
    osd "🔊 Speakers Muted"
  fi
}

toggle_mic_mute() {
  if source_is_muted "$MIC_MAIN"; then
    pactl set-source-mute "$MIC_MAIN" 0
    osd "🎙 Mic Unmuted"
  else
    pactl set-source-mute "$MIC_MAIN" 1
    osd "🎙 Mic Muted"
  fi
}

################################
# PIPEWIRE LINK CONTROL
################################
unlink_main() {
  #pw-link -d "$MAIN_NODE:monitor_1" "$HEADPHONES_NODE:playback_FL" 2>/dev/null || true
  #pw-link -d "$MAIN_NODE:monitor_2" "$HEADPHONES_NODE:playback_FR" 2>/dev/null || true

  pw-link -d "$MAIN_NODE:monitor_FL" "$HEADPHONES_NODE:playback_FL" 2>/dev/null || true
  pw-link -d "$MAIN_NODE:monitor_FR" "$HEADPHONES_NODE:playback_FR" 2>/dev/null || true

  pw-link -d "$MAIN_NODE:monitor_FL" "$HEADPHONES_NODE_2:playback_FL" 2>/dev/null || true
  pw-link -d "$MAIN_NODE:monitor_FR" "$HEADPHONES_NODE_2:playback_FR" 2>/dev/null || true
}

unlink_aux() {
  #pw-link -d "$AUX_NODE:monitor_1" "$SPEAKERS_NODE:playback_FL" 2>/dev/null || true
  #pw-link -d "$AUX_NODE:monitor_2" "$SPEAKERS_NODE:playback_FR" 2>/dev/null || true
  #pw-link -d "$AUX_NODE:monitor_1" "$HEADPHONES_NODE:playback_FL" 2>/dev/null || true
  #pw-link -d "$AUX_NODE:monitor_2" "$HEADPHONES_NODE:playback_FR" 2>/dev/null || true
  #pw-link -d "$AUX_NODE:monitor_1" "$SPEAKERS_NODE:playback_AUX0" 2>/dev/null || true
  #pw-link -d "$AUX_NODE:monitor_2" "$SPEAKERS_NODE:playback_AUX1" 2>/dev/null || true

  pw-link -d "$AUX_NODE:monitor_FL" "$SPEAKERS_NODE:playback_FL" 2>/dev/null || true
  pw-link -d "$AUX_NODE:monitor_FR" "$SPEAKERS_NODE:playback_FR" 2>/dev/null || true
  pw-link -d "$AUX_NODE:monitor_FL" "$HEADPHONES_NODE:playback_FL" 2>/dev/null || true
  pw-link -d "$AUX_NODE:monitor_FR" "$HEADPHONES_NODE:playback_FR" 2>/dev/null || true
  pw-link -d "$AUX_NODE:monitor_FL" "$HEADPHONES_NODE_2:playback_FL" 2>/dev/null || true
  pw-link -d "$AUX_NODE:monitor_FR" "$HEADPHONES_NODE_2:playback_FR" 2>/dev/null || true
  #pw-link -d "$AUX_NODE:monitor_FL" "$CAVA_NODE:playback_FL" 2>/dev/null || true
  #pw-link -d "$AUX_NODE:monitor_FR" "$CAVA_NODE:playback_FR" 2>/dev/null || true

  #pw-link -d "$AUX_NODE:monitor_FL" "$SPEAKERS_NODE:playback_AUX0" 2>/dev/null || true
  #pw-link -d "$AUX_NODE:monitor_FR" "$SPEAKERS_NODE:playback_AUX1" 2>/dev/null || true

}

unlink_aux_cava() {
  pw-link -d "$AUX_NODE:monitor_FL" "$CAVA_NODE:playback_FL" 2>/dev/null || true
  pw-link -d "$AUX_NODE:monitor_FR" "$CAVA_NODE:playback_FR" 2>/dev/null || true
}

link_main_to_headphones() {
  unlink_main
  #pw-link "$MAIN_NODE:monitor_1" "$HEADPHONES_NODE:playback_FL"
  #pw-link "$MAIN_NODE:monitor_2" "$HEADPHONES_NODE:playback_FR"

  pw-link "$MAIN_NODE:monitor_FL" "$HEADPHONES_NODE:playback_FL"
  pw-link "$MAIN_NODE:monitor_FR" "$HEADPHONES_NODE:playback_FR"

  pw-link "$MAIN_NODE:monitor_FL" "$HEADPHONES_NODE_2:playback_FL"
  pw-link "$MAIN_NODE:monitor_FR" "$HEADPHONES_NODE_2:playback_FR"
}

link_aux_to() {
  unlink_aux
  #pw-link "$AUX_NODE:monitor_1" "$1:playback_FL"
  #pw-link "$AUX_NODE:monitor_2" "$1:playback_FR"
  #pw-link "$AUX_NODE:monitor_1" "$1:playback_AUX0"
  #pw-link "$AUX_NODE:monitor_2" "$1:playback_AUX1"

  pw-link "$AUX_NODE:monitor_FL" "$1:playback_FL"
  pw-link "$AUX_NODE:monitor_FR" "$1:playback_FR"
  #pw-link "$AUX_NODE:monitor_FL" "$1:playback_AUX0"
  #pw-link "$AUX_NODE:monitor_FR" "$1:playback_AUX1"

}

link_aux_to_headphone_2() {
  pw-link "$AUX_NODE:monitor_FL" "$HEADPHONES_NODE_2:playback_FL"
  pw-link "$AUX_NODE:monitor_FR" "$HEADPHONES_NODE_2:playback_FR"

}

link_aux_to_cava() {
  unlink_aux_cava
  pw-link "$AUX_NODE:monitor_FL" "$CAVA_NODE:playback_FL"
  pw-link "$AUX_NODE:monitor_FR" "$CAVA_NODE:playback_FR"
  #pw-link "$AUX_NODE:monitor_FL" "$CAVA_NODE:playback_AUX0"
  #pw-link "$AUX_NODE:monitor_FR" "$CAVA_NODE:playback_AUX1"
}

aux_to_headphones() {
  link_aux_to "$HEADPHONES_NODE"
  link_aux_to_headphone_2
  AUX_TARGET="headphones"
  echo "headphones" > "$STATE_FILE"
  osd "🔀 AUX → Headphones"
}

aux_to_speakers() {
  link_aux_to "$SPEAKERS_NODE"
  AUX_TARGET="speakers"
  echo "speakers" > "$STATE_FILE"
  osd "🔀 AUX → Speakers"
}

################################
# CLEANUP
################################
trap unlink_aux EXIT INT TERM

################################
# INITIAL ROUTE
################################
link_main_to_headphones
link_aux_to_cava

if [ "$AUX_TARGET" = "speakers" ]; then
  aux_to_speakers
else
  aux_to_headphones
fi

echo "🎛 MIDI Audio Router running on $MIDI_PORT"

################################
# SMOOTH VOLUME HANDLER
################################
smooth_volume() {
  local VALUE="$1" LAST="$2" SINK="$3"
  local NOW DIFF VOL

  [ "$LAST" -eq -1 ] && LAST="$VALUE"
  DIFF=$(( VALUE > LAST ? VALUE - LAST : LAST - VALUE ))
  NOW=$(now_ms)

  if (( DIFF >= CC_DEADZONE && NOW - LAST_APPLY_TIME >= APPLY_INTERVAL )); then
    VOL=$(( VALUE * 100 / 127 ))
    VOL=$(( (VOL / VOL_STEP) * VOL_STEP ))

    # ----- HYSTERESIS -----
    if [ "$VOL" = "$LAST_APPLIED_VOL" ]; then
      echo "$LAST"
      return
    fi
    LAST_APPLIED_VOL="$VOL"
    # ---------------------

    pactl set-sink-volume "$SINK" "${VOL}%"
    LAST_APPLY_TIME="$NOW"
    echo "$VALUE"
  else
    echo "$LAST"
  fi
}

################################
# MIDI LOOP
################################
aseqdump -p "$MIDI_PORT" | while read -r line; do

  ################################
  # MEDIA (NO OSD)
  ################################
  grep -q "Note on.* note $NOTE_PREV," <<<"$line" && playerctl previous
  grep -q "Note on.* note $NOTE_PLAY," <<<"$line" && playerctl play-pause
  grep -q "Note on.* note $NOTE_STOP," <<<"$line" && playerctl stop
  grep -q "Note on.* note $NOTE_NEXT," <<<"$line" && playerctl next

  ################################
  # AUX SWITCH (OSD SAFE)
  ################################
  if grep -q "Note on.* note $NOTE_AUX_SWITCH," <<<"$line"; then
    [ "$AUX_TARGET" = "headphones" ] && aux_to_speakers || aux_to_headphones
  fi

  ################################
  # VOLUME CC (NO OSD)
  ################################
  if grep -q "Control change.*controller $CC_HP_VOL," <<<"$line"; then
    V=$(sed -n 's/.*value \([0-9]\+\).*/\1/p' <<<"$line")
    LAST_CC_HP=$(smooth_volume "$V" "$LAST_CC_HP" "$HEADPHONES_NODE")
  fi

  if grep -q "Control change.*controller $CC_HP_VOL," <<<"$line"; then
    V=$(sed -n 's/.*value \([0-9]\+\).*/\1/p' <<<"$line")
    LAST_CC_HP_2=$(smooth_volume "$V" "$LAST_CC_HP_2" "$HEADPHONES_NODE_2")
  fi

  if grep -q "Control change.*controller $CC_SPK_VOL," <<<"$line"; then
    V=$(sed -n 's/.*value \([0-9]\+\).*/\1/p' <<<"$line")
    LAST_CC_SPK=$(smooth_volume "$V" "$LAST_CC_SPK" "$SPEAKERS_NODE")
  fi

  if grep -q "Control change.*controller $CC_AUX_VOL," <<<"$line"; then
    V=$(sed -n 's/.*value \([0-9]\+\).*/\1/p' <<<"$line")
    LAST_CC_AUX=$(smooth_volume "$V" "$LAST_CC_AUX" "$AUX_NODE")
  fi

  ################################
  # MUTES (OSD SAFE)
  ################################
  grep -q "Note on.* note $NOTE_HP_MUTE," <<<"$line" && toggle_hp_mute
  grep -q "Note on.* note $NOTE_SPK_MUTE," <<<"$line" && toggle_spk_mute
  grep -q "Note on.* note $NOTE_MIC_MUTE," <<<"$line" && toggle_mic_mute

done
