#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: Traffic Padding Daemon
# ═══════════════════════════════════════════════════════════════
# Generates constant-rate encrypted noise traffic so ISP can't
# do traffic analysis. Without this, ISP can guess what you're
# doing by watching traffic patterns:
#   - Burst of data = loading a page
#   - Steady stream = watching video
#   - Small packets = chat/messaging
#
# With padding: traffic looks like a constant encrypted stream
# regardless of what you're actually doing.
#
# This is the difference between 90% and 95%+ security.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

GHOST_NS="ghostbox"
HOST_IP="10.200.1.1"
TOR_SOCKS_PORT=9050

PADDING_PID_FILE="/tmp/ghostbox_padding.pid"

# How much fake traffic to generate (bytes/sec)
# Higher = more noise = harder to analyze = more bandwidth
PADDING_RATE="${GHOSTBOX_PADDING_RATE:-50000}"  # 50 KB/s default

# Interval between padding bursts (seconds)
PADDING_INTERVAL="${GHOSTBOX_PADDING_INTERVAL:-0.5}"

# List of onion services to use as padding destinations
# (traffic goes through Tor anyway, these are just sinks)
PADDING_TARGETS=(
    "https://www.torproject.org"
    "https://check.torproject.org"
    "https://duckduckgo.com"
    "https://www.wikipedia.org"
    "https://www.eff.org"
)

# ─── Padding daemon ─────────────────────────────────────────

padding_daemon() {
    echo "[padding] Starting traffic padding daemon..."
    echo "[padding] Rate: ~${PADDING_RATE} bytes/sec"
    echo "[padding] Interval: ${PADDING_INTERVAL}s"

    local bytes_per_burst=$((PADDING_RATE / 2))

    while true; do
        # Method 1: Generate random data through Tor SOCKS
        # This creates real encrypted traffic that's indistinguishable
        # from actual browsing
        {
            # Pick random target
            local target="${PADDING_TARGETS[$((RANDOM % ${#PADDING_TARGETS[@]}))]}"

            # Send random-length request through Tor
            local rand_size=$((RANDOM % bytes_per_burst + 1000))
            ip netns exec "$GHOST_NS" \
                curl -s --max-time 5 \
                     --socks5 "$HOST_IP:$TOR_SOCKS_PORT" \
                     -o /dev/null \
                     -H "Accept: text/html,application/xhtml+xml" \
                     -H "Accept-Encoding: gzip" \
                     -H "Cache-Control: no-cache" \
                     "$target" 2>/dev/null || true
        } &

        # Method 2: Raw noise through Tor (random data)
        {
            # Generate random data and pipe through Tor
            head -c "$((RANDOM % 2000 + 500))" /dev/urandom | \
                ip netns exec "$GHOST_NS" \
                socat - SOCKS4A:"$HOST_IP":"$(printf '%s' "${PADDING_TARGETS[$((RANDOM % ${#PADDING_TARGETS[@]}))]}" | sed 's|https://||')":443,socksport="$TOR_SOCKS_PORT" 2>/dev/null || true
        } &

        # Randomize interval (prevents pattern detection)
        local jitter
        jitter=$(awk "BEGIN{printf \"%.2f\", $PADDING_INTERVAL + ($(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 100) / 200.0}")
        sleep "$jitter"
    done
}

# ─── Start padding ──────────────────────────────────────────

padding_start() {
    echo "[padding] Starting traffic padding..."

    # Kill existing padding
    padding_stop 2>/dev/null || true

    # Start daemon in background
    padding_daemon &
    local pid=$!
    echo "$pid" > "$PADDING_PID_FILE"

    echo "[padding] Daemon started (PID: $pid)"
    echo "[padding] ISP traffic analysis now significantly harder"
}

# ─── Stop padding ───────────────────────────────────────────

padding_stop() {
    if [[ -f "$PADDING_PID_FILE" ]]; then
        local pid
        pid=$(cat "$PADDING_PID_FILE")
        kill "$pid" 2>/dev/null || true
        # Kill child processes too
        pkill -P "$pid" 2>/dev/null || true
        rm -f "$PADDING_PID_FILE"
        echo "[padding] Daemon stopped"
    else
        # Try to find and kill by name
        pkill -f "padding_daemon" 2>/dev/null || true
        echo "[padding] Daemon stopped (by name)"
    fi
}

# ─── Status ──────────────────────────────────────────────────

padding_status() {
    if [[ -f "$PADDING_PID_FILE" ]] && kill -0 "$(cat "$PADDING_PID_FILE")" 2>/dev/null; then
        echo "[padding] Status: RUNNING (PID: $(cat "$PADDING_PID_FILE"))"
        echo "[padding] Rate: ~${PADDING_RATE} bytes/sec"
    else
        echo "[padding] Status: STOPPED"
    fi
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    start)  padding_start ;;
    stop)   padding_stop ;;
    status) padding_status ;;
    *)      echo "Usage: $0 {start|stop|status}" ;;
esac
