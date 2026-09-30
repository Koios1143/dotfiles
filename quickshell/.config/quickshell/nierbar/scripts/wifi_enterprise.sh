#!/usr/bin/env bash
set -euo pipefail

# WPA-Enterprise (802.1X) wifi connect for NetworkService.qml. `nmcli device
# wifi connect` can only carry a PSK, so an enterprise SSID needs a real
# profile with the 802-1x settings before it can be brought up.
#
# Subcommands:
#   connect <ssid> [eap] [phase2]   create/update the profile and activate it
#
# eap defaults to peap, phase2 to mschapv2 — the combination essentially every
# campus/eduroam-style network uses. ttls+mschapv2 is the other common pair.
#
# Credentials come in through the environment, NOT argv: /proc/<pid>/cmdline is
# world-readable while /proc/<pid>/environ is owner-only.
#   NIERBAR_EAP_IDENTITY   account name (may be user@realm)
#   NIERBAR_EAP_PASSWORD   account password
#   NIERBAR_EAP_ANON       optional anonymous identity sent in the clear
#   NIERBAR_EAP_CA         optional CA cert path to validate the RADIUS server
#
# With no CA cert the server certificate is not validated. That is the usual
# situation on campus networks that never publish one; NetworkManager logs a
# warning and connects anyway. Point NIERBAR_EAP_CA at the pem when you have it.

wifi_iface() {
  nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
}

# a stored wifi profile whose name is exactly this ssid, if any
wifi_profile_exists() {
  nmcli -t -f NAME,TYPE connection show 2>/dev/null \
    | awk -F: -v s="$1" '{t=$NF; sub("(:[^:]*)$","",$0); if ($0==s && t=="802-11-wireless") { print "yes"; exit }}'
}

cmd="${1:-}"

case "$cmd" in
  connect)
    ssid="${2:-}"
    eap="${3:-peap}"
    phase2="${4:-mschapv2}"
    [[ -n "$ssid" ]] || { echo "connect: missing ssid" >&2; exit 2; }

    identity="${NIERBAR_EAP_IDENTITY:-}"
    password="${NIERBAR_EAP_PASSWORD:-}"
    [[ -n "$identity" ]] || { echo "Account required" >&2; exit 2; }
    [[ -n "$password" ]] || { echo "Password required" >&2; exit 2; }

    # 802-1x.password-flags 0 = store in NetworkManager, so reconnects and
    # autoconnect work without prompting again.
    settings=(
      802-11-wireless.ssid            "$ssid"
      802-11-wireless-security.key-mgmt wpa-eap
      802-1x.eap                      "$eap"
      802-1x.phase2-auth              "$phase2"
      802-1x.identity                 "$identity"
      802-1x.password                 "$password"
      802-1x.password-flags           0
      connection.autoconnect          yes
    )
    if [[ -n "${NIERBAR_EAP_ANON:-}" ]]; then
      settings+=(802-1x.anonymous-identity "$NIERBAR_EAP_ANON")
    fi
    if [[ -n "${NIERBAR_EAP_CA:-}" ]]; then
      settings+=(802-1x.ca-cert "$NIERBAR_EAP_CA" 802-1x.system-ca-certs no)
    fi

    if [[ -n "$(wifi_profile_exists "$ssid")" ]]; then
      # reuse the existing profile so its ip/dns/metered tweaks survive. A
      # previous PSK profile for the same SSID must lose its psk, otherwise
      # NetworkManager rejects the wpa-eap key-mgmt as inconsistent.
      nmcli connection modify "$ssid" "${settings[@]}" 802-11-wireless-security.psk ""
    else
      iface="$(wifi_iface)"
      add=(nmcli connection add type wifi con-name "$ssid")
      [[ -n "$iface" ]] && add+=(ifname "$iface")
      add+=(ssid "$ssid" -- "${settings[@]}")
      "${add[@]}" >/dev/null
    fi

    exec nmcli connection up "$ssid"
    ;;
  *)
    echo "usage: wifi_enterprise.sh connect <ssid> [eap] [phase2]" >&2
    exit 2
    ;;
esac
