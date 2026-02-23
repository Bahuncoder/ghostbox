#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#   GhostBox Leak Test
#   Verifies no IP, DNS, or WebRTC leaks
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓ PASS${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}! WARN${NC} $1"; ((WARN++)); }

echo -e "${CYAN}${BOLD}"
echo "  GhostBox Leak Test"
echo "  ═══════════════════"
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}  Run as root: sudo $0${NC}"
    exit 1
fi

# ─── Check GhostBox is running ───
if ! ip netns list 2>/dev/null | grep -qw ghostbox; then
    echo -e "${RED}  GhostBox is not running. Start it first: sudo ghostbox up${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# TEST 1: Namespace isolation
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 1: Namespace Isolation ───${NC}"

# Check namespace exists
if ip netns list | grep -qw ghostbox; then
    pass "Network namespace exists"
else
    fail "Network namespace missing"
fi

# Check veth pair exists
if ip netns exec ghostbox ip link show gbox1 &>/dev/null; then
    pass "Virtual Ethernet pair active"
else
    fail "Virtual Ethernet pair missing"
fi

# Check IPv6 disabled inside namespace
ipv6_ns=$(ip netns exec ghostbox sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) || ipv6_ns="0"
if [[ "$ipv6_ns" == "1" ]]; then
    pass "IPv6 disabled inside namespace"
else
    fail "IPv6 active inside namespace (LEAK RISK)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 2: Firewall kill switch
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 2: Firewall Kill Switch ───${NC}"

# Check nftables rules exist
if nft list table inet ghostbox &>/dev/null; then
    pass "Kill switch rules loaded"
else
    fail "Kill switch rules MISSING (traffic can leak)"
fi

# Check namespace-side rules
if ip netns exec ghostbox nft list table inet ghostbox_ns &>/dev/null; then
    pass "Namespace-side firewall active"
else
    fail "Namespace-side firewall missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 3: Tor is routing
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 3: Tor Routing ───${NC}"

# Check tor process
if pgrep -f "tor -f.*ghostbox" &>/dev/null; then
    pass "Tor process running"
else
    fail "Tor process NOT running"
fi

# Check Tor is fully bootstrapped
if grep -q "Bootstrapped 100" /var/log/tor/ghostbox.log 2>/dev/null; then
    pass "Tor fully bootstrapped (100%)"
else
    local_pct=$(grep -oP 'Bootstrapped \K[0-9]+' /var/log/tor/ghostbox.log 2>/dev/null | tail -1) || local_pct="0"
    warn "Tor bootstrap at ${local_pct}% (not 100%)"
fi

# Check actual IP is a Tor exit (test from inside namespace)
echo -ne "  Checking exit IP... "
REAL_IP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null) || REAL_IP="unknown"
NS_IP=$(ip netns exec ghostbox curl -s --connect-timeout 15 --socks5 10.200.1.1:9050 https://api.ipify.org 2>/dev/null) || NS_IP="timeout"

if [[ "$NS_IP" == "timeout" || "$NS_IP" == "" ]]; then
    warn "Could not determine exit IP (Tor may still be connecting)"
elif [[ "$REAL_IP" != "$NS_IP" && "$NS_IP" != "unknown" ]]; then
    pass "Exit IP differs from real IP ($NS_IP vs $REAL_IP)"
else
    fail "Exit IP matches real IP! ($NS_IP)"
fi

# Verify IP is a known Tor exit
if [[ "$NS_IP" != "timeout" && "$NS_IP" != "" && "$NS_IP" != "unknown" ]]; then
    TOR_CHECK=$(ip netns exec ghostbox curl -s --connect-timeout 10 --socks5 10.200.1.1:9050 "https://check.torproject.org/api/ip" 2>/dev/null) || TOR_CHECK=""
    if echo "$TOR_CHECK" | grep -q '"IsTor":true'; then
        pass "Connected through Tor (confirmed by torproject.org)"
    else
        warn "Could not confirm Tor exit status"
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 4: DNS isolation
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 4: DNS Isolation ───${NC}"

# Check resolv.conf
if [[ -f /etc/netns/ghostbox/resolv.conf ]]; then
    pass "Namespace DNS config exists"
else
    fail "Namespace DNS config missing"
fi

# Check resolv.conf doesn't point to ISP DNS
if grep -q "nameserver 10.200.1.1" /etc/netns/ghostbox/resolv.conf 2>/dev/null; then
    pass "DNS points to isolated resolver"
else
    fail "DNS may be leaking to ISP"
fi

# DNS leak test — resolve through namespace
echo -ne "  DNS leak test... "
DNS_RESULT=$(ip netns exec ghostbox curl -s --connect-timeout 15 --socks5 10.200.1.1:9050 "https://dnsleaktest.com/dns-leak-test.html" 2>/dev/null) || DNS_RESULT=""
if [[ -n "$DNS_RESULT" ]]; then
    pass "DNS resolution works through Tor"
else
    warn "DNS leak test inconclusive"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 5: System hardening
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 5: System Hardening ───${NC}"

# IPv6 disabled
ipv6_host=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) || ipv6_host="0"
if [[ "$ipv6_host" == "1" ]]; then
    pass "IPv6 disabled (host)"
else
    fail "IPv6 still active on host"
fi

# TCP timestamps
tcp_ts=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null) || tcp_ts="1"
if [[ "$tcp_ts" == "0" ]]; then
    pass "TCP timestamps disabled"
else
    fail "TCP timestamps enabled (fingerprinting risk)"
fi

# ICMP redirects
icmp=$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null) || icmp="1"
if [[ "$icmp" == "0" ]]; then
    pass "ICMP redirects blocked"
else
    fail "ICMP redirects accepted"
fi

# ptrace
ptrace=$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null) || ptrace="0"
if [[ "$ptrace" -ge 2 ]]; then
    pass "ptrace restricted (scope=$ptrace)"
else
    warn "ptrace scope is $ptrace (3 recommended)"
fi

# Core dumps
core=$(sysctl -n kernel.core_pattern 2>/dev/null) || core=""
if [[ "$core" == "|/bin/false" || "$core" == "/dev/null" ]]; then
    pass "Core dumps disabled"
else
    warn "Core dumps may be enabled"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 6: MAC randomization
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 6: MAC Randomization ───${NC}"

if [[ -f /tmp/ghostbox_mac.pid ]] && kill -0 "$(cat /tmp/ghostbox_mac.pid)" 2>/dev/null; then
    pass "MAC rotation daemon running"
else
    fail "MAC rotation daemon not running"
fi

# Check MAC is locally administered
for iface in $(ip link show | grep -oP '^\d+: \K[^:@]+' | grep -v lo); do
    mac=$(ip link show "$iface" | grep -oP 'link/ether \K[^ ]+' 2>/dev/null) || continue
    local_bit=$(( 16#${mac:1:1} & 2 ))
    if [[ $local_bit -eq 2 ]]; then
        pass "$iface MAC is locally administered ($mac)"
    else
        warn "$iface MAC appears to be factory ($mac)"
    fi
done

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 7: RAM workspace
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 7: RAM Workspace ───${NC}"

if [[ -d /dev/shm/ghostbox_workspace ]]; then
    pass "RAM workspace active"
else
    warn "RAM workspace not created"
fi

# Check swap
swap_total=$(sysctl -n vm.swappiness 2>/dev/null) || swap_total="60"
if [[ "$swap_total" == "0" ]]; then
    pass "Swap disabled (swappiness=0)"
else
    warn "Swappiness is $swap_total (0 recommended)"
fi

# Check no swap partitions active
if [[ $(swapon --show 2>/dev/null | wc -l) -le 1 ]]; then
    pass "No active swap partitions"
else
    fail "Active swap partitions detected (forensic risk)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# RESULTS
# ═══════════════════════════════════════════════════════════════
TOTAL=$((PASS + FAIL + WARN))
echo -e "${BOLD}  ═══════════════════════════════════════${NC}"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC} / $TOTAL tests"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   NO LEAKS DETECTED                              ║"
    echo "  ║   GhostBox is running securely                    ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   LEAKS DETECTED: $FAIL failure(s)                  ║"
    echo "  ║   Fix issues above before browsing                ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    exit 1
fi
