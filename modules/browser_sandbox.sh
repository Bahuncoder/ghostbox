#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: Browser Sandbox
# ═══════════════════════════════════════════════════════════════
# Launches browser inside the network namespace with:
#   - Full identity spoofing (from identity engine)
#   - RAM-based profile (no disk persistence)
#   - WebRTC disabled
#   - All privacy extensions pre-configured
#   - Proxy set to Tor SOCKS
#   - Hardened preferences
#
# The browser physically cannot reach the internet except
# through Tor — it's running in a namespace where the real
# network doesn't exist.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/configs"
GHOST_NS="ghostbox"
HOST_IP="10.200.1.1"
TOR_SOCKS_PORT=9050

RAM_PROFILE_DIR="/dev/shm/ghostbox_browser"

# ─── Create hardened Chrome/Chromium profile ─────────────────

create_chrome_profile() {
    local profile_dir="$RAM_PROFILE_DIR/chrome-profile"
    mkdir -p "$profile_dir/Default"

    # Load identity environment
    local identity_env
    identity_env=$("$SCRIPT_DIR/identity_engine.py" export-env 2>/dev/null) || true

    if [[ -n "$identity_env" ]]; then
        eval "$identity_env"
    fi

    # Chrome preferences — maximum privacy
    cat > "$profile_dir/Default/Preferences" <<EOF
{
  "browser": {
    "enable_spellchecking": false,
    "has_seen_welcome_page": true
  },
  "download": {
    "default_directory": "/dev/shm/ghostbox_downloads",
    "prompt_for_download": true
  },
  "net": {
    "network_prediction_options": 2
  },
  "profile": {
    "default_content_setting_values": {
      "geolocation": 2,
      "media_stream_camera": 2,
      "media_stream_mic": 2,
      "notifications": 2,
      "sensors": 2,
      "usb_guard": 2,
      "bluetooth_guard": 2,
      "serial_guard": 2,
      "hid_guard": 2,
      "clipboard": 2
    }
  },
  "safebrowsing": {
    "enabled": false,
    "enhanced": false
  },
  "search": {
    "suggest_enabled": false
  },
  "signin": {
    "allowed": false
  },
  "translate": {
    "enabled": false
  },
  "webkit": {
    "webprefs": {
      "WebRTCIPHandlingPolicy": "disable_non_proxied_udp"
    }
  }
}
EOF

    # Local State
    cat > "$profile_dir/Local State" <<EOF
{
  "dns_over_https": {
    "mode": "off"
  },
  "hardware_acceleration_mode_previous": false
}
EOF

    echo "$profile_dir"
}

# ─── Create hardened Firefox profile ─────────────────────────

create_firefox_profile() {
    local profile_dir="$RAM_PROFILE_DIR/firefox-profile"
    mkdir -p "$profile_dir"

    # Load identity
    local identity_env
    identity_env=$("$SCRIPT_DIR/identity_engine.py" export-env 2>/dev/null) || true
    if [[ -n "$identity_env" ]]; then
        eval "$identity_env"
    fi

    # user.js — hardened Firefox preferences (based on arkenfox)
    cat > "$profile_dir/user.js" <<'EOF'
// ═══ GhostBox Firefox Hardening ═══
// Based on arkenfox user.js with maximum privacy

// ─── Startup ─────────────────────────────
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.startup.page", 0);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtab.preload", false);

// ─── Geolocation ─────────────────────────
user_pref("geo.enabled", false);
user_pref("geo.wifi.uri", "");
user_pref("browser.search.geoip.url", "");

// ─── Language/Locale (handled by identity engine) ───
user_pref("privacy.spoof_english", 2);

// ─── Telemetry OFF ───────────────────────
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.server", "");
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("app.shield.optoutstudies.enabled", false);

// ─── WebRTC DISABLED ─────────────────────
user_pref("media.peerconnection.enabled", false);
user_pref("media.peerconnection.ice.default_address_only", true);
user_pref("media.peerconnection.ice.no_host", true);
user_pref("media.peerconnection.ice.proxy_only_if_behind_proxy", true);

// ─── Camera/Mic BLOCKED ─────────────────
user_pref("media.navigator.enabled", false);
user_pref("media.navigator.video.enabled", false);
user_pref("media.autoplay.default", 5);

// ─── DNS ─────────────────────────────────
user_pref("network.dns.disablePrefetch", true);
user_pref("network.dns.disableIPv6", true);
user_pref("network.predictor.enabled", false);
user_pref("network.prefetch-next", false);

// ─── Proxy (Tor SOCKS) ──────────────────
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "10.200.1.1");
user_pref("network.proxy.socks_port", 9050);
user_pref("network.proxy.socks_version", 5);
user_pref("network.proxy.socks_remote_dns", true);
user_pref("network.proxy.no_proxies_on", "");

// ─── Cookies/Tracking ───────────────────
user_pref("network.cookie.cookieBehavior", 1);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.firstparty.isolate", true);
user_pref("privacy.resistFingerprinting", true);
user_pref("privacy.resistFingerprinting.letterboxing", true);

// ─── HTTPS ──────────────────────────────
user_pref("dom.security.https_only_mode", true);
user_pref("dom.security.https_only_mode_send_http_background_request", false);

// ─── Cache/History ──────────────────────
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 65536);
user_pref("browser.sessionhistory.max_entries", 2);
user_pref("places.history.enabled", false);
user_pref("browser.formfill.enable", false);
user_pref("signon.rememberSignons", false);
user_pref("browser.download.manager.addToRecentDocs", false);

// ─── Fingerprinting Resistance ──────────
user_pref("privacy.resistFingerprinting", true);
user_pref("webgl.disabled", false);
user_pref("media.eme.enabled", false);
user_pref("dom.battery.enabled", false);
user_pref("dom.vr.enabled", false);
user_pref("dom.gamepad.enabled", false);
user_pref("dom.netinfo.enabled", false);
user_pref("dom.vibrator.enabled", false);

// ─── Safe Browsing OFF (sends URLs to Google) ───
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.safebrowsing.downloads.enabled", false);

// ─── Misc ───────────────────────────────
user_pref("accessibility.force_disabled", 1);
user_pref("browser.send_pings", false);
user_pref("beacon.enabled", false);
user_pref("device.sensors.enabled", false);
user_pref("dom.webaudio.enabled", false);
EOF

    echo "$profile_dir"
}

# ─── Launch Chrome in namespace ──────────────────────────────

launch_chrome() {
    echo "[browser] Launching Chrome inside GhostBox namespace..."

    local profile_dir
    profile_dir=$(create_chrome_profile)
    mkdir -p /dev/shm/ghostbox_downloads

    # Generate and deploy spoof JS
    python3 "$SCRIPT_DIR/identity_engine.py" export-js 2>/dev/null || true

    # Chrome flags for maximum privacy
    local chrome_cmd="google-chrome"
    command -v google-chrome-stable >/dev/null 2>&1 && chrome_cmd="google-chrome-stable"
    command -v chromium-browser >/dev/null 2>&1 && chrome_cmd="chromium-browser"
    command -v chromium >/dev/null 2>&1 && chrome_cmd="chromium"

    local spoof_ext="$CONFIG_DIR/browser_profile"

    ip netns exec "$GHOST_NS" \
        env HOME="/dev/shm/ghostbox_home" \
            TZ="${GHOST_TZ:-UTC}" \
            LANG="${GHOST_LOCALE:-en_US.UTF-8}" \
            LC_ALL="${GHOST_LOCALE:-en_US.UTF-8}" \
        "$chrome_cmd" \
        --user-data-dir="$profile_dir" \
        --no-first-run \
        --no-default-browser-check \
        --disable-background-networking \
        --disable-breakpad \
        --disable-client-side-phishing-detection \
        --disable-component-update \
        --disable-default-apps \
        --disable-domain-reliability \
        --disable-features=AutofillServerCommunication,SafeBrowsing \
        --disable-hang-monitor \
        --disable-logging \
        --disable-notifications \
        --disable-permissions-api \
        --disable-popup-blocking \
        --disable-prompt-on-repost \
        --disable-sync \
        --disable-translate \
        --disable-web-security=false \
        --dns-prefetch-disable \
        --incognito \
        --no-pings \
        --proxy-server="socks5://$HOST_IP:$TOR_SOCKS_PORT" \
        --host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE $HOST_IP" \
        --disable-webrtc-hw-encoding \
        --disable-webrtc-hw-decoding \
        --enforce-webrtc-ip-permission-check \
        --force-webrtc-ip-handling-policy=disable_non_proxied_udp \
        --disable-reading-from-canvas \
        --disable-remote-fonts \
        --disable-gpu-sandbox \
        --disable-accelerated-2d-canvas \
        --load-extension="$spoof_ext" \
        --window-size="${GHOST_SCREEN_W:-1920},${GHOST_SCREEN_H:-1080}" \
        2>/dev/null &

    echo "[browser] Chrome launched (PID: $!)"
    echo "[browser] Profile: $profile_dir (RAM only — no disk)"
    echo "[browser] Proxy: socks5://$HOST_IP:$TOR_SOCKS_PORT"
    echo "[browser] WebRTC: DISABLED"
    echo "[browser] All traffic goes through Tor"
}

# ─── Launch Firefox in namespace ─────────────────────────────

launch_firefox() {
    echo "[browser] Launching Firefox inside GhostBox namespace..."

    local profile_dir
    profile_dir=$(create_firefox_profile)
    mkdir -p /dev/shm/ghostbox_downloads

    ip netns exec "$GHOST_NS" \
        env HOME="/dev/shm/ghostbox_home" \
            TZ="${GHOST_TZ:-UTC}" \
            LANG="${GHOST_LOCALE:-en_US.UTF-8}" \
            LC_ALL="${GHOST_LOCALE:-en_US.UTF-8}" \
        firefox \
        --profile "$profile_dir" \
        --no-remote \
        --private-window \
        2>/dev/null &

    echo "[browser] Firefox launched (PID: $!)"
    echo "[browser] Profile: $profile_dir (RAM only — no disk)"
    echo "[browser] Proxy: socks5://$HOST_IP:$TOR_SOCKS_PORT (via user.js)"
    echo "[browser] WebRTC: DISABLED"
}

# ─── Cleanup browser data ───────────────────────────────────

browser_cleanup() {
    echo "[browser] Securely wiping browser data..."

    # Kill any browsers in namespace
    ip netns exec "$GHOST_NS" pkill -9 chrome 2>/dev/null || true
    ip netns exec "$GHOST_NS" pkill -9 chromium 2>/dev/null || true
    ip netns exec "$GHOST_NS" pkill -9 firefox 2>/dev/null || true

    sleep 1

    # Securely wipe RAM profile
    if [[ -d "$RAM_PROFILE_DIR" ]]; then
        find "$RAM_PROFILE_DIR" -type f -exec shred -n 3 -z -u {} \; 2>/dev/null || true
        rm -rf "$RAM_PROFILE_DIR"
    fi

    # Wipe downloads
    if [[ -d /dev/shm/ghostbox_downloads ]]; then
        find /dev/shm/ghostbox_downloads -type f -exec shred -n 3 -z -u {} \; 2>/dev/null || true
        rm -rf /dev/shm/ghostbox_downloads
    fi

    # Wipe home
    rm -rf /dev/shm/ghostbox_home 2>/dev/null || true

    echo "[browser] All browser data wiped from RAM"
}

# ─── Status ──────────────────────────────────────────────────

browser_status() {
    echo "[browser] === Browser Status ==="
    local chrome_pids firefox_pids
    chrome_pids=$(ip netns exec "$GHOST_NS" pgrep -a chrome 2>/dev/null) || chrome_pids=""
    firefox_pids=$(ip netns exec "$GHOST_NS" pgrep -a firefox 2>/dev/null) || firefox_pids=""

    if [[ -n "$chrome_pids" ]]; then
        echo "[browser] Chrome: RUNNING"
        echo "$chrome_pids" | head -3 | sed 's/^/  /'
    fi
    if [[ -n "$firefox_pids" ]]; then
        echo "[browser] Firefox: RUNNING"
        echo "$firefox_pids" | head -3 | sed 's/^/  /'
    fi
    if [[ -z "$chrome_pids" && -z "$firefox_pids" ]]; then
        echo "[browser] No browsers running in namespace"
    fi

    if [[ -d "$RAM_PROFILE_DIR" ]]; then
        local size
        size=$(du -sh "$RAM_PROFILE_DIR" 2>/dev/null | cut -f1) || size="?"
        echo "[browser] RAM profile: $size"
    fi
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    chrome)  launch_chrome ;;
    firefox) launch_firefox ;;
    cleanup) browser_cleanup ;;
    status)  browser_status ;;
    *)       echo "Usage: $0 {chrome|firefox|cleanup|status}" ;;
esac
