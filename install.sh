#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#   GhostBox Installer
#   Installs all dependencies and sets up the system
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYAN}${BOLD}"
echo "  GhostBox Installer"
echo "  ═══════════════════"
echo -e "${NC}"

# Root check
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}  Run as root: sudo $0${NC}"
    exit 1
fi

# Detect package manager
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
    PKG_INSTALL="apt-get install -y"
    PKG_UPDATE="apt-get update -qq"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
    PKG_INSTALL="dnf install -y"
    PKG_UPDATE="dnf check-update || true"
elif command -v pacman &>/dev/null; then
    PKG_MGR="pacman"
    PKG_INSTALL="pacman -S --noconfirm"
    PKG_UPDATE="pacman -Sy"
elif command -v zypper &>/dev/null; then
    PKG_MGR="zypper"
    PKG_INSTALL="zypper install -y"
    PKG_UPDATE="zypper refresh"
else
    echo -e "${RED}  Unsupported package manager. Install dependencies manually.${NC}"
    exit 1
fi

echo -e "${CYAN}  Detected package manager: ${BOLD}$PKG_MGR${NC}"
echo ""

# ─── Update repos ───
echo -e "${YELLOW}  [1/6] Updating package lists...${NC}"
$PKG_UPDATE 2>/dev/null

# ─── Core dependencies ───
echo -e "${YELLOW}  [2/6] Installing core dependencies...${NC}"

CORE_PACKAGES=""
case "$PKG_MGR" in
    apt)
        CORE_PACKAGES="tor obfs4proxy nftables iptables iproute2 socat python3 python3-pip curl wget"
        ;;
    dnf)
        CORE_PACKAGES="tor obfs4 nftables iptables iproute socat python3 python3-pip curl wget"
        ;;
    pacman)
        CORE_PACKAGES="tor obfs4proxy nftables iptables iproute2 socat python curl wget"
        ;;
    zypper)
        CORE_PACKAGES="tor nftables iptables iproute2 socat python3 python3-pip curl wget"
        ;;
esac

for pkg in $CORE_PACKAGES; do
    echo -ne "  Installing ${pkg}... "
    $PKG_INSTALL "$pkg" >/dev/null 2>&1 && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}SKIP${NC}"
done

# ─── Privacy tools ───
echo ""
echo -e "${YELLOW}  [3/6] Installing privacy tools...${NC}"

PRIVACY_PACKAGES=""
case "$PKG_MGR" in
    apt)
        PRIVACY_PACKAGES="macchanger libimage-exiftool-perl inotify-tools bleachbit secure-delete mat2"
        ;;
    dnf)
        PRIVACY_PACKAGES="macchanger perl-Image-ExifTool inotify-tools bleachbit"
        ;;
    pacman)
        PRIVACY_PACKAGES="macchanger perl-image-exiftool inotify-tools bleachbit"
        ;;
    zypper)
        PRIVACY_PACKAGES="macchanger exiftool inotify-tools bleachbit"
        ;;
esac

for pkg in $PRIVACY_PACKAGES; do
    echo -ne "  Installing ${pkg}... "
    $PKG_INSTALL "$pkg" >/dev/null 2>&1 && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}SKIP${NC}"
done

# ─── Sandbox tools ───
echo ""
echo -e "${YELLOW}  [4/6] Installing sandbox tools...${NC}"

SANDBOX_PACKAGES=""
case "$PKG_MGR" in
    apt)
        SANDBOX_PACKAGES="firejail bubblewrap xdg-utils"
        ;;
    dnf)
        SANDBOX_PACKAGES="firejail bubblewrap xdg-utils"
        ;;
    pacman)
        SANDBOX_PACKAGES="firejail bubblewrap xdg-utils"
        ;;
    zypper)
        SANDBOX_PACKAGES="firejail bubblewrap xdg-utils"
        ;;
esac

for pkg in $SANDBOX_PACKAGES; do
    echo -ne "  Installing ${pkg}... "
    $PKG_INSTALL "$pkg" >/dev/null 2>&1 && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}SKIP${NC}"
done

# ─── Python dependencies ───
echo ""
echo -e "${YELLOW}  [5/6] Installing Python dependencies...${NC}"

pip3 install --quiet --break-system-packages 2>/dev/null || true
# No external Python packages needed — identity_engine uses stdlib only

echo -e "${GREEN}  Python dependencies OK (stdlib only)${NC}"

# ─── Setup ───
echo ""
echo -e "${YELLOW}  [6/6] Setting up GhostBox...${NC}"

# Make all scripts executable
chmod +x "$SCRIPT_DIR/ghostbox.sh"
chmod +x "$SCRIPT_DIR/modules/"*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/tests/"*.sh 2>/dev/null || true

# Create symlink for easy access
ln -sf "$SCRIPT_DIR/ghostbox.sh" /usr/local/bin/ghostbox
echo -e "  ${GREEN}Symlinked: /usr/local/bin/ghostbox${NC}"

# Create configs directory
mkdir -p "$SCRIPT_DIR/configs/browser_profile"

# Create Tor data directory
mkdir -p /var/lib/tor/ghostbox
chown debian-tor:debian-tor /var/lib/tor/ghostbox 2>/dev/null || true
chmod 700 /var/lib/tor/ghostbox

# Create log directory
mkdir -p /var/log/tor
touch /var/log/tor/ghostbox.log
chown debian-tor:debian-tor /var/log/tor/ghostbox.log 2>/dev/null || true

# Create namespace resolv.conf directory
mkdir -p /etc/netns/ghostbox

# Disable Tor system service (we run our own instance)
systemctl disable tor 2>/dev/null || true
systemctl stop tor 2>/dev/null || true

echo ""

# ─── Verification ───
echo -e "${BOLD}  Checking installed tools:${NC}"
echo ""

check_tool() {
    local name="$1"
    local cmd="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name ${RED}(not found)${NC}"
        return 1
    fi
}

FAILS=0
check_tool "tor" "tor" || ((FAILS++))
check_tool "obfs4proxy" "obfs4proxy" || ((FAILS++))
check_tool "nftables (nft)" "nft" || ((FAILS++))
check_tool "iptables" "iptables" || ((FAILS++))
check_tool "ip (iproute2)" "ip" || ((FAILS++))
check_tool "socat" "socat" || ((FAILS++))
check_tool "python3" "python3" || ((FAILS++))
check_tool "curl" "curl" || ((FAILS++))
check_tool "macchanger" "macchanger" || true  # optional
check_tool "exiftool" "exiftool" || true       # optional
check_tool "inotifywait" "inotifywait" || true # optional
check_tool "firejail" "firejail" || true       # optional
check_tool "mat2" "mat2" || true               # optional

echo ""

if [[ $FAILS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║                                                   ║"
    echo "  ║   GHOSTBOX INSTALLED SUCCESSFULLY                 ║"
    echo "  ║                                                   ║"
    echo "  ║   Start:   sudo ghostbox up                       ║"
    echo "  ║   Help:    ghostbox help                          ║"
    echo "  ║                                                   ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
else
    echo -e "${YELLOW}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║                                                   ║"
    echo "  ║   GHOSTBOX INSTALLED WITH WARNINGS                ║"
    echo "  ║   Some core tools are missing ($FAILS)               ║"
    echo "  ║   Install them manually before running            ║"
    echo "  ║                                                   ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
fi
