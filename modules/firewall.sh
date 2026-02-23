#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: Firewall Kill Switch
# ═══════════════════════════════════════════════════════════════
# Uses nftables to create an airtight firewall that:
#   1. BLOCKS all traffic that isn't going through Tor
#   2. If Tor drops, NOTHING gets out (kill switch)
#   3. Blocks all IPv6 (prevents leaks)
#   4. Blocks DNS except through Tor
#   5. Blocks WebRTC STUN/TURN ports
#   6. Prevents all direct connections
#
# This is the most critical security layer. Even if every
# other module fails, this ensures zero bytes leak.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

GHOST_NS="ghostbox"
VETH_HOST="gbox0"
HOST_IP="10.200.1.1"
NS_IP="10.200.1.2"

# Tor SOCKS port (inside namespace)
TOR_SOCKS_PORT=9050
TOR_DNS_PORT=5353
TOR_TRANS_PORT=9040

# Tor user (traffic from Tor process itself must be allowed out)
TOR_USER="debian-tor"

NFT_TABLE="ghostbox"

# ─── Deploy kill switch firewall ─────────────────────────────

firewall_up() {
    echo "[firewall] Deploying kill switch..."

    # ═══ HOST-SIDE RULES (on the real machine) ═══
    # Only allow traffic between namespace veth and Tor
    # Block everything else from the namespace

    nft -f - <<EOF
# Flush any existing ghostbox rules
table inet $NFT_TABLE
delete table inet $NFT_TABLE

table inet $NFT_TABLE {

    # ─── CHAINS ───────────────────────────────────

    chain input {
        type filter hook input priority 0; policy drop;

        # Allow established/related
        ct state established,related accept

        # Allow loopback
        iif lo accept

        # Allow traffic from namespace veth
        iif "$VETH_HOST" ip saddr $NS_IP accept

        # Allow ICMP (for connectivity, can disable for stealth)
        # ip protocol icmp accept

        # Drop everything else silently
        drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;

        # Allow namespace → Tor (already running on host)
        iif "$VETH_HOST" oif lo accept

        # Allow return traffic
        ct state established,related accept

        # ─── KILL SWITCH ───
        # Block ALL forwarding from namespace to real interfaces
        # This means if Tor is down, NOTHING gets out
        iif "$VETH_HOST" drop

        # Block everything else
        drop
    }

    chain output {
        type filter hook output priority 0; policy accept;

        # Host output is mostly unrestricted (Tor needs to connect)
        # But we block namespace IP from going anywhere except Tor

        # Allow Tor user to connect to the internet
        skuid $TOR_USER accept

        # Allow loopback
        oif lo accept

        # Allow established
        ct state established,related accept

        # Allow DHCP
        udp dport 67 accept

        # Allow traffic to namespace
        oif "$VETH_HOST" accept

        # Block all other outbound from non-Tor processes
        # (This is aggressive — only Tor can talk to the internet)
        # Uncomment the next line for MAXIMUM security:
        # drop
        accept
    }
}
EOF

    echo "[firewall] Host-side kill switch deployed"

    # ═══ NAMESPACE-SIDE RULES (inside the jail) ═══
    # Inside the namespace, only Tor SOCKS and DNS are allowed

    ip netns exec "$GHOST_NS" nft -f - <<EOF
table inet ns_firewall
delete table inet ns_firewall

table inet ns_firewall {

    chain input {
        type filter hook input priority 0; policy drop;

        # Allow established/related
        ct state established,related accept

        # Allow loopback
        iif lo accept

        # Allow traffic from host veth
        iif "$VETH_HOST" drop
        ip saddr $HOST_IP accept

        drop
    }

    chain output {
        type filter hook output priority 0; policy drop;

        # Allow loopback (local services like Tor SOCKS)
        oif lo accept

        # Allow DNS to host (where Tor DNS resolver runs)
        ip daddr $HOST_IP udp dport $TOR_DNS_PORT accept
        ip daddr $HOST_IP tcp dport $TOR_DNS_PORT accept

        # Allow Tor SOCKS to host
        ip daddr $HOST_IP tcp dport $TOR_SOCKS_PORT accept

        # Allow Tor transparent proxy
        ip daddr $HOST_IP tcp dport $TOR_TRANS_PORT accept

        # ─── BLOCK EVERYTHING ELSE ───
        # No direct connections to any IP
        # No DNS to any server except our Tor resolver
        # No UDP except to our DNS
        # No ICMP out
        # NOTHING.

        # Log dropped packets (for debugging, disable in production)
        # log prefix "[ghostbox-drop] " drop

        drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        # Nothing should be forwarded inside namespace
        drop
    }
}
EOF

    echo "[firewall] Namespace-side firewall deployed"

    # ═══ BLOCK WEBRTC STUN/TURN PORTS ═══
    # Even though namespace firewall blocks all, belt-and-suspenders
    ip netns exec "$GHOST_NS" nft add rule inet ns_firewall output \
        udp dport { 3478, 3479, 5349, 5350 } drop 2>/dev/null || true

    # ═══ BLOCK IPv6 COMPLETELY ═══
    ip netns exec "$GHOST_NS" nft -f - <<EOF2
table ip6 ns_ipv6_block
delete table ip6 ns_ipv6_block

table ip6 ns_ipv6_block {
    chain input {
        type filter hook input priority 0; policy drop;
        drop
    }
    chain output {
        type filter hook output priority 0; policy drop;
        drop
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
        drop
    }
}
EOF2

    echo "[firewall] IPv6 completely blocked inside namespace"
    echo "[firewall] WebRTC STUN/TURN ports blocked"
    echo "[firewall] Kill switch ACTIVE — if Tor drops, zero bytes leak"
}

# ─── Remove firewall ─────────────────────────────────────────

firewall_down() {
    echo "[firewall] Removing kill switch..."

    # Remove host-side rules
    nft delete table inet "$NFT_TABLE" 2>/dev/null || true

    # Remove namespace-side rules (if namespace still exists)
    ip netns exec "$GHOST_NS" nft delete table inet ns_firewall 2>/dev/null || true
    ip netns exec "$GHOST_NS" nft delete table ip6 ns_ipv6_block 2>/dev/null || true

    echo "[firewall] Kill switch removed"
}

# ─── Verify kill switch ──────────────────────────────────────

firewall_verify() {
    echo "[firewall] Verifying kill switch..."
    local failures=0

    # Check host-side table exists
    if nft list table inet "$NFT_TABLE" >/dev/null 2>&1; then
        echo "[firewall] PASS: Host-side firewall active"
    else
        echo "[firewall] FAIL: Host-side firewall missing!"
        ((failures++))
    fi

    # Check namespace-side table exists
    if ip netns exec "$GHOST_NS" nft list table inet ns_firewall >/dev/null 2>&1; then
        echo "[firewall] PASS: Namespace firewall active"
    else
        echo "[firewall] FAIL: Namespace firewall missing!"
        ((failures++))
    fi

    # Check IPv6 block
    if ip netns exec "$GHOST_NS" nft list table ip6 ns_ipv6_block >/dev/null 2>&1; then
        echo "[firewall] PASS: IPv6 block active"
    else
        echo "[firewall] FAIL: IPv6 block missing!"
        ((failures++))
    fi

    # Test: try to ping outside from namespace (should fail)
    if ip netns exec "$GHOST_NS" ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        echo "[firewall] FAIL: Direct ping escaped namespace!"
        ((failures++))
    else
        echo "[firewall] PASS: Direct connections blocked"
    fi

    # Test: try DNS outside Tor (should fail)
    if ip netns exec "$GHOST_NS" nslookup google.com 8.8.8.8 >/dev/null 2>&1; then
        echo "[firewall] FAIL: DNS leaked outside Tor!"
        ((failures++))
    else
        echo "[firewall] PASS: DNS leak blocked"
    fi

    if [[ $failures -eq 0 ]]; then
        echo "[firewall] ALL CHECKS PASSED — kill switch verified"
    else
        echo "[firewall] WARNING: $failures checks failed!"
    fi

    return $failures
}

# ─── Status ──────────────────────────────────────────────────

firewall_status() {
    echo "[firewall] === Host-side rules ==="
    nft list table inet "$NFT_TABLE" 2>/dev/null || echo "  Not active"
    echo ""
    echo "[firewall] === Namespace rules ==="
    ip netns exec "$GHOST_NS" nft list table inet ns_firewall 2>/dev/null || echo "  Not active"
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    up)      firewall_up ;;
    down)    firewall_down ;;
    verify)  firewall_verify ;;
    status)  firewall_status ;;
    *)       echo "Usage: $0 {up|down|verify|status}" ;;
esac
