# GhostBox

**Isolated Privacy System for Linux**

GhostBox creates a multi-layered isolation environment that routes all traffic through Tor, randomizes your identity every 30 seconds, and leaves zero forensic traces. Everything runs in RAM.

```
  ┌─────────────────────────────────────────────────────┐
  │                                                     │
  │   ░██████╗░██╗░░██╗░█████╗░░██████╗████████╗        │
  │   ██╔════╝░██║░░██║██╔══██╗██╔════╝╚══██╔══╝        │
  │   ██║░░██╗░███████║██║░░██║╚█████╗░░░░██║░░░        │
  │   ██║░░╚██╗██╔══██║██║░░██║░╚═══██╗░░░██║░░░        │
  │   ╚██████╔╝██║░░██║╚█████╔╝██████╔╝░░░██║░░░        │
  │   ░╚═════╝░╚═╝░░╚═╝░╚════╝░╚═════╝░░░░╚═╝░░░       │
  │                                                     │
  │   B O X   v1.0.0                                    │
  └─────────────────────────────────────────────────────┘
```

## What It Does

| Layer | Component | What It Protects Against |
|-------|-----------|------------------------|
| 1 | **Network Namespace** | Process-level network isolation (same tech as containers) |
| 2 | **nftables Kill Switch** | If Tor drops, zero bytes leak — guaranteed |
| 3 | **Tor + obfs4 Bridges** | ISP sees encrypted blob, not Tor usage |
| 4 | **Traffic Padding** | Defeats traffic analysis & timing correlation |
| 5 | **Identity Engine** | Coordinated fake identity (MAC+location+timezone+fingerprint) |
| 6 | **DNS Isolation** | All DNS goes through Tor — never touches ISP |
| 7 | **MAC Randomizer** | Hardware address rotates continuously |
| 8 | **Browser Sandbox** | Chrome/Firefox run hardened inside namespace |
| 9 | **System Hardening** | Kernel lockdown, camera/mic/bluetooth blocked |
| 10 | **RAM Workspace** | Nothing on disk, secure wipe, anti-forensics |

## What Each Observer Sees

| Observer | What They See |
|----------|--------------|
| **ISP** | Encrypted blob to a bridge relay (or Tor entry node). Zero DNS queries. Constant-rate traffic. |
| **Website** | Tor exit IP from random country. Fake fingerprint. Fake timezone. Fake geolocation. |
| **Local forensics** | Nothing. RAM workspace is wiped. No logs. No cache. No history. |
| **Network admin** | Random MAC address changing every few seconds. Random hostname. |
| **Kernel** | Hardened sysctls. No ptrace. No core dumps. No swap. |

## Quick Start

```bash
# 1. Install dependencies
sudo bash install.sh

# 2. Start GhostBox
sudo ghostbox up

# 3. Launch a browser
sudo ghostbox browser chrome    # or firefox

# 4. When done — secure wipe & shutdown
sudo ghostbox down
```

## Commands

```bash
sudo ghostbox up                        # Start (random identity)
sudo ghostbox up bridges                # Start with obfs4 bridges (hide Tor from ISP)
sudo ghostbox up bridges europe-west    # Start with bridges + European identity
sudo ghostbox down                      # Graceful shutdown + secure wipe
sudo ghostbox emergency                 # PANIC — instant wipe everything

sudo ghostbox browser chrome            # Launch Chrome in sandbox
sudo ghostbox browser firefox           # Launch Firefox in sandbox
sudo ghostbox rotate                    # Force identity rotation
sudo ghostbox rotate asia-east          # Rotate to specific region
sudo ghostbox identity                  # Show current identity

sudo ghostbox status                    # System status dashboard
sudo ghostbox verify                    # Run security checks
sudo ghostbox exec <command>            # Run any command inside namespace
sudo ghostbox shell                     # Open shell inside namespace

sudo ghostbox help                      # Full help
```

## Available Regions

| Region | Example Cities |
|--------|---------------|
| `us-east` | New York, Washington DC, Miami |
| `us-west` | Los Angeles, San Francisco, Seattle |
| `europe-west` | London, Paris, Amsterdam |
| `europe-north` | Stockholm, Helsinki, Oslo |
| `asia-east` | Tokyo, Seoul, Taipei |
| `asia-south` | Mumbai, Bangalore, Delhi |
| `oceania` | Sydney, Melbourne, Auckland |
| `south-america` | São Paulo, Buenos Aires, Bogotá |
| `middle-east` | Dubai, Istanbul, Tel Aviv |
| `africa` | Lagos, Nairobi, Cape Town |
| `random` | Any of the above (default) |

## Environment Variables

```bash
GHOSTBOX_ROTATE_INTERVAL=30     # Identity rotation interval (seconds)
GHOSTBOX_MAC_INTERVAL=3         # MAC rotation interval (seconds)
GHOSTBOX_PADDING_RATE=50000     # Traffic padding rate (bytes/sec)
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  RAM Workspace (tmpfs — nothing on disk)                │
│ ┌─────────────────────────────────────────────────────┐ │
│ │  System Hardening (kernel sysctl, cam/mic blocked)  │ │
│ │ ┌─────────────────────────────────────────────────┐ │ │
│ │ │  Browser Sandbox (hardened Chrome/Firefox)       │ │ │
│ │ │ ┌─────────────────────────────────────────────┐ │ │ │
│ │ │ │  Identity Engine (MAC+geo+tz+fingerprint)   │ │ │ │
│ │ │ │ ┌─────────────────────────────────────────┐ │ │ │ │
│ │ │ │ │  DNS Isolation (all DNS through Tor)     │ │ │ │ │
│ │ │ │ │ ┌─────────────────────────────────────┐ │ │ │ │ │
│ │ │ │ │ │  Traffic Padding (constant noise)    │ │ │ │ │ │
│ │ │ │ │ │ ┌─────────────────────────────────┐ │ │ │ │ │ │
│ │ │ │ │ │ │  Tor + obfs4 (encrypted routing) │ │ │ │ │ │ │
│ │ │ │ │ │ │ ┌───────────────────────────────┐│ │ │ │ │ │ │
│ │ │ │ │ │ │ │ nftables Kill Switch (0 leak) ││ │ │ │ │ │ │
│ │ │ │ │ │ │ │ ┌───────────────────────────┐ ││ │ │ │ │ │ │
│ │ │ │ │ │ │ │ │ Network Namespace (jail)  │ ││ │ │ │ │ │ │
│ │ │ │ │ │ │ │ └───────────────────────────┘ ││ │ │ │ │ │ │
│ │ │ │ │ │ │ └───────────────────────────────┘│ │ │ │ │ │ │
│ │ │ │ │ │ └─────────────────────────────────┘ │ │ │ │ │ │
│ │ │ │ │ └─────────────────────────────────────┘ │ │ │ │ │
│ │ │ │ └─────────────────────────────────────────┘ │ │ │ │
│ │ │ └─────────────────────────────────────────────┘ │ │ │
│ │ └─────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Security Level

GhostBox achieves approximately **95% isolation** on a standard Linux system:

| Threat | Protected? |
|--------|-----------|
| ISP monitoring your traffic | ✅ Tor + bridges + traffic padding |
| Website fingerprinting | ✅ Spoofed fingerprint, rotated identity |
| DNS leaks | ✅ All DNS through Tor |
| IP leaks | ✅ Kill switch + namespace isolation |
| WebRTC leaks | ✅ Blocked at firewall + browser level |
| MAC tracking | ✅ Randomized continuously |
| Local forensics | ✅ RAM workspace + secure wipe |
| Camera/mic spying | ✅ Kernel modules unloaded |
| USB attacks | ✅ USB storage blocked |
| Timing correlation | ✅ Traffic padding + circuit rotation |
| Swap forensics | ✅ Swap disabled |

**What it does NOT protect against:**
- Hardware implants / supply chain attacks
- Compromised Linux kernel (0-day kernel exploits)
- Electromagnetic emanation attacks (TEMPEST)
- Cold boot attacks on systems without memory encryption
- Physical surveillance (shoulder surfing)
- A global passive adversary with unlimited resources

For higher security, combine with: QubesOS (VM isolation), full disk encryption, and a physically secured machine.

## File Structure

```
ghostbox/
├── ghostbox.sh              # Main controller — start here
├── install.sh               # One-command installer
├── README.md
├── LICENSE
├── modules/
│   ├── namespace.sh          # Network namespace jail
│   ├── firewall.sh           # nftables kill switch
│   ├── tor_routing.sh        # Tor + obfs4 bridges
│   ├── traffic_padding.sh    # Constant-rate noise
│   ├── identity_engine.py    # Coordinated fake identity
│   ├── dns_isolation.sh      # DNS-over-Tor
│   ├── mac_randomizer.sh     # MAC rotation
│   ├── browser_sandbox.sh    # Hardened browser launcher
│   ├── system_hardening.sh   # Kernel/hardware lockdown
│   └── ram_workspace.sh      # RAM workspace + anti-forensics
├── configs/
│   └── browser_profile/      # Generated browser configs
└── tests/
    ├── leak_test.sh          # IP/DNS/WebRTC leak verification
    └── identity_test.sh      # Identity rotation verification
```

## Requirements

- Linux (Ubuntu 22.04+, Debian 12+, Fedora 38+, Arch)
- Root access
- Tor
- nftables
- Python 3.8+
- Chrome or Firefox

## License

GPLv3 — see LICENSE file.

## Disclaimer

This software is provided for **legitimate privacy protection**. The authors are not responsible for misuse. Check local laws regarding privacy tools in your jurisdiction.
