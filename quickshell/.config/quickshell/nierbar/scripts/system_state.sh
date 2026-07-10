#!/usr/bin/env bash
set -euo pipefail

# Polled by SystemService.qml. Takes a mode so the bar can refresh cheap,
# fast-changing values often and expensive/slow ones rarely:
#   fast -> cpu, ram
#   slow -> gpu, network, battery, bluetooth, keyboard
#   all  -> everything, including volume/brightness (default; handy for debugging)
#
# Note: volume/mute (PipeWire) and brightness (backlight udev events) are now
# event-driven in SystemService.qml, so the fast lane no longer computes them.
# They are still emitted in "all" mode for standalone debugging of this script.
mode="${1:-all}"
want_fast=false; want_slow=false; want_va=false
case "$mode" in
  fast) want_fast=true ;;
  slow) want_slow=true ;;
  *)    want_fast=true; want_slow=true; want_va=true ;;
esac

# ---------------- volume/brightness (debug/"all" mode only) ----------------
if $want_va; then
  vol="--"; muted="false"
  if command -v wpctl >/dev/null 2>&1; then
    line=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
    n=$(printf '%s' "$line" | awk '{print $2}')
    [[ -n "${n:-}" ]] && vol=$(awk -v v="$n" 'BEGIN { printf "%d", v * 100 }')
    grep -qi MUTED <<<"$line" && muted="true"
  fi

  # Linear scale, to match the keyboard binds and SystemService.qml.
  bright="--"
  if command -v brightnessctl >/dev/null 2>&1; then
    bright=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,"",$4); print $4; exit}' || echo "--")
  fi
fi

# ---------------- fast lane ----------------
if $want_fast; then
  cpu="--"
  if [[ -r /proc/stat ]]; then
    read -r _ u n s i io irq sirq steal _ < /proc/stat
    t1=$((u+n+s+i+io+irq+sirq+steal)); idle1=$((i+io))
    sleep 0.1
    read -r _ u n s i io irq sirq steal _ < /proc/stat
    t2=$((u+n+s+i+io+irq+sirq+steal)); idle2=$((i+io))
    dt=$((t2-t1)); di=$((idle2-idle1))
    (( dt > 0 )) && cpu=$(( (100*(dt-di))/dt ))
  fi

  ram="--"
  if [[ -r /proc/meminfo ]]; then
    total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    ram=$(( (100*(total-avail))/total ))
  fi
fi

# ---------------- slow lane ----------------
if $want_slow; then
  gpu="--"
  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "--")
  elif command -v rocm-smi >/dev/null 2>&1; then
    gpu=$(rocm-smi --showuse --json 2>/dev/null | jq -r 'to_entries[0].value."GPU use (%)" // "--"' 2>/dev/null || echo "--")
  fi

  network="none"
  wifi_signal=0
  if command -v nmcli >/dev/null 2>&1; then
    if nmcli -t -f TYPE,STATE device status 2>/dev/null | grep -q '^ethernet:connected$'; then
      network="wired"
    elif nmcli -t -f TYPE,STATE device status 2>/dev/null | grep -q '^wifi:connected$'; then
      network="wifi"
      # SIGNAL (0-100) of the in-use AP (row marked with '*')
      wifi_signal=$(nmcli -t -f IN-USE,SIGNAL device wifi list 2>/dev/null | awk -F: '/^\*/{print $2; exit}')
      [[ "$wifi_signal" =~ ^[0-9]+$ ]] || wifi_signal=0
    fi
  elif [[ -d /sys/class/net ]]; then
    for iface in /sys/class/net/*; do
      name=$(basename "$iface")
      [[ "$name" == "lo" ]] && continue
      [[ -r "$iface/operstate" ]] && [[ "$(cat "$iface/operstate")" == "up" ]] && network="wired" && break
    done
  fi

  # active VPN / WireGuard tunnel (independent of the underlying wired/wifi link)
  vpn="false"
  if command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f TYPE connection show --active 2>/dev/null | grep -qE '^(vpn|wireguard)$' && vpn="true"
  fi

  bat_percent="--"; bat_seconds=-1; charging="false"
  if command -v upower >/dev/null 2>&1; then
    dev=$(upower -e 2>/dev/null | grep -m1 battery || true)
    if [[ -n "$dev" ]]; then
      info=$(upower -i "$dev" 2>/dev/null || true)
      bat_percent=$(awk '/percentage:/ {gsub(/%/,"",$2); print $2; exit}' <<<"$info" || echo "--")
      state=$(awk '/state:/ {print $2; exit}' <<<"$info" || true)
      [[ "$state" == "charging" ]] && charging="true"
      time=$(awk '/time to empty:/ {print $(NF-1),$NF; exit}' <<<"$info" || true)
      if [[ -n "$time" ]]; then
        v=$(awk '{print $1}' <<<"$time"); unit=$(awk '{print $2}' <<<"$time")
        case "$unit" in
          hour|hours) bat_seconds=$(awk -v v="$v" 'BEGIN{printf "%d", v*3600}') ;;
          minute|minutes) bat_seconds=$(awk -v v="$v" 'BEGIN{printf "%d", v*60}') ;;
        esac
      fi
    fi
  else
    bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1 || true)
    if [[ -n "$bat" ]]; then
      bat_percent=$(cat "$bat/capacity" 2>/dev/null || echo "--")
      [[ "$(cat "$bat/status" 2>/dev/null || true)" == "Charging" ]] && charging="true"
    fi
  fi

  # Treat "plugged into AC" as charging for the green indicator: charge-limit
  # thresholds can report "not charging" / "fully-charged" while on mains power.
  for f in /sys/class/power_supply/*/online; do
    [[ -r "$f" ]] || continue
    [[ "$(cat "$f" 2>/dev/null)" == "1" ]] && charging="true" && break
  done

  bt="off"
  if command -v bluetoothctl >/dev/null 2>&1; then
    if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
      bt="on"
      bluetoothctl devices Connected 2>/dev/null | grep -q '^Device' && bt="connected"
    fi
  fi

  kbd=""
  if command -v hyprctl >/dev/null 2>&1; then
    kbd=$(hyprctl devices -j 2>/dev/null | jq -r '.keyboards[0].active_keymap // ""' 2>/dev/null || true)
  fi
  [[ -z "$kbd" ]] && kbd="KB"
fi

# ---------------- emit ----------------
if $want_fast && ! $want_slow; then
  jq -nc \
    --arg cpu "$cpu" --arg ram "$ram" \
    '{cpu:$cpu, ram:$ram}'
elif $want_slow && ! $want_fast; then
  jq -nc \
    --arg gpu "$gpu" --arg network "$network" --argjson wifi_signal "${wifi_signal:-0}" --argjson vpn "${vpn:-false}" \
    --arg bat "$bat_percent" --argjson bat_seconds "$bat_seconds" --argjson charging "$charging" \
    --arg bt "$bt" --arg kbd "$kbd" \
    '{gpu:$gpu, network:$network, wifiSignal:$wifi_signal, vpn:$vpn, battery:$bat, batterySeconds:$bat_seconds, charging:$charging, bluetooth:$bt, keyboard:$kbd}'
else
  jq -nc \
    --arg vol "$vol" --argjson muted "$muted" --arg bright "$bright" --arg cpu "$cpu" --arg gpu "$gpu" --arg ram "$ram" \
    --arg network "$network" --argjson wifi_signal "${wifi_signal:-0}" --argjson vpn "${vpn:-false}" --arg bat "$bat_percent" --argjson bat_seconds "$bat_seconds" --argjson charging "$charging" --arg bt "$bt" --arg kbd "$kbd" \
    '{volume:$vol, muted:$muted, brightness:$bright, cpu:$cpu, gpu:$gpu, ram:$ram, network:$network, wifiSignal:$wifi_signal, vpn:$vpn, battery:$bat, batterySeconds:$bat_seconds, charging:$charging, bluetooth:$bt, keyboard:$kbd}'
fi
