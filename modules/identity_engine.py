#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════════
GhostBox Module: Identity Engine
═══════════════════════════════════════════════════════════════
Generates CONSISTENT fake identities. All components match:
  - If exit node is in Tokyo → timezone=Asia/Tokyo,
    language=ja-JP, geolocation=Tokyo area, etc.

Rotates everything together every N seconds so all signals
are coherent and don't contradict each other.

This is what makes tracking nearly impossible — every few
seconds you become a completely different person in a
completely different place.
═══════════════════════════════════════════════════════════════
"""

import json
import math
import os
import random
import string
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
STATE_FILE = SCRIPT_DIR.parent / "configs" / ".identity_state.json"

# ═══════════════════════════════════════════════════════════════
# IDENTITY DATABASE
# Each region has consistent: locations, timezones, languages,
# user agents, screen resolutions, platform strings
# ═══════════════════════════════════════════════════════════════

IDENTITIES = {
    "us-east": {
        "name": "US East Coast",
        "tor_exit_country": "{us}",
        "cities": [
            {"lat": 40.7128, "lon": -74.0060, "radius": 30, "name": "New York"},
            {"lat": 38.9072, "lon": -77.0369, "radius": 25, "name": "Washington DC"},
            {"lat": 42.3601, "lon": -71.0589, "radius": 20, "name": "Boston"},
            {"lat": 39.9526, "lon": -75.1652, "radius": 18, "name": "Philadelphia"},
            {"lat": 25.7617, "lon": -80.1918, "radius": 20, "name": "Miami"},
        ],
        "timezones": ["America/New_York", "America/Chicago"],
        "languages": ["en-US", "en"],
        "locales": ["en_US.UTF-8"],
        "accept_language": "en-US,en;q=0.9",
    },
    "us-west": {
        "name": "US West Coast",
        "tor_exit_country": "{us}",
        "cities": [
            {"lat": 34.0522, "lon": -118.2437, "radius": 35, "name": "Los Angeles"},
            {"lat": 37.7749, "lon": -122.4194, "radius": 20, "name": "San Francisco"},
            {"lat": 47.6062, "lon": -122.3321, "radius": 22, "name": "Seattle"},
            {"lat": 45.5152, "lon": -122.6784, "radius": 18, "name": "Portland"},
        ],
        "timezones": ["America/Los_Angeles"],
        "languages": ["en-US", "en"],
        "locales": ["en_US.UTF-8"],
        "accept_language": "en-US,en;q=0.9",
    },
    "europe-west": {
        "name": "Western Europe",
        "tor_exit_country": "{de},{nl},{fr},{gb}",
        "cities": [
            {"lat": 51.5074, "lon": -0.1278, "radius": 25, "name": "London"},
            {"lat": 48.8566, "lon": 2.3522, "radius": 20, "name": "Paris"},
            {"lat": 52.3676, "lon": 4.9041, "radius": 15, "name": "Amsterdam"},
            {"lat": 52.5200, "lon": 13.4050, "radius": 22, "name": "Berlin"},
        ],
        "timezones": ["Europe/London", "Europe/Paris", "Europe/Berlin", "Europe/Amsterdam"],
        "languages": ["en-GB", "en", "de", "fr", "nl"],
        "locales": ["en_GB.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8"],
        "accept_language": "en-GB,en;q=0.9,de;q=0.8",
    },
    "europe-north": {
        "name": "Northern Europe",
        "tor_exit_country": "{se},{no},{fi},{dk}",
        "cities": [
            {"lat": 59.3293, "lon": 18.0686, "radius": 18, "name": "Stockholm"},
            {"lat": 59.9139, "lon": 10.7522, "radius": 15, "name": "Oslo"},
            {"lat": 60.1699, "lon": 24.9384, "radius": 15, "name": "Helsinki"},
            {"lat": 55.6761, "lon": 12.5683, "radius": 15, "name": "Copenhagen"},
        ],
        "timezones": ["Europe/Stockholm", "Europe/Oslo", "Europe/Helsinki"],
        "languages": ["en", "sv", "no", "fi", "da"],
        "locales": ["en_US.UTF-8", "sv_SE.UTF-8"],
        "accept_language": "en,sv;q=0.9",
    },
    "asia-east": {
        "name": "East Asia",
        "tor_exit_country": "{jp},{kr},{sg}",
        "cities": [
            {"lat": 35.6762, "lon": 139.6503, "radius": 30, "name": "Tokyo"},
            {"lat": 37.5665, "lon": 126.9780, "radius": 22, "name": "Seoul"},
            {"lat": 31.2304, "lon": 121.4737, "radius": 25, "name": "Shanghai"},
        ],
        "timezones": ["Asia/Tokyo", "Asia/Seoul", "Asia/Shanghai"],
        "languages": ["ja", "ko", "zh-CN", "en"],
        "locales": ["ja_JP.UTF-8", "ko_KR.UTF-8"],
        "accept_language": "ja,en;q=0.8",
    },
    "oceania": {
        "name": "Oceania",
        "tor_exit_country": "{au},{nz}",
        "cities": [
            {"lat": -33.8688, "lon": 151.2093, "radius": 25, "name": "Sydney"},
            {"lat": -37.8136, "lon": 144.9631, "radius": 22, "name": "Melbourne"},
            {"lat": -36.8485, "lon": 174.7633, "radius": 18, "name": "Auckland"},
        ],
        "timezones": ["Australia/Sydney", "Australia/Melbourne", "Pacific/Auckland"],
        "languages": ["en-AU", "en"],
        "locales": ["en_AU.UTF-8"],
        "accept_language": "en-AU,en;q=0.9",
    },
    "south-america": {
        "name": "South America",
        "tor_exit_country": "{br},{ar},{cl}",
        "cities": [
            {"lat": -23.5505, "lon": -46.6333, "radius": 30, "name": "São Paulo"},
            {"lat": -34.6037, "lon": -58.3816, "radius": 25, "name": "Buenos Aires"},
            {"lat": -33.4489, "lon": -70.6693, "radius": 18, "name": "Santiago"},
        ],
        "timezones": ["America/Sao_Paulo", "America/Argentina/Buenos_Aires"],
        "languages": ["pt-BR", "es", "en"],
        "locales": ["pt_BR.UTF-8", "es_AR.UTF-8"],
        "accept_language": "pt-BR,pt;q=0.9,en;q=0.8",
    },
}

# Browser fingerprint components
PLATFORMS = [
    "Win32", "Linux x86_64", "MacIntel",
]

SCREEN_RESOLUTIONS = [
    (1920, 1080), (2560, 1440), (1366, 768), (1536, 864),
    (1440, 900), (1280, 720), (1600, 900), (3840, 2160),
    (2560, 1600), (1680, 1050),
]

USER_AGENTS = [
    # Chrome variants
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    # Firefox variants
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
    "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0",
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0",
]

WEBGL_RENDERERS = [
    "ANGLE (Intel, Intel(R) UHD Graphics 630, OpenGL 4.5)",
    "ANGLE (NVIDIA, NVIDIA GeForce GTX 1060, OpenGL 4.5)",
    "ANGLE (AMD, AMD Radeon RX 580, OpenGL 4.5)",
    "ANGLE (Intel, Intel(R) Iris(R) Plus Graphics, OpenGL 4.5)",
    "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060, OpenGL 4.5)",
    "Mesa Intel(R) UHD Graphics 620 (KBL GT2)",
    "Mesa AMD Radeon Graphics (renoir, LLVM 15.0.7, DRM 3.49)",
]

WEBGL_VENDORS = [
    "Google Inc. (Intel)",
    "Google Inc. (NVIDIA)",
    "Google Inc. (AMD)",
    "Intel Inc.",
    "Mesa/X.org",
]


# ═══════════════════════════════════════════════════════════════
# IDENTITY GENERATION
# ═══════════════════════════════════════════════════════════════

def random_point_near(lat, lon, radius_km):
    """Random coordinate within radius_km of center."""
    radius_deg = radius_km / 111.32
    angle = random.uniform(0, 2 * math.pi)
    r = radius_deg * math.sqrt(random.random())
    new_lat = lat + r * math.cos(angle)
    new_lon = lon + r * math.sin(angle) / max(math.cos(math.radians(lat)), 0.01)
    return round(max(-90, min(90, new_lat)), 6), round(((new_lon + 180) % 360) - 180, 6)


def random_mac():
    """Generate random MAC with locally-administered bit set."""
    mac = [random.randint(0, 255) for _ in range(6)]
    mac[0] = (mac[0] | 0x02) & 0xFE  # locally administered, unicast
    return ":".join(f"{b:02x}" for b in mac)


def random_hostname():
    """Generate a plausible hostname."""
    prefixes = ["desktop", "laptop", "pc", "workstation", "home", "user"]
    suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return f"{random.choice(prefixes)}-{suffix}"


def generate_canvas_noise_seed():
    """Generate a seed for canvas fingerprint noise."""
    return random.randint(100000, 999999)


def generate_audio_noise_seed():
    """Generate a seed for AudioContext fingerprint noise."""
    return round(random.uniform(0.0001, 0.01), 6)


def generate_identity(region_key=None):
    """Generate a complete, consistent fake identity."""
    if region_key is None or region_key == "random":
        region_key = random.choice(list(IDENTITIES.keys()))

    region = IDENTITIES[region_key]
    city = random.choice(region["cities"])
    lat, lon = random_point_near(city["lat"], city["lon"], city["radius"])
    screen = random.choice(SCREEN_RESOLUTIONS)

    # Pick a coherent platform + user agent
    ua = random.choice(USER_AGENTS)
    if "Windows" in ua:
        platform = "Win32"
    elif "Mac" in ua:
        platform = "MacIntel"
    else:
        platform = "Linux x86_64"

    identity = {
        "id": ''.join(random.choices(string.hexdigits[:16], k=16)),
        "generated_at": time.time(),
        "region_key": region_key,
        "region_name": region["name"],
        "tor_exit_country": region["tor_exit_country"],

        # Location
        "location": {
            "latitude": lat,
            "longitude": lon,
            "accuracy": round(random.uniform(20, 150), 1),
            "near_city": city["name"],
        },

        # Network
        "network": {
            "mac_address": random_mac(),
            "hostname": random_hostname(),
        },

        # Time
        "timezone": random.choice(region["timezones"]),

        # Language
        "language": region["languages"][0],
        "languages": region["languages"][:3],
        "accept_language": region["accept_language"],
        "locale": random.choice(region["locales"]),

        # Browser fingerprint
        "browser": {
            "user_agent": ua,
            "platform": platform,
            "screen_width": screen[0],
            "screen_height": screen[1],
            "color_depth": random.choice([24, 32]),
            "pixel_ratio": random.choice([1.0, 1.25, 1.5, 2.0]),
            "hardware_concurrency": random.choice([2, 4, 8, 12, 16]),
            "device_memory": random.choice([2, 4, 8, 16]),
            "max_touch_points": 0,
            "webgl_vendor": random.choice(WEBGL_VENDORS),
            "webgl_renderer": random.choice(WEBGL_RENDERERS),
            "canvas_noise_seed": generate_canvas_noise_seed(),
            "audio_noise_seed": generate_audio_noise_seed(),
        },
    }

    return identity


def save_identity(identity):
    """Save current identity to state file."""
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(identity, f, indent=2)


def load_identity():
    """Load current identity from state file."""
    if STATE_FILE.exists():
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    return None


def print_identity(identity):
    """Pretty-print an identity."""
    print(f"\n  ╔══════════════════════════════════════════════════╗")
    print(f"  ║  GHOST IDENTITY [{identity['id'][:8]}]               ║")
    print(f"  ╠══════════════════════════════════════════════════╣")
    print(f"  ║  Region    : {identity['region_name']:<35} ║")
    print(f"  ║  Near      : {identity['location']['near_city']:<35} ║")
    print(f"  ║  Lat/Lon   : {identity['location']['latitude']}, {identity['location']['longitude']}")
    print(f"  ║  Timezone  : {identity['timezone']:<35} ║")
    print(f"  ║  Language  : {identity['language']:<35} ║")
    print(f"  ║  MAC       : {identity['network']['mac_address']:<35} ║")
    print(f"  ║  Hostname  : {identity['network']['hostname']:<35} ║")
    print(f"  ║  Platform  : {identity['browser']['platform']:<35} ║")
    print(f"  ║  Screen    : {identity['browser']['screen_width']}x{identity['browser']['screen_height']}")
    print(f"  ║  UA        : {identity['browser']['user_agent'][:45]}...")
    print(f"  ║  Tor Exit  : {identity['tor_exit_country']:<35} ║")
    print(f"  ╚══════════════════════════════════════════════════╝\n")


def export_env(identity):
    """Export identity as environment variables for other modules."""
    env_lines = [
        f"export GHOST_REGION='{identity['region_key']}'",
        f"export GHOST_LAT='{identity['location']['latitude']}'",
        f"export GHOST_LON='{identity['location']['longitude']}'",
        f"export GHOST_ACCURACY='{identity['location']['accuracy']}'",
        f"export GHOST_CITY='{identity['location']['near_city']}'",
        f"export GHOST_MAC='{identity['network']['mac_address']}'",
        f"export GHOST_HOSTNAME='{identity['network']['hostname']}'",
        f"export GHOST_TZ='{identity['timezone']}'",
        f"export GHOST_LANG='{identity['language']}'",
        f"export GHOST_LOCALE='{identity['locale']}'",
        f"export GHOST_ACCEPT_LANG='{identity['accept_language']}'",
        f"export GHOST_UA='{identity['browser']['user_agent']}'",
        f"export GHOST_PLATFORM='{identity['browser']['platform']}'",
        f"export GHOST_SCREEN_W='{identity['browser']['screen_width']}'",
        f"export GHOST_SCREEN_H='{identity['browser']['screen_height']}'",
        f"export GHOST_COLOR_DEPTH='{identity['browser']['color_depth']}'",
        f"export GHOST_PIXEL_RATIO='{identity['browser']['pixel_ratio']}'",
        f"export GHOST_HW_CONCURRENCY='{identity['browser']['hardware_concurrency']}'",
        f"export GHOST_DEVICE_MEMORY='{identity['browser']['device_memory']}'",
        f"export GHOST_WEBGL_VENDOR='{identity['browser']['webgl_vendor']}'",
        f"export GHOST_WEBGL_RENDERER='{identity['browser']['webgl_renderer']}'",
        f"export GHOST_CANVAS_SEED='{identity['browser']['canvas_noise_seed']}'",
        f"export GHOST_AUDIO_SEED='{identity['browser']['audio_noise_seed']}'",
        f"export GHOST_TOR_EXIT='{identity['tor_exit_country']}'",
    ]
    return "\n".join(env_lines)


def generate_browser_spoof_js(identity):
    """Generate JavaScript injection for browser fingerprint spoofing."""
    b = identity["browser"]
    loc = identity["location"]

    js = f"""// GhostBox Identity Spoof — auto-generated
// ID: {identity['id']}
(function() {{
    'use strict';

    // ─── Navigator overrides ─────────────────────────
    const navProps = {{
        userAgent: '{b["user_agent"]}',
        platform: '{b["platform"]}',
        language: '{identity["language"]}',
        languages: {json.dumps(identity["languages"])},
        hardwareConcurrency: {b["hardware_concurrency"]},
        deviceMemory: {b["device_memory"]},
        maxTouchPoints: {b["max_touch_points"]},
    }};

    for (const [key, value] of Object.entries(navProps)) {{
        try {{
            Object.defineProperty(navigator, key, {{
                get: () => value,
                configurable: true,
            }});
        }} catch(e) {{}}
    }}

    // ─── Screen overrides ────────────────────────────
    const screenProps = {{
        width: {b["screen_width"]},
        height: {b["screen_height"]},
        availWidth: {b["screen_width"]},
        availHeight: {b["screen_height"] - 40},
        colorDepth: {b["color_depth"]},
        pixelDepth: {b["color_depth"]},
    }};

    for (const [key, value] of Object.entries(screenProps)) {{
        try {{
            Object.defineProperty(screen, key, {{
                get: () => value,
                configurable: true,
            }});
        }} catch(e) {{}}
    }}

    Object.defineProperty(window, 'devicePixelRatio', {{
        get: () => {b["pixel_ratio"]},
        configurable: true,
    }});

    // ─── Geolocation override ────────────────────────
    const spoofedCoords = {{
        latitude: {loc["latitude"]},
        longitude: {loc["longitude"]},
        accuracy: {loc["accuracy"]},
        altitude: null,
        altitudeAccuracy: null,
        heading: null,
        speed: null,
    }};

    navigator.geolocation.getCurrentPosition = function(success, error, opts) {{
        const jitter = () => (Math.random() - 0.5) * 0.002;
        setTimeout(() => success({{
            coords: {{
                ...spoofedCoords,
                latitude: spoofedCoords.latitude + jitter(),
                longitude: spoofedCoords.longitude + jitter(),
            }},
            timestamp: Date.now(),
        }}), 100 + Math.random() * 300);
    }};

    let _watchId = 1;
    const _watchers = {{}};
    navigator.geolocation.watchPosition = function(success, error, opts) {{
        const id = _watchId++;
        const jitter = () => (Math.random() - 0.5) * 0.002;
        _watchers[id] = setInterval(() => success({{
            coords: {{
                ...spoofedCoords,
                latitude: spoofedCoords.latitude + jitter(),
                longitude: spoofedCoords.longitude + jitter(),
            }},
            timestamp: Date.now(),
        }}), 5000);
        return id;
    }};
    navigator.geolocation.clearWatch = function(id) {{
        clearInterval(_watchers[id]);
        delete _watchers[id];
    }};

    // ─── WebGL fingerprint override ──────────────────
    const origGetParameter = WebGLRenderingContext.prototype.getParameter;
    WebGLRenderingContext.prototype.getParameter = function(param) {{
        if (param === 0x9245) return '{b["webgl_vendor"]}';   // UNMASKED_VENDOR
        if (param === 0x9246) return '{b["webgl_renderer"]}'; // UNMASKED_RENDERER
        return origGetParameter.call(this, param);
    }};
    if (typeof WebGL2RenderingContext !== 'undefined') {{
        const origGetParam2 = WebGL2RenderingContext.prototype.getParameter;
        WebGL2RenderingContext.prototype.getParameter = function(param) {{
            if (param === 0x9245) return '{b["webgl_vendor"]}';
            if (param === 0x9246) return '{b["webgl_renderer"]}';
            return origGetParam2.call(this, param);
        }};
    }}

    // ─── Canvas fingerprint noise ────────────────────
    const canvasSeed = {b["canvas_noise_seed"]};
    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function(type, quality) {{
        const ctx = this.getContext('2d');
        if (ctx) {{
            const imgData = ctx.getImageData(0, 0, this.width, this.height);
            for (let i = 0; i < imgData.data.length; i += 4) {{
                // Subtle noise based on seed
                imgData.data[i] ^= (canvasSeed >> (i % 8)) & 1;
            }}
            ctx.putImageData(imgData, 0, 0);
        }}
        return origToDataURL.call(this, type, quality);
    }};

    const origToBlob = HTMLCanvasElement.prototype.toBlob;
    HTMLCanvasElement.prototype.toBlob = function(callback, type, quality) {{
        const ctx = this.getContext('2d');
        if (ctx) {{
            const imgData = ctx.getImageData(0, 0, this.width, this.height);
            for (let i = 0; i < imgData.data.length; i += 4) {{
                imgData.data[i] ^= (canvasSeed >> (i % 8)) & 1;
            }}
            ctx.putImageData(imgData, 0, 0);
        }}
        return origToBlob.call(this, callback, type, quality);
    }};

    // ─── AudioContext fingerprint noise ──────────────
    const audioSeed = {b["audio_noise_seed"]};
    const origCreateOscillator = AudioContext.prototype.createOscillator;
    AudioContext.prototype.createOscillator = function() {{
        const osc = origCreateOscillator.call(this);
        const origConnect = osc.connect.bind(osc);
        osc.connect = function(dest) {{
            // Add tiny noise to audio fingerprint
            const gain = this.context.createGain();
            gain.gain.value = 1.0 + audioSeed;
            origConnect(gain);
            gain.connect(dest);
            return dest;
        }};
        return osc;
    }};

    // ─── Timezone override ───────────────────────────
    const targetTZ = '{identity["timezone"]}';
    const origDateTimeFormat = Intl.DateTimeFormat;
    Intl.DateTimeFormat = function(locale, options) {{
        options = options || {{}};
        options.timeZone = options.timeZone || targetTZ;
        return new origDateTimeFormat(locale, options);
    }};
    Intl.DateTimeFormat.prototype = origDateTimeFormat.prototype;
    Intl.DateTimeFormat.supportedLocalesOf = origDateTimeFormat.supportedLocalesOf;

    // Override Date.prototype.getTimezoneOffset
    // This is approximate but consistent with the timezone
    const tzOffsets = {{
        'America/New_York': 300,
        'America/Chicago': 360,
        'America/Los_Angeles': 480,
        'Europe/London': 0,
        'Europe/Paris': -60,
        'Europe/Berlin': -60,
        'Europe/Amsterdam': -60,
        'Europe/Stockholm': -60,
        'Europe/Oslo': -60,
        'Europe/Helsinki': -120,
        'Asia/Tokyo': -540,
        'Asia/Seoul': -540,
        'Asia/Shanghai': -480,
        'Australia/Sydney': -660,
        'Australia/Melbourne': -660,
        'Pacific/Auckland': -780,
        'America/Sao_Paulo': 180,
        'America/Argentina/Buenos_Aires': 180,
    }};
    const tzOffset = tzOffsets[targetTZ] || 0;
    Date.prototype.getTimezoneOffset = function() {{ return tzOffset; }};

    // ─── WebRTC leak prevention ──────────────────────
    // Block RTCPeerConnection entirely
    if (window.RTCPeerConnection) {{
        window.RTCPeerConnection = function() {{
            throw new DOMException('WebRTC is disabled', 'NotAllowedError');
        }};
    }}
    if (window.webkitRTCPeerConnection) {{
        window.webkitRTCPeerConnection = function() {{
            throw new DOMException('WebRTC is disabled', 'NotAllowedError');
        }};
    }}
    if (window.mozRTCPeerConnection) {{
        window.mozRTCPeerConnection = function() {{
            throw new DOMException('WebRTC is disabled', 'NotAllowedError');
        }};
    }}

    // ─── Battery API block (fingerprinting vector) ───
    if (navigator.getBattery) {{
        navigator.getBattery = function() {{
            return Promise.resolve({{
                charging: true,
                chargingTime: 0,
                dischargingTime: Infinity,
                level: 1.0,
                addEventListener: function() {{}},
                removeEventListener: function() {{}},
            }});
        }};
    }}

    // ─── Connection API spoof ────────────────────────
    if (navigator.connection) {{
        Object.defineProperty(navigator.connection, 'effectiveType', {{
            get: () => '4g', configurable: true
        }});
        Object.defineProperty(navigator.connection, 'downlink', {{
            get: () => 10, configurable: true
        }});
        Object.defineProperty(navigator.connection, 'rtt', {{
            get: () => 50, configurable: true
        }});
    }}

    // ─── Plugins/MimeTypes spoof (match Tor Browser) ─
    Object.defineProperty(navigator, 'plugins', {{
        get: () => [], configurable: true
    }});
    Object.defineProperty(navigator, 'mimeTypes', {{
        get: () => [], configurable: true
    }});

    console.log('[GhostBox] Identity spoofed: ' + targetTZ + ' / ' + '{identity["language"]}');
}})();
"""
    return js


# ═══════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════

def main():
    import argparse

    parser = argparse.ArgumentParser(description="GhostBox Identity Engine")
    parser.add_argument("command", choices=["generate", "show", "export-env", "export-js"],
                        help="Command to run")
    parser.add_argument("--region", "-r", default="random",
                        choices=list(IDENTITIES.keys()) + ["random"])

    args = parser.parse_args()

    if args.command == "generate":
        identity = generate_identity(args.region)
        save_identity(identity)
        print_identity(identity)

    elif args.command == "show":
        identity = load_identity()
        if identity:
            print_identity(identity)
        else:
            print("  No identity generated yet.")

    elif args.command == "export-env":
        identity = load_identity()
        if identity:
            print(export_env(identity))
        else:
            print("# No identity generated", file=sys.stderr)
            sys.exit(1)

    elif args.command == "export-js":
        identity = load_identity()
        if identity:
            js = generate_browser_spoof_js(identity)
            # Write to configs dir
            js_file = SCRIPT_DIR.parent / "configs" / "browser_profile" / "ghost_spoof.js"
            js_file.parent.mkdir(parents=True, exist_ok=True)
            with open(js_file, "w") as f:
                f.write(js)
            print(f"  Browser spoof JS written to: {js_file}")
        else:
            print("  No identity generated yet.")
            sys.exit(1)


if __name__ == "__main__":
    main()
