#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: MAC Randomizer
# ═══════════════════════════════════════════════════════════════
# Rotates MAC address on ALL network interfaces.
# Runs both outside (real interface) and inside namespace.
#
# - Changes MAC every N seconds (configurable)
# - Uses locally-administered, unicast addresses
# - Also randomizes hostname seen on LAN
# - Disables IPv6 privacy extensions (we handle it ourselves)
#
# ISP/router sees constantly changing hardware identity.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

MAC_PID_FILE="/tmp/ghostbox_mac.pid"
ROTATE_INTERVAL="${GHOSTBOX_MAC_INTERVAL:-3}"  # seconds

# ─── Generate random MAC ────────────────────────────────────

generate_mac() {
    # Generate random MAC with locally-administered bit set
    local b1 b2 b3 b4 b5 b6
    b1=$(printf '%02x' $(( (RANDOM % 256 | 0x02) & 0xFE )))  # locally admin, unicast
    b2=$(printf '%02x' $((RANDOM % 256)))
    b3=$(printf '%02x' $((RANDOM % 256)))
    b4=$(printf '%02x' $((RANDOM % 256)))
    b5=$(printf '%02x' $((RANDOM % 256)))
    b6=$(printf '%02x' $((RANDOM % 256)))
    echo "$b1:$b2:$b3:$b4:$b5:$b6"
}

# ─── Set MAC on interface ───────────────────────────────────

set_mac() {
    local iface="$1"
    local mac="$2"
    local ns="${3:-}"  # optional namespace

    if [[ -n "$ns" ]]; then
        ip netns exec "$ns" ip link set "$iface" down 2>/dev/null || true
        ip netns exec "$ns" ip link set "$iface" address "$mac" 2>/dev/null || true
        ip netns exec "$ns" ip link set "$iface" up 2>/dev/null || true
    else
        ip link set "$iface" down 2>/dev/null || true
        ip link set "$iface" address "$mac" 2>/dev/null || true
        ip link set "$iface" up 2>/dev/null || true
    fi
}

# ─── Randomize hostname ────────────────────────────────────

randomize_hostname() {
    local ns="${1:-}"
    local prefix
    prefix=$(shuf -n1 -e desktop laptop pc workstation home user)
    local suffix
    suffix=$(head -c 4 /dev/urandom | xxd -p)
    local new_hostname="${prefix}-${suffix}"

    if [[ -n "$ns" ]]; then
        ip netns exec "$ns" hostname "$new_hostname" 2>/dev/null || true
    else
        hostname "$new_hostname" 2>/dev/null || true
    fi
    echo "$new_hostname"
}

# ─── Get real network interfaces ────────────────────────────

get_real_interfaces() {
    # Find wireless and ethernet interfaces (exclude lo, veth, docker, etc)
    ip -o link show | awk -F': ' '{print $2}' | grep -E '^(wl|en|eth)' | head -5
}

# ─── Rotate once ────────────────────────────────────────────

mac_rotate_once() {
    local ifaces
    ifaces=$(get_real_interfaces)

    for iface in $ifaces; do
        local new_mac
        new_mac=$(generate_mac)

        # Need to handle WiFi specially — disconnect, change, reconnect
        if [[ "$iface" == wl* ]]; then
            # Check if connected to WiFi
            local ssid
            ssid=$(iwgetid -r "$iface" 2>/dev/null) || ssid=""

            if [[ -n "$ssid" ]]; then
                # Disconnect
                nmcli device disconnect "$iface" 2>/dev/null || true
                sleep 0.5
            fi

            set_mac "$iface" "$new_mac"

            # Reconnect if was connected
            if [[ -n "$ssid" ]]; then
                sleep 0.5
                nmcli device connect "$iface" 2>/dev/null || \
                nmcli connection up "$ssid" 2>/dev/null || true
            fi
        else
            set_mac "$iface" "$new_mac"
        fi

        echo "[mac] $iface → $new_mac"
    done

    # Also rotate inside namespace if it exists
    if ip netns list 2>/dev/null | grep -qw ghostbox; then
        local ns_mac
        ns_mac=$(generate_mac)
        set_mac gbox1 "$ns_mac" ghostbox
        echo "[mac] gbox1 (namespace) → $ns_mac"
    fi

    # Randomize hostname
    local new_host
    new_host=$(randomize_hostname)
    echo "[mac] hostname → $new_host"
}

# ─── Rotation daemon ────────────────────────────────────────

mac_daemon() {
    echo "[mac] Starting MAC rotation daemon (every ${ROTATE_INTERVAL}s)..."

    while true; do
        mac_rotate_once 2>/dev/null
        sleep "$ROTATE_INTERVAL"
    done
}

# ─── Start ───────────────────────────────────────────────────

mac_start() {
    echo "[mac] Starting MAC randomization..."

    # Kill existing
    mac_stop 2>/dev/null || true

    # Disable NetworkManager MAC management (we handle it)
    if command -v nmcli >/dev/null 2>&1; then
        for iface in $(get_real_interfaces); do
            local conn
            conn=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":${iface}$" | cut -d: -f1) || conn=""
            if [[ -n "$conn" ]]; then
                nmcli con mod "$conn" wifi.cloned-mac-address random 2>/dev/null || true
                nmcli con mod "$conn" ethernet.cloned-mac-address random 2>/dev/null || true
            fi
        done
    fi

    # Initial rotation
    mac_rotate_once

    # Start daemon
    mac_daemon &
    local pid=$!
    echo "$pid" > "$MAC_PID_FILE"

    echo "[mac] Daemon started (PID: $pid)"
    echo "[mac] All MACs rotating every ${ROTATE_INTERVAL}s"
}

# ─── Stop ────────────────────────────────────────────────────

mac_stop() {
    if [[ -f "$MAC_PID_FILE" ]]; then
        local pid
        pid=$(cat "$MAC_PID_FILE")
        kill "$pid" 2>/dev/null || true
        pkill -P "$pid" 2>/dev/null || true
        rm -f "$MAC_PID_FILE"
        echo "[mac] Daemon stopped"
    else
        pkill -f "mac_daemon" 2>/dev/null || true
    fi
}

# ─── Status ──────────────────────────────────────────────────

mac_status() {
    echo "[mac] === MAC Randomization Status ==="
    if [[ -f "$MAC_PID_FILE" ]] && kill -0 "$(cat "$MAC_PID_FILE")" 2>/dev/null; then
        echo "[mac] Daemon: RUNNING (PID: $(cat "$MAC_PID_FILE"))"
    else
        echo "[mac] Daemon: STOPPED"
    fi

    echo "[mac] Current MACs:"
    for iface in $(get_real_interfaces); do
        local mac
        mac=$(ip link show "$iface" 2>/dev/null | grep link/ether | awk '{print $2}') || mac="?"
        echo "  $iface: $mac"
    done

    if ip netns list 2>/dev/null | grep -qw ghostbox; then
        local ns_mac
        ns_mac=$(ip netns exec ghostbox ip link show gbox1 2>/dev/null | grep link/ether | awk '{print $2}') || ns_mac="?"
        echo "  gbox1 (ns): $ns_mac"
    fi

    echo "[mac] Hostname: $(hostname)"
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    start)  mac_start ;;
    stop)   mac_stop ;;
    rotate) mac_rotate_once ;;
    status) mac_status ;;
    *)      echo "Usage: $0 {start|stop|rotate|status}" ;;
esac
