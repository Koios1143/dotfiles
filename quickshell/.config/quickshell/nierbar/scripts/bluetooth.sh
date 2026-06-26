#!/usr/bin/env bash
set -euo pipefail

# Emits the adapter power state plus the list of known devices (with connected
# status) as JSON, for BluetoothService.qml.

powered=false
if command -v bluetoothctl >/dev/null 2>&1; then
  bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && powered=true
fi

devices_json="[]"
if [[ "$powered" == "true" ]]; then
  connected=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}')
  items=()
  while read -r _ mac name; do
    [[ -z "${mac:-}" ]] && continue
    conn=false
    grep -qxF "$mac" <<<"$connected" && conn=true
    items+=("$(jq -nc --arg mac "$mac" --arg name "$name" --argjson conn "$conn" \
      '{mac:$mac, name:$name, connected:$conn}')")
  done < <(bluetoothctl devices 2>/dev/null)
  if ((${#items[@]})); then
    devices_json=$(printf '%s\n' "${items[@]}" | jq -sc '.')
  fi
fi

jq -nc --argjson powered "$powered" --argjson devices "$devices_json" \
  '{powered:$powered, devices:$devices}'
