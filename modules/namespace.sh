#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: Network Namespace Isolation
# ═══════════════════════════════════════════════════════════════
# Creates a kernel-level network jail. The OS inside this
# namespace cannot see or touch real network interfaces.
# Only a virtual ethernet pair connects it to the outside,
# and that pair goes through Tor only.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

GHOST_NS="ghostbox"
VETH_HOST="gbox0"
VETH_NS="gbox1"
HOST_IP="10.200.1.1"
NS_IP="10.200.1.2"
SUBNET="10.200.1.0/24"

# ─── Create the isolated namespace ───────────────────────────

namespace_create() {
    echo "[namespace] Creating isolated network namespace..."

    # Create namespace
    ip netns add "$GHOST_NS" 2>/dev/null || true

    # Create virtual ethernet pair (like a virtual cable)
    ip link add "$VETH_HOST" type veth peer name "$VETH_NS" 2>/dev/null || true

    # Move one end into the namespace
    ip link set "$VETH_NS" netns "$GHOST_NS"

    # Configure host side
    ip addr add "$HOST_IP/24" dev "$VETH_HOST" 2>/dev/null || true
    ip link set "$VETH_HOST" up

    # Configure namespace side
    ip netns exec "$GHOST_NS" ip addr add "$NS_IP/24" dev "$VETH_NS" 2>/dev/null || true
    ip netns exec "$GHOST_NS" ip link set "$VETH_NS" up
    ip netns exec "$GHOST_NS" ip link set lo up

    # Default route inside namespace goes through host veth
    ip netns exec "$GHOST_NS" ip route add default via "$HOST_IP" 2>/dev/null || true

    # Enable IP forwarding on host (required for NAT)
    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    # Disable IPv6 inside namespace (prevents leaks)
    ip netns exec "$GHOST_NS" sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
    ip netns exec "$GHOST_NS" sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

    # Set random hostname inside namespace
    local fake_host
    fake_host="desktop-$(head -c 4 /dev/urandom | xxd -p)"
    ip netns exec "$GHOST_NS" hostname "$fake_host" 2>/dev/null || true

    echo "[namespace] Namespace '$GHOST_NS' created"
    echo "[namespace] Host side: $VETH_HOST ($HOST_IP)"
    echo "[namespace] NS side:   $VETH_NS ($NS_IP)"
    echo "[namespace] Fake hostname: $fake_host"
    echo "[namespace] IPv6: disabled (leak prevention)"
}

# ─── Destroy the namespace ───────────────────────────────────

namespace_destroy() {
    echo "[namespace] Destroying namespace..."

    # Kill all processes inside namespace
    local pids
    pids=$(ip netns pids "$GHOST_NS" 2>/dev/null) || true
    if [[ -n "$pids" ]]; then
        echo "[namespace] Killing processes inside namespace: $pids"
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 1
    fi

    # Delete veth pair (deleting one end removes both)
    ip link del "$VETH_HOST" 2>/dev/null || true

    # Delete namespace
    ip netns del "$GHOST_NS" 2>/dev/null || true

    echo "[namespace] Namespace destroyed"
}

# ─── Execute command inside namespace ────────────────────────

namespace_exec() {
    ip netns exec "$GHOST_NS" "$@"
}

# ─── Check if namespace exists ───────────────────────────────

namespace_exists() {
    ip netns list 2>/dev/null | grep -qw "$GHOST_NS"
}

# ─── Status ──────────────────────────────────────────────────

namespace_status() {
    if namespace_exists; then
        echo "[namespace] Status: ACTIVE"
        echo "[namespace] Interfaces inside namespace:"
        ip netns exec "$GHOST_NS" ip addr show 2>/dev/null | grep -E "inet |link/" | sed 's/^/  /'
        echo "[namespace] Routes inside namespace:"
        ip netns exec "$GHOST_NS" ip route show 2>/dev/null | sed 's/^/  /'
        echo "[namespace] Processes inside namespace:"
        local pids
        pids=$(ip netns pids "$GHOST_NS" 2>/dev/null) || true
        if [[ -n "$pids" ]]; then
            echo "  PIDs: $pids"
        else
            echo "  No processes"
        fi
    else
        echo "[namespace] Status: INACTIVE"
    fi
}

# ─── Verify isolation ────────────────────────────────────────

namespace_verify() {
    if ! namespace_exists; then
        echo "[namespace] FAIL: Namespace does not exist"
        return 1
    fi

    # Verify real interfaces are NOT visible inside namespace
    local real_ifs
    real_ifs=$(ip netns exec "$GHOST_NS" ip link show 2>/dev/null | grep -cE "enp|wlp|eth|wlan") || true
    if [[ "$real_ifs" -gt 0 ]]; then
        echo "[namespace] FAIL: Real interfaces visible inside namespace!"
        return 1
    fi

    # Verify only our veth + loopback exist
    local ns_ifs
    ns_ifs=$(ip netns exec "$GHOST_NS" ip link show 2>/dev/null | grep -cE "^[0-9]+:") || true
    if [[ "$ns_ifs" -le 2 ]]; then
        echo "[namespace] PASS: Only virtual interfaces visible (isolated)"
    else
        echo "[namespace] WARN: Unexpected interfaces detected"
    fi

    # Verify IPv6 is disabled
    local ipv6
    ipv6=$(ip netns exec "$GHOST_NS" sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) || true
    if [[ "$ipv6" == "1" ]]; then
        echo "[namespace] PASS: IPv6 disabled"
    else
        echo "[namespace] WARN: IPv6 may be active (leak risk)"
    fi

    return 0
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    create)  namespace_create ;;
    destroy) namespace_destroy ;;
    exec)    shift; namespace_exec "$@" ;;
    status)  namespace_status ;;
    verify)  namespace_verify ;;
    *)       echo "Usage: $0 {create|destroy|exec|status|verify}" ;;
esac
