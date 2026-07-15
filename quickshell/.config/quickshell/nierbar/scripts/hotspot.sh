#!/usr/bin/env bash
set -euo pipefail

# WiFi hotspot control for NetworkService.qml. Turns the wifi radio into an
# access point sharing the machine's other (e.g. wired) connection via
# NetworkManager's `ipv4.method shared` (built-in dnsmasq DHCP + NAT).
#
# Subcommands:
#   status                     -> JSON {active, device, ssid, password, band}
#   start <ssid> <pw> <band>   create/replace the profile and bring it up
#   stop                       bring the profile down (wifi client resumes)
#   clients [device]           -> JSON array of connected station names
#   qr <ssid> <pw>             render a WiFi-join QR PNG, print its path
#
# Conservative fixed defaults: WPA2-AES (wpa-psk, proto rsn, ccmp) when a >=8
# char password is set else an open network, autoconnect off, SSID broadcast,
# ap-isolation off, pinned to ch6 (2.4GHz) / ch36 (5GHz) for client compat.
# The ssid/password/band are mirrored to a 0600 state file so the popup can
# prefill fields and build the QR without prompting NetworkManager for the
# stored secret.
#
# Runtime dependencies: dnsmasq (DHCP for shared mode), qrencode (join QR),
# iw (client list).
#
# FIREWALL: if a firewall is active (e.g. ufw) it will block DHCP and NAT, so
# clients associate + complete the WPA2 handshake but never get an IP (they
# spin on "obtaining address" then drop). Allow it once — for ufw:
#     sudo ufw allow in on <wifi-iface> to any port 67 proto udp  # DHCP
#     sudo ufw allow in on <wifi-iface> to any port 53            # DNS
#     sudo ufw route allow in on <wifi-iface>                     # NAT / routing
# The rules persist across reboots and only take effect while the AP is up
# (dnsmasq binds only to 10.42.0.1). Substitute your wifi interface name
# (see `hotspot.sh status` -> .device, e.g. wlp0s20f3).

PROFILE="nierbar-hotspot"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nierbar"
CFG="$STATE_DIR/hotspot.json"
QR="$STATE_DIR/hotspot-qr.png"

wifi_iface() {
  nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
}

cmd="${1:-status}"

case "$cmd" in
  status)
    active=false
    dev=""
    if nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -q "^${PROFILE}:"; then
      active=true
      dev=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null \
              | awk -F: -v p="$PROFILE" '$1==p{print $2; exit}')
    fi
    ssid=""; pw=""; band="bg"
    if [[ -r "$CFG" ]]; then
      ssid=$(jq -r '.ssid // ""' "$CFG")
      pw=$(jq -r '.password // ""' "$CFG")
      band=$(jq -r '.band // "bg"' "$CFG")
    fi
    jq -nc --argjson active "$active" --arg dev "$dev" \
      --arg ssid "$ssid" --arg pw "$pw" --arg band "$band" \
      '{active:$active, device:$dev, ssid:$ssid, password:$pw, band:$band}'
    ;;

  start)
    ssid="${2:-nierbar}"
    pw="${3:-}"
    band="${4:-bg}"
    dev=$(wifi_iface)

    # NetworkManager's `ipv4.method shared` (DHCP + NAT) shells out to dnsmasq;
    # without it the AP associates but IP config fails with a cryptic error.
    if ! command -v dnsmasq >/dev/null 2>&1; then
      echo "dnsmasq not installed — run: sudo pacman -S dnsmasq" >&2
      exit 3
    fi

    # the state file holds the password in plaintext (needed to rebuild the QR
    # without asking NM for the secret) — keep it owner-only.
    mkdir -p -m 700 "$STATE_DIR"
    ( umask 077
      jq -nc --arg ssid "$ssid" --arg pw "$pw" --arg band "$band" \
        '{ssid:$ssid, password:$pw, band:$band}' > "$CFG" )

    # an AP needs the radio on; enabling the profile then takes the device out
    # of client mode on its own (so the normal wifi connection drops).
    nmcli radio wifi on || true

    # recreate from scratch each start so stale security settings can't linger
    # when switching between an open and a WPA2 hotspot.
    nmcli connection delete "$PROFILE" >/dev/null 2>&1 || true

    ifopt=()
    [[ -n "$dev" ]] && ifopt=(ifname "$dev")

    # Pin a universally-allowed, non-DFS channel. Auto-selection can land on
    # 2.4GHz ch12/13, which clients in many regulatory domains refuse — they
    # associate but never finish connecting. ch6 (2.4GHz) / ch36 (5GHz) are
    # safe everywhere.
    chan=6
    [[ "$band" == "a" ]] && chan=36

    add=(nmcli connection add type wifi "${ifopt[@]}" con-name "$PROFILE"
         autoconnect no ssid "$ssid"
         802-11-wireless.mode ap
         802-11-wireless.band "$band"
         802-11-wireless.channel "$chan"
         802-11-wireless.ap-isolation 0
         ipv4.method shared
         ipv6.method ignore)

    if [[ "${#pw}" -ge 8 ]]; then
      # Pin WPA2-Personal with AES/CCMP only (proto rsn). Leaving the ciphers
      # unset lets NM also advertise WPA/TKIP, whose handshake many modern
      # clients reject — they associate (show up as a station) but never finish
      # connecting. Forcing CCMP makes the handshake succeed.
      add+=(wifi-sec.key-mgmt wpa-psk
            wifi-sec.proto rsn
            wifi-sec.pairwise ccmp
            wifi-sec.group ccmp
            wifi-sec.psk "$pw")
    fi

    "${add[@]}"
    nmcli connection up "$PROFILE"
    ;;

  stop)
    nmcli connection down "$PROFILE" >/dev/null 2>&1 || true
    ;;

  clients)
    dev="${2:-$(wifi_iface)}"
    leases="/var/lib/NetworkManager/dnsmasq-$dev.leases"
    names=()
    while read -r mac; do
      [[ -z "$mac" ]] && continue
      name=""
      if [[ -r "$leases" ]]; then
        # lease line: <expiry> <mac> <ip> <hostname> <clientid>
        name=$(awk -v m="${mac,,}" 'tolower($2)==m{print $4}' "$leases" | head -n1)
      fi
      if [[ -z "$name" || "$name" == "*" ]]; then
        name="$mac"
      fi
      names+=("$name")
    done < <(iw dev "$dev" station dump 2>/dev/null | awk '/^Station/{print $2}')

    if ((${#names[@]})); then
      printf '%s\n' "${names[@]}" | jq -Rsc 'split("\n") | map(select(length>0))'
    else
      echo "[]"
    fi
    ;;

  qr)
    ssid="${2:-}"
    pw="${3:-}"
    mkdir -p -m 700 "$STATE_DIR"
    umask 077
    # de-facto WiFi-join QR payload. WPA when a password is set, else open.
    if [[ -n "$pw" ]]; then
      payload="WIFI:T:WPA;S:${ssid};P:${pw};H:false;;"
    else
      payload="WIFI:T:nopass;S:${ssid};H:false;;"
    fi
    printf '%s' "$payload" | qrencode -o "$QR" -s 6 -m 2 -l M
    echo "$QR"
    ;;

  *)
    echo "usage: hotspot.sh {status|start|stop|clients|qr}" >&2
    exit 2
    ;;
esac
