#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#
#    ██████╗ ██╗  ██╗ ██████╗ ███████╗████████╗██████╗  ██████╗ ██╗  ██╗
#   ██╔════╝ ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗╚██╗██╔╝
#   ██║  ███╗███████║██║   ██║███████╗   ██║   ██████╔╝██║   ██║ ╚███╔╝
#   ██║   ██║██╔══██║██║   ██║╚════██║   ██║   ██╔══██╗██║   ██║ ██╔██╗
#   ╚██████╔╝██║  ██║╚██████╔╝███████║   ██║   ██████╔╝╚██████╔╝██╔╝ ██╗
#    ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝
#
#   Isolated Privacy System for Linux
#   https://github.com/ghostbox/ghostbox
#
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Identity rotation settings
ROTATION_INTERVAL="${GHOSTBOX_ROTATE_INTERVAL:-30}"  # seconds
ROTATION_PID_FILE="/tmp/ghostbox_rotation.pid"

# ═══════════════════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════════════════

show_banner() {
    echo -e "${CYAN}"
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │                                                     │"
    echo "  │   ░██████╗░██╗░░██╗░█████╗░░██████╗████████╗        │"
    echo "  │   ██╔════╝░██║░░██║██╔══██╗██╔════╝╚══██╔══╝        │"
    echo "  │   ██║░░██╗░███████║██║░░██║╚█████╗░░░░██║░░░        │"
    echo "  │   ██║░░╚██╗██╔══██║██║░░██║░╚═══██╗░░░██║░░░        │"
    echo "  │   ╚██████╔╝██║░░██║╚█████╔╝██████╔╝░░░██║░░░        │"
    echo "  │   ░╚═════╝░╚═╝░░╚═╝░╚════╝░╚═════╝░░░░╚═╝░░░       │"
    echo "  │                                                     │"
    echo -e "  │   ${BOLD}B O X${NC}${CYAN}   v${VERSION}                                 │"
    echo "  │   Isolated Privacy System for Linux                 │"
    echo "  │                                                     │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

# ═══════════════════════════════════════════════════════════════
# ROOT CHECK
# ═══════════════════════════════════════════════════════════════

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}  GhostBox requires root privileges.${NC}"
        echo -e "  Run: ${BOLD}sudo $0 $*${NC}"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# UP — Start GhostBox (all layers)
# ═══════════════════════════════════════════════════════════════

cmd_up() {
    require_root
    show_banner

    local use_bridges="${1:-no}"
    local region="${2:-random}"

    echo -e "${YELLOW}  Starting GhostBox...${NC}"
    echo ""

    # Phase 1: Foundation
    echo -e "${BOLD}  ═══ Phase 1: Foundation ═══${NC}"

    echo -e "${CYAN}  [1/10]${NC} Network namespace (kernel jail)..."
    bash "$MODULES_DIR/namespace.sh" create
    echo ""

    echo -e "${CYAN}  [2/10]${NC} Firewall kill switch..."
    bash "$MODULES_DIR/firewall.sh" up
    echo ""

    echo -e "${CYAN}  [3/10]${NC} Tor routing ($([ "$use_bridges" = "yes" ] && echo "with obfs4 bridges" || echo "direct")..."
    bash "$MODULES_DIR/tor_routing.sh" start "$use_bridges"
    echo ""

    # Phase 2: Identity
    echo -e "${BOLD}  ═══ Phase 2: Identity ═══${NC}"

    echo -e "${CYAN}  [4/10]${NC} Generating ghost identity ($region)..."
    python3 "$MODULES_DIR/identity_engine.py" generate --region "$region"
    python3 "$MODULES_DIR/identity_engine.py" export-js
    echo ""

    echo -e "${CYAN}  [5/10]${NC} DNS isolation (all DNS through Tor)..."
    bash "$MODULES_DIR/dns_isolation.sh" setup
    echo ""

    echo -e "${CYAN}  [6/10]${NC} MAC randomization..."
    bash "$MODULES_DIR/mac_randomizer.sh" start
    echo ""

    # Phase 3: Hardening
    echo -e "${BOLD}  ═══ Phase 3: Hardening ═══${NC}"

    echo -e "${CYAN}  [7/10]${NC} System hardening..."
    bash "$MODULES_DIR/system_hardening.sh" apply
    echo ""

    echo -e "${CYAN}  [8/10]${NC} RAM workspace..."
    bash "$MODULES_DIR/ram_workspace.sh" create
    echo ""

    echo -e "${CYAN}  [9/10]${NC} Traffic padding..."
    bash "$MODULES_DIR/traffic_padding.sh" start
    echo ""

    # Phase 4: Identity rotation
    echo -e "${CYAN}  [10/10]${NC} Starting identity rotation (every ${ROTATION_INTERVAL}s)..."
    cmd_start_rotation "$region" &
    echo ""

    # Done
    echo -e "${GREEN}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║                                                   ║"
    echo "  ║        GHOSTBOX IS ACTIVE                         ║"
    echo "  ║                                                   ║"
    echo "  ║   All traffic goes through Tor                    ║"
    echo "  ║   Kill switch is armed                            ║"
    echo "  ║   Identity rotates every ${ROTATION_INTERVAL}s                    ║"
    echo "  ║   DNS is isolated                                 ║"
    echo "  ║   MAC is randomizing                              ║"
    echo "  ║   System is hardened                               ║"
    echo "  ║   Everything runs in RAM                          ║"
    echo "  ║                                                   ║"
    echo "  ║   Launch browser:                                 ║"
    echo "  ║     sudo ghostbox browser chrome                  ║"
    echo "  ║     sudo ghostbox browser firefox                 ║"
    echo "  ║                                                   ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ═══════════════════════════════════════════════════════════════
# DOWN — Stop GhostBox (reverse order, secure wipe)
# ═══════════════════════════════════════════════════════════════

cmd_down() {
    require_root
    show_banner

    echo -e "${YELLOW}  Shutting down GhostBox...${NC}"
    echo ""

    # Stop rotation
    echo -e "${CYAN}  [1/8]${NC} Stopping identity rotation..."
    cmd_stop_rotation
    echo ""

    # Stop traffic padding
    echo -e "${CYAN}  [2/8]${NC} Stopping traffic padding..."
    bash "$MODULES_DIR/traffic_padding.sh" stop 2>/dev/null || true
    echo ""

    # Kill browsers
    echo -e "${CYAN}  [3/8]${NC} Closing browsers..."
    bash "$MODULES_DIR/browser_sandbox.sh" cleanup 2>/dev/null || true
    echo ""

    # Stop MAC rotation
    echo -e "${CYAN}  [4/8]${NC} Stopping MAC randomization..."
    bash "$MODULES_DIR/mac_randomizer.sh" stop 2>/dev/null || true
    echo ""

    # Stop DNS
    echo -e "${CYAN}  [5/8]${NC} Tearing down DNS isolation..."
    bash "$MODULES_DIR/dns_isolation.sh" teardown 2>/dev/null || true
    echo ""

    # Stop Tor
    echo -e "${CYAN}  [6/8]${NC} Stopping Tor..."
    bash "$MODULES_DIR/tor_routing.sh" stop 2>/dev/null || true
    echo ""

    # Remove firewall
    echo -e "${CYAN}  [7/8]${NC} Removing kill switch..."
    bash "$MODULES_DIR/firewall.sh" down 2>/dev/null || true
    echo ""

    # Destroy namespace
    echo -e "${CYAN}  [8/8]${NC} Destroying namespace..."
    bash "$MODULES_DIR/namespace.sh" destroy 2>/dev/null || true
    echo ""

    # Remove hardening
    echo -e "${CYAN}  [+]${NC} Removing system hardening..."
    bash "$MODULES_DIR/system_hardening.sh" remove 2>/dev/null || true
    echo ""

    # SECURE WIPE
    echo -e "${RED}  [+] SECURE WIPE — destroying all traces...${NC}"
    bash "$MODULES_DIR/ram_workspace.sh" wipe 2>/dev/null || true
    echo ""

    echo -e "${GREEN}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║                                                   ║"
    echo "  ║   GHOSTBOX SHUTDOWN COMPLETE                      ║"
    echo "  ║   All data securely wiped                         ║"
    echo "  ║   All traces destroyed                            ║"
    echo "  ║                                                   ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ═══════════════════════════════════════════════════════════════
# EMERGENCY — Instant panic wipe
# ═══════════════════════════════════════════════════════════════

cmd_emergency() {
    require_root
    echo -e "${RED}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   !!! EMERGENCY WIPE !!!                          ║"
    echo "  ║   Destroying everything immediately               ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Everything in parallel for speed
    bash "$MODULES_DIR/ram_workspace.sh" emergency &
    bash "$MODULES_DIR/traffic_padding.sh" stop 2>/dev/null &
    bash "$MODULES_DIR/mac_randomizer.sh" stop 2>/dev/null &
    cmd_stop_rotation 2>/dev/null &
    wait

    bash "$MODULES_DIR/dns_isolation.sh" teardown 2>/dev/null || true
    bash "$MODULES_DIR/tor_routing.sh" stop 2>/dev/null || true
    bash "$MODULES_DIR/firewall.sh" down 2>/dev/null || true
    bash "$MODULES_DIR/namespace.sh" destroy 2>/dev/null || true
    bash "$MODULES_DIR/system_hardening.sh" remove 2>/dev/null || true

    echo -e "${GREEN}  EMERGENCY WIPE COMPLETE${NC}"
}

# ═══════════════════════════════════════════════════════════════
# BROWSER — Launch isolated browser
# ═══════════════════════════════════════════════════════════════

cmd_browser() {
    require_root
    local browser_type="${1:-chrome}"

    # Check if GhostBox is running
    if ! ip netns list 2>/dev/null | grep -qw ghostbox; then
        echo -e "${RED}  GhostBox is not running. Start it first:${NC}"
        echo "  sudo $0 up"
        exit 1
    fi

    # Load identity environment
    local identity_env
    identity_env=$(python3 "$MODULES_DIR/identity_engine.py" export-env 2>/dev/null) || true
    if [[ -n "$identity_env" ]]; then
        eval "$identity_env"
    fi

    echo -e "${CYAN}  Launching $browser_type inside GhostBox...${NC}"
    bash "$MODULES_DIR/browser_sandbox.sh" "$browser_type"
}

# ═══════════════════════════════════════════════════════════════
# ROTATE — Manually trigger identity rotation
# ═══════════════════════════════════════════════════════════════

cmd_rotate() {
    require_root
    local region="${1:-random}"

    echo -e "${YELLOW}  Rotating identity...${NC}"

    # Generate new identity
    python3 "$MODULES_DIR/identity_engine.py" generate --region "$region"
    python3 "$MODULES_DIR/identity_engine.py" export-js 2>/dev/null || true

    # Rotate MAC
    bash "$MODULES_DIR/mac_randomizer.sh" rotate 2>/dev/null || true

    # New Tor circuit
    bash "$MODULES_DIR/tor_routing.sh" new-circuit 2>/dev/null || true

    echo -e "${GREEN}  Identity rotated!${NC}"
}

# ─── Identity rotation daemon ───────────────────────────────

cmd_start_rotation() {
    local region="${1:-random}"

    # Kill existing
    cmd_stop_rotation 2>/dev/null || true

    (
        while true; do
            sleep "$ROTATION_INTERVAL"

            # Generate new identity
            python3 "$MODULES_DIR/identity_engine.py" generate --region "$region" >/dev/null 2>&1 || true
            python3 "$MODULES_DIR/identity_engine.py" export-js >/dev/null 2>&1 || true

            # New Tor circuit
            bash "$MODULES_DIR/tor_routing.sh" new-circuit >/dev/null 2>&1 || true

            # Rotate MAC (handled by mac_randomizer daemon, but force sync)
            bash "$MODULES_DIR/mac_randomizer.sh" rotate >/dev/null 2>&1 || true
        done
    ) &
    echo $! > "$ROTATION_PID_FILE"
    echo "[rotation] Daemon started (PID: $!, every ${ROTATION_INTERVAL}s)"
}

cmd_stop_rotation() {
    if [[ -f "$ROTATION_PID_FILE" ]]; then
        local pid
        pid=$(cat "$ROTATION_PID_FILE")
        kill "$pid" 2>/dev/null || true
        pkill -P "$pid" 2>/dev/null || true
        rm -f "$ROTATION_PID_FILE"
        echo "[rotation] Daemon stopped"
    fi
}

# ═══════════════════════════════════════════════════════════════
# STATUS — Full system status
# ═══════════════════════════════════════════════════════════════

cmd_status() {
    show_banner

    local all_good=true

    # Namespace
    if ip netns list 2>/dev/null | grep -qw ghostbox; then
        echo -e "  ${GREEN}●${NC} Network Namespace    ${GREEN}ACTIVE${NC}"
    else
        echo -e "  ${RED}○${NC} Network Namespace    ${RED}INACTIVE${NC}"
        all_good=false
    fi

    # Firewall
    if nft list table inet ghostbox >/dev/null 2>&1; then
        echo -e "  ${GREEN}●${NC} Kill Switch          ${GREEN}ARMED${NC}"
    else
        echo -e "  ${RED}○${NC} Kill Switch          ${RED}DISARMED${NC}"
        all_good=false
    fi

    # Tor
    if pgrep -f "tor -f.*ghostbox" >/dev/null 2>&1; then
        local pct
        pct=$(grep -oP 'Bootstrapped \K[0-9]+' /var/log/tor/ghostbox.log 2>/dev/null | tail -1) || pct="?"
        echo -e "  ${GREEN}●${NC} Tor Routing          ${GREEN}RUNNING${NC} (${pct}% bootstrapped)"
    else
        echo -e "  ${RED}○${NC} Tor Routing          ${RED}STOPPED${NC}"
        all_good=false
    fi

    # DNS
    if [[ -f /etc/netns/ghostbox/resolv.conf ]]; then
        echo -e "  ${GREEN}●${NC} DNS Isolation        ${GREEN}ACTIVE${NC}"
    else
        echo -e "  ${RED}○${NC} DNS Isolation        ${RED}INACTIVE${NC}"
        all_good=false
    fi

    # MAC randomizer
    if [[ -f /tmp/ghostbox_mac.pid ]] && kill -0 "$(cat /tmp/ghostbox_mac.pid)" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} MAC Randomizer       ${GREEN}RUNNING${NC}"
    else
        echo -e "  ${RED}○${NC} MAC Randomizer       ${RED}STOPPED${NC}"
        all_good=false
    fi

    # Traffic padding
    if [[ -f /tmp/ghostbox_padding.pid ]] && kill -0 "$(cat /tmp/ghostbox_padding.pid)" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} Traffic Padding      ${GREEN}RUNNING${NC}"
    else
        echo -e "  ${DIM}○${NC} Traffic Padding      ${DIM}STOPPED${NC}"
    fi

    # Identity rotation
    if [[ -f "$ROTATION_PID_FILE" ]] && kill -0 "$(cat "$ROTATION_PID_FILE")" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} Identity Rotation    ${GREEN}ACTIVE${NC} (every ${ROTATION_INTERVAL}s)"
    else
        echo -e "  ${RED}○${NC} Identity Rotation    ${RED}STOPPED${NC}"
    fi

    # System hardening
    local ipv6
    ipv6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) || ipv6="0"
    if [[ "$ipv6" == "1" ]]; then
        echo -e "  ${GREEN}●${NC} System Hardening     ${GREEN}APPLIED${NC}"
    else
        echo -e "  ${RED}○${NC} System Hardening     ${RED}NOT APPLIED${NC}"
    fi

    # RAM workspace
    if [[ -d /dev/shm/ghostbox_workspace ]]; then
        echo -e "  ${GREEN}●${NC} RAM Workspace        ${GREEN}ACTIVE${NC}"
    else
        echo -e "  ${DIM}○${NC} RAM Workspace        ${DIM}NOT CREATED${NC}"
    fi

    echo ""

    # Current identity
    if [[ -f "$CONFIGS_DIR/.identity_state.json" ]]; then
        echo -e "  ${BOLD}Current Identity:${NC}"
        python3 "$MODULES_DIR/identity_engine.py" show 2>/dev/null | grep -E "Region|Near|Lat|MAC|Hostname|Timezone|Platform" | head -8
    fi

    echo ""

    if $all_good; then
        echo -e "  ${GREEN}${BOLD}GHOSTBOX IS FULLY OPERATIONAL${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}GHOSTBOX IS PARTIALLY ACTIVE${NC}"
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# VERIFY — Run all security checks
# ═══════════════════════════════════════════════════════════════

cmd_verify() {
    require_root
    show_banner

    echo -e "${BOLD}  Running security verification...${NC}"
    echo ""

    local total_failures=0

    echo -e "${BOLD}  ─── Namespace Isolation ───${NC}"
    bash "$MODULES_DIR/namespace.sh" verify 2>/dev/null || ((total_failures++))
    echo ""

    echo -e "${BOLD}  ─── Firewall Kill Switch ───${NC}"
    bash "$MODULES_DIR/firewall.sh" verify 2>/dev/null || ((total_failures++))
    echo ""

    echo -e "${BOLD}  ─── Tor Routing ───${NC}"
    bash "$MODULES_DIR/tor_routing.sh" verify 2>/dev/null || ((total_failures++))
    echo ""

    echo -e "${BOLD}  ─── DNS Isolation ───${NC}"
    bash "$MODULES_DIR/dns_isolation.sh" verify 2>/dev/null || ((total_failures++))
    echo ""

    echo -e "${BOLD}  ─── System Hardening ───${NC}"
    bash "$MODULES_DIR/system_hardening.sh" verify 2>/dev/null || ((total_failures++))
    echo ""

    echo -e "${BOLD}  ─── RAM Workspace ───${NC}"
    bash "$MODULES_DIR/ram_workspace.sh" mem-check 2>/dev/null || true
    echo ""

    if [[ $total_failures -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}"
        echo "  ╔═══════════════════════════════════════════════════╗"
        echo "  ║   ALL SECURITY CHECKS PASSED                     ║"
        echo "  ║   GhostBox is fully operational                   ║"
        echo "  ╚═══════════════════════════════════════════════════╝"
        echo -e "${NC}"
    else
        echo -e "${RED}${BOLD}"
        echo "  ╔═══════════════════════════════════════════════════╗"
        echo "  ║   WARNING: $total_failures module(s) have issues              ║"
        echo "  ║   Check output above for details                  ║"
        echo "  ╚═══════════════════════════════════════════════════╝"
        echo -e "${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════════
# EXEC — Run any command inside the namespace
# ═══════════════════════════════════════════════════════════════

cmd_exec() {
    require_root
    if ! ip netns list 2>/dev/null | grep -qw ghostbox; then
        echo -e "${RED}  GhostBox is not running.${NC}"
        exit 1
    fi

    # Load identity env
    local identity_env
    identity_env=$(python3 "$MODULES_DIR/identity_engine.py" export-env 2>/dev/null) || true
    if [[ -n "$identity_env" ]]; then
        eval "$identity_env"
    fi

    ip netns exec ghostbox env \
        TZ="${GHOST_TZ:-UTC}" \
        LANG="${GHOST_LOCALE:-en_US.UTF-8}" \
        HOME="/dev/shm/ghostbox_home" \
        "$@"
}

# ═══════════════════════════════════════════════════════════════
# HELP
# ═══════════════════════════════════════════════════════════════

cmd_help() {
    show_banner

    echo -e "${BOLD}  Usage:${NC} sudo ghostbox <command> [options]"
    echo ""
    echo -e "${BOLD}  Core Commands:${NC}"
    echo -e "    ${GREEN}up${NC} [bridges] [region]    Start GhostBox (all layers)"
    echo -e "    ${GREEN}down${NC}                     Shutdown + secure wipe"
    echo -e "    ${RED}emergency${NC}                INSTANT panic wipe"
    echo -e "    ${CYAN}status${NC}                   Show system status"
    echo -e "    ${CYAN}verify${NC}                   Run security checks"
    echo ""
    echo -e "${BOLD}  Browser:${NC}"
    echo -e "    ${GREEN}browser chrome${NC}           Launch Chrome in sandbox"
    echo -e "    ${GREEN}browser firefox${NC}          Launch Firefox in sandbox"
    echo ""
    echo -e "${BOLD}  Identity:${NC}"
    echo -e "    ${GREEN}rotate${NC} [region]          Force identity rotation"
    echo -e "    ${CYAN}identity${NC}                 Show current identity"
    echo ""
    echo -e "${BOLD}  Advanced:${NC}"
    echo -e "    ${GREEN}exec${NC} <command>           Run command inside namespace"
    echo -e "    ${GREEN}shell${NC}                    Open shell inside namespace"
    echo ""
    echo -e "${BOLD}  Options:${NC}"
    echo -e "    up ${DIM}bridges${NC}             Use obfs4 bridges (hide Tor from ISP)"
    echo -e "    up ${DIM}[region]${NC}             us-east, us-west, europe-west, europe-north,"
    echo -e "                             asia-east, oceania, south-america, random"
    echo ""
    echo -e "${BOLD}  Examples:${NC}"
    echo -e "    sudo ghostbox up                     # Start with random identity"
    echo -e "    sudo ghostbox up bridges europe-west # Start with bridge + EU identity"
    echo -e "    sudo ghostbox browser chrome         # Launch Chrome in sandbox"
    echo -e "    sudo ghostbox rotate asia-east       # Switch to East Asia identity"
    echo -e "    sudo ghostbox status                 # Check everything"
    echo -e "    sudo ghostbox down                   # Shutdown + wipe"
    echo -e "    sudo ghostbox emergency              # PANIC — destroy everything NOW"
    echo ""
    echo -e "${BOLD}  Environment Variables:${NC}"
    echo -e "    GHOSTBOX_ROTATE_INTERVAL=30   Identity rotation interval (seconds)"
    echo -e "    GHOSTBOX_MAC_INTERVAL=3       MAC rotation interval (seconds)"
    echo -e "    GHOSTBOX_PADDING_RATE=50000   Traffic padding rate (bytes/sec)"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# MAIN DISPATCHER
# ═══════════════════════════════════════════════════════════════

main() {
    case "${1:-help}" in
        up)
            local bridges="no"
            local region="random"
            shift
            for arg in "$@"; do
                case "$arg" in
                    bridges|bridge|obfs4) bridges="yes" ;;
                    *) region="$arg" ;;
                esac
            done
            cmd_up "$bridges" "$region"
            ;;
        down|stop)
            cmd_down
            ;;
        emergency|panic|wipe)
            cmd_emergency
            ;;
        browser)
            cmd_browser "${2:-chrome}"
            ;;
        rotate)
            cmd_rotate "${2:-random}"
            ;;
        identity)
            python3 "$MODULES_DIR/identity_engine.py" show
            ;;
        status)
            cmd_status
            ;;
        verify|check)
            cmd_verify
            ;;
        exec)
            shift
            cmd_exec "$@"
            ;;
        shell)
            cmd_exec /bin/bash
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            echo -e "${RED}  Unknown command: $1${NC}"
            echo "  Run: $0 help"
            exit 1
            ;;
    esac
}

main "$@"
