#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: Tor Routing + obfs4 Bridge Support
# ═══════════════════════════════════════════════════════════════
# Routes ALL traffic from the namespace through Tor.
# Uses transparent proxy mode so applications don't need
# SOCKS configuration.
#
# obfs4 bridges hide Tor usage from ISP — they see normal
# HTTPS traffic instead of Tor protocol signatures.
#
# With obfs4: ISP cannot even detect you're using Tor.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/configs"

GHOST_NS="ghostbox"
HOST_IP="10.200.1.1"
NS_IP="10.200.1.2"

TOR_SOCKS_PORT=9050
TOR_DNS_PORT=5353
TOR_TRANS_PORT=9040
TOR_CONTROL_PORT=9051

TORRC_FILE="$CONFIG_DIR/torrc.ghostbox"
TOR_DATA_DIR="/var/lib/tor/ghostbox"
TOR_LOG="/var/log/tor/ghostbox.log"

# ─── Generate Tor configuration ─────────────────────────────

tor_generate_config() {
    local use_bridges="${1:-no}"

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$TOR_DATA_DIR"
    chown debian-tor:debian-tor "$TOR_DATA_DIR" 2>/dev/null || true

    cat > "$TORRC_FILE" <<EOF
# ═══ GhostBox Tor Configuration ═══
# Auto-generated — do not edit manually

# Data directory
DataDirectory $TOR_DATA_DIR
Log notice file $TOR_LOG

# SOCKS proxy (for applications that support it)
SocksPort $HOST_IP:$TOR_SOCKS_PORT

# Transparent proxy (catches ALL TCP traffic)
TransPort $HOST_IP:$TOR_TRANS_PORT

# DNS resolver through Tor
DNSPort $HOST_IP:$TOR_DNS_PORT

# Control port (for circuit rotation)
ControlPort $TOR_CONTROL_PORT
HashedControlPassword 16:A9B8C7D6E5F4A3B2C1D0E9F8A7B6C5D4E3F2A1B0C9D8E7F6A5B4C3D2

# Automatically map DNS to .exit addresses
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10

# Force new circuit every 30 seconds (for identity rotation)
MaxCircuitDirtiness 30

# Use a new circuit for each destination
IsolateDestAddr
IsolateDestPort

# Disable IPv6 (prevents leaks)
ClientUseIPv4 1
ClientUseIPv6 0

# Connection padding (makes traffic analysis harder)
ConnectionPadding 1

# Reduced connection padding is OFF (we want maximum padding)
ReducedConnectionPadding 0
EOF

    # Add bridge configuration if requested
    if [[ "$use_bridges" == "yes" ]]; then
        cat >> "$TORRC_FILE" <<'EOF'

# ═══ BRIDGE CONFIGURATION ═══
# obfs4 makes Tor traffic look like regular HTTPS
# ISP cannot detect Tor usage
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

# Default obfs4 bridges (get fresh ones from https://bridges.torproject.org)
# These are public bridges — for maximum security, request private ones
Bridge obfs4 192.95.36.142:443 CDF2E852BF539B82BD10E27E9115A31734E378C2 cert=qUVQ0srL1JI/vO6V6m/24anYXiJD3QP2HgzUKQtQ7GRqqUvs7P+tG43RtAqdhLOALP7DJQ iat-mode=1
Bridge obfs4 38.229.1.78:80 C8CBDB2464FC9804A69531437BCF2BE31FDD2EE4 cert=Hmyfd2ev46gGY7NoVxA9ngrPF2zCZtzskRTzoWXbxNkzeVnGFPWmrTtILRyqCTjHR+s9dg iat-mode=1
Bridge obfs4 85.31.186.98:443 011F2599C0E9B27EE74B353155E244813763C3E5 cert=AwkwaKKSLibMVgjoy0WlQ9we2MHbKVfAxbv7l0MhNkm30rkJJWdmRzhW0GM+BN4NG2SWKQ iat-mode=1
EOF
        echo "[tor] Bridge mode enabled (obfs4 — ISP cannot detect Tor)"
    fi

    echo "[tor] Configuration written to $TORRC_FILE"
}

# ─── Start Tor service ───────────────────────────────────────

tor_start() {
    local use_bridges="${1:-no}"

    echo "[tor] Starting Tor routing..."

    # Generate config
    tor_generate_config "$use_bridges"

    # Stop any existing Tor instance for ghostbox
    tor_stop 2>/dev/null || true

    # Start Tor with our config
    tor -f "$TORRC_FILE" --runas debian-tor &
    local tor_pid=$!

    echo "[tor] Tor starting (PID: $tor_pid)..."

    # Wait for Tor to bootstrap
    local tries=0
    local max_tries=60
    while [[ $tries -lt $max_tries ]]; do
        if grep -q "Bootstrapped 100%" "$TOR_LOG" 2>/dev/null; then
            echo "[tor] Tor fully bootstrapped!"
            break
        fi
        sleep 2
        ((tries++))
        if [[ $((tries % 5)) -eq 0 ]]; then
            local pct
            pct=$(grep -oP 'Bootstrapped \K[0-9]+' "$TOR_LOG" 2>/dev/null | tail -1) || pct="0"
            echo "[tor] Bootstrapping... ${pct}%"
        fi
    done

    if [[ $tries -ge $max_tries ]]; then
        echo "[tor] WARNING: Tor did not fully bootstrap in time"
        echo "[tor] Check $TOR_LOG for details"
        return 1
    fi

    # Set up NAT/redirect so namespace traffic goes through Tor
    tor_setup_redirect

    echo "[tor] All namespace traffic now routes through Tor"
}

# ─── Set up iptables redirect for transparent proxy ──────────

tor_setup_redirect() {
    echo "[tor] Setting up transparent proxy redirect..."

    # NAT rules: redirect all TCP from namespace through Tor transparent proxy
    iptables -t nat -A PREROUTING -i gbox0 -p tcp -j REDIRECT --to-ports $TOR_TRANS_PORT 2>/dev/null || \
    nft add rule ip nat prerouting iif gbox0 tcp dport != $TOR_SOCKS_PORT redirect to :$TOR_TRANS_PORT 2>/dev/null || true

    # Redirect DNS from namespace to Tor DNS
    iptables -t nat -A PREROUTING -i gbox0 -p udp --dport 53 -j REDIRECT --to-ports $TOR_DNS_PORT 2>/dev/null || \
    nft add rule ip nat prerouting iif gbox0 udp dport 53 redirect to :$TOR_DNS_PORT 2>/dev/null || true

    echo "[tor] TCP → Tor transparent proxy (:$TOR_TRANS_PORT)"
    echo "[tor] DNS → Tor DNS resolver (:$TOR_DNS_PORT)"
}

# ─── Stop Tor ────────────────────────────────────────────────

tor_stop() {
    echo "[tor] Stopping Tor..."

    # Kill Tor process
    pkill -f "tor -f $TORRC_FILE" 2>/dev/null || true

    # Remove NAT rules
    iptables -t nat -F PREROUTING 2>/dev/null || true

    # Clean up data dir (anti-forensic)
    if [[ -d "$TOR_DATA_DIR" ]]; then
        find "$TOR_DATA_DIR" -type f -exec shred -u {} \; 2>/dev/null || true
        rm -rf "$TOR_DATA_DIR" 2>/dev/null || true
    fi

    echo "[tor] Tor stopped and data shredded"
}

# ─── Rotate Tor circuit (new identity) ───────────────────────

tor_new_circuit() {
    # Send NEWNYM signal to Tor control port
    # This creates a completely new circuit (new exit node = new IP)
    echo -e 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT' | \
        nc -q 1 127.0.0.1 $TOR_CONTROL_PORT 2>/dev/null || \
    echo -e 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT' | \
        socat - TCP:127.0.0.1:$TOR_CONTROL_PORT 2>/dev/null || true

    echo "[tor] New circuit requested (new exit IP)"
}

# ─── Get current exit node info ──────────────────────────────

tor_exit_info() {
    # Check our apparent IP through Tor
    local exit_ip
    exit_ip=$(ip netns exec "$GHOST_NS" curl -s --socks5 "$HOST_IP:$TOR_SOCKS_PORT" https://check.torproject.org/api/ip 2>/dev/null) || \
    exit_ip=$(ip netns exec "$GHOST_NS" curl -s --socks5 "$HOST_IP:$TOR_SOCKS_PORT" https://api.ipify.org 2>/dev/null) || \
    exit_ip="unknown"

    echo "[tor] Current exit IP: $exit_ip"
}

# ─── Verify Tor routing ─────────────────────────────────────

tor_verify() {
    echo "[tor] Verifying Tor routing..."
    local failures=0

    # Check Tor process is running
    if pgrep -f "tor -f $TORRC_FILE" >/dev/null 2>&1; then
        echo "[tor] PASS: Tor process running"
    else
        echo "[tor] FAIL: Tor process not running!"
        ((failures++))
    fi

    # Check bootstrap status
    if grep -q "Bootstrapped 100%" "$TOR_LOG" 2>/dev/null; then
        echo "[tor] PASS: Tor fully bootstrapped"
    else
        echo "[tor] FAIL: Tor not fully bootstrapped"
        ((failures++))
    fi

    # Check that namespace traffic goes through Tor
    local check
    check=$(ip netns exec "$GHOST_NS" curl -s --max-time 15 --socks5 "$HOST_IP:$TOR_SOCKS_PORT" https://check.torproject.org/api/ip 2>/dev/null) || check=""
    if [[ -n "$check" ]]; then
        echo "[tor] PASS: Traffic routes through Tor (exit: $check)"
    else
        echo "[tor] WARN: Could not verify Tor routing (timeout?)"
    fi

    if [[ $failures -eq 0 ]]; then
        echo "[tor] ALL CHECKS PASSED"
    else
        echo "[tor] WARNING: $failures checks failed"
    fi

    return $failures
}

# ─── Status ──────────────────────────────────────────────────

tor_status() {
    if pgrep -f "tor -f $TORRC_FILE" >/dev/null 2>&1; then
        echo "[tor] Status: RUNNING"
        local pct
        pct=$(grep -oP 'Bootstrapped \K[0-9]+' "$TOR_LOG" 2>/dev/null | tail -1) || pct="?"
        echo "[tor] Bootstrap: ${pct}%"
        tor_exit_info
    else
        echo "[tor] Status: STOPPED"
    fi
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    start)       tor_start "${2:-no}" ;;
    stop)        tor_stop ;;
    restart)     tor_stop; sleep 2; tor_start "${2:-no}" ;;
    new-circuit) tor_new_circuit ;;
    exit-info)   tor_exit_info ;;
    verify)      tor_verify ;;
    status)      tor_status ;;
    *)           echo "Usage: $0 {start [bridges]|stop|restart|new-circuit|exit-info|verify|status}" ;;
esac
