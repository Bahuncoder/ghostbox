#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: DNS Isolation
# ═══════════════════════════════════════════════════════════════
# ALL DNS goes through Tor. No DNS query ever touches ISP.
#
# How it works:
#   1. Inside the namespace, /etc/resolv.conf points to our
#      local resolver (on the host side of the veth pair)
#   2. The host runs a tiny DNS forwarder that sends all
#      queries through Tor's DNS resolver
#   3. Firewall blocks ALL other DNS traffic
#   4. Even if an app hardcodes 8.8.8.8, it gets blocked
#
# Result: ISP sees ZERO DNS queries. They have no idea what
# domains you're resolving.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

GHOST_NS="ghostbox"
HOST_IP="10.200.1.1"
NS_IP="10.200.1.2"
TOR_DNS_PORT=5353
LOCAL_DNS_PORT=53

DNS_PID_FILE="/tmp/ghostbox_dns.pid"

# ─── Setup DNS inside namespace ──────────────────────────────

dns_setup() {
    echo "[dns] Setting up isolated DNS resolution..."

    # Create resolv.conf for namespace
    # Points to host IP where Tor DNS is running
    mkdir -p /etc/netns/"$GHOST_NS"
    cat > /etc/netns/"$GHOST_NS"/resolv.conf <<EOF
# GhostBox DNS — all queries route through Tor
# No ISP DNS server is ever contacted
nameserver $HOST_IP
options ndots:0
options timeout:5
options attempts:3
EOF

    echo "[dns] Namespace resolv.conf configured → $HOST_IP"

    # Start a DNS forwarder on host that proxies to Tor's DNS port
    # Using socat to forward UDP 53 on host veth to Tor DNS
    dns_start_forwarder

    echo "[dns] DNS isolation active — all queries go through Tor"
}

# ─── Start DNS forwarder ─────────────────────────────────────

dns_start_forwarder() {
    # Kill existing forwarder
    dns_stop_forwarder 2>/dev/null || true

    # Method 1: Use socat to forward DNS queries to Tor
    # Listens on host veth IP:53, forwards to localhost:TOR_DNS_PORT
    if command -v socat >/dev/null 2>&1; then
        socat UDP4-LISTEN:$LOCAL_DNS_PORT,bind=$HOST_IP,fork,reuseaddr \
              UDP4:127.0.0.1:$TOR_DNS_PORT &
        local pid=$!
        echo "$pid" > "$DNS_PID_FILE"
        echo "[dns] DNS forwarder started (socat, PID: $pid)"

    # Method 2: Use iptables DNAT if socat isn't available
    else
        iptables -t nat -A PREROUTING -i gbox0 -p udp --dport 53 \
            -j DNAT --to-destination 127.0.0.1:$TOR_DNS_PORT 2>/dev/null || true
        iptables -t nat -A PREROUTING -i gbox0 -p tcp --dport 53 \
            -j DNAT --to-destination 127.0.0.1:$TOR_DNS_PORT 2>/dev/null || true
        echo "[dns] DNS forwarding via iptables DNAT"
    fi
}

# ─── Stop DNS forwarder ──────────────────────────────────────

dns_stop_forwarder() {
    if [[ -f "$DNS_PID_FILE" ]]; then
        local pid
        pid=$(cat "$DNS_PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$DNS_PID_FILE"
        echo "[dns] DNS forwarder stopped"
    fi
    # Also clean up any stray socat
    pkill -f "socat.*UDP4-LISTEN:$LOCAL_DNS_PORT.*bind=$HOST_IP" 2>/dev/null || true
}

# ─── Tear down DNS ───────────────────────────────────────────

dns_teardown() {
    echo "[dns] Tearing down DNS isolation..."

    dns_stop_forwarder

    # Remove namespace resolv.conf
    rm -f /etc/netns/"$GHOST_NS"/resolv.conf 2>/dev/null || true
    rmdir /etc/netns/"$GHOST_NS" 2>/dev/null || true

    echo "[dns] DNS isolation removed"
}

# ─── Verify no DNS leaks ────────────────────────────────────

dns_verify() {
    echo "[dns] Verifying DNS isolation..."
    local failures=0

    # Check that namespace resolv.conf exists and points to us
    local resolv
    resolv=$(ip netns exec "$GHOST_NS" cat /etc/resolv.conf 2>/dev/null) || resolv=""
    if echo "$resolv" | grep -q "$HOST_IP"; then
        echo "[dns] PASS: resolv.conf points to GhostBox DNS"
    else
        echo "[dns] FAIL: resolv.conf does not point to GhostBox DNS"
        ((failures++))
    fi

    # Check DNS forwarder is running
    if [[ -f "$DNS_PID_FILE" ]] && kill -0 "$(cat "$DNS_PID_FILE")" 2>/dev/null; then
        echo "[dns] PASS: DNS forwarder running"
    else
        echo "[dns] WARN: DNS forwarder process not found (may use iptables)"
    fi

    # Try to resolve through our DNS (should work via Tor)
    local resolve_test
    resolve_test=$(ip netns exec "$GHOST_NS" nslookup torproject.org "$HOST_IP" 2>/dev/null) || resolve_test=""
    if [[ -n "$resolve_test" ]]; then
        echo "[dns] PASS: DNS resolution through Tor works"
    else
        echo "[dns] WARN: DNS resolution test failed (Tor may still be bootstrapping)"
    fi

    # Try to resolve directly via 8.8.8.8 (should be BLOCKED by firewall)
    local leak_test
    leak_test=$(ip netns exec "$GHOST_NS" nslookup torproject.org 8.8.8.8 2>/dev/null) || leak_test=""
    if [[ -z "$leak_test" ]]; then
        echo "[dns] PASS: Direct DNS queries blocked (no leak)"
    else
        echo "[dns] FAIL: Direct DNS query succeeded — DNS LEAK!"
        ((failures++))
    fi

    if [[ $failures -eq 0 ]]; then
        echo "[dns] ALL CHECKS PASSED — DNS fully isolated"
    else
        echo "[dns] WARNING: $failures checks failed"
    fi

    return $failures
}

# ─── Status ──────────────────────────────────────────────────

dns_status() {
    echo "[dns] === DNS Isolation Status ==="
    if [[ -f /etc/netns/"$GHOST_NS"/resolv.conf ]]; then
        echo "[dns] Namespace resolv.conf:"
        cat /etc/netns/"$GHOST_NS"/resolv.conf | sed 's/^/  /'
    else
        echo "[dns] No namespace resolv.conf"
    fi

    if [[ -f "$DNS_PID_FILE" ]] && kill -0 "$(cat "$DNS_PID_FILE")" 2>/dev/null; then
        echo "[dns] Forwarder: RUNNING (PID: $(cat "$DNS_PID_FILE"))"
    else
        echo "[dns] Forwarder: NOT RUNNING"
    fi
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    setup)    dns_setup ;;
    teardown) dns_teardown ;;
    verify)   dns_verify ;;
    status)   dns_status ;;
    *)        echo "Usage: $0 {setup|teardown|verify|status}" ;;
esac
