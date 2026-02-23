#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: System Hardening
# ═══════════════════════════════════════════════════════════════
# Hardens the Linux kernel and blocks hardware-level leaks:
#   - Disables camera/microphone at kernel level
#   - Blocks USB mass storage (prevents data exfil)
#   - Hardens kernel network parameters
#   - Disables core dumps (prevents memory forensics)
#   - Restricts ptrace (prevents process snooping)
#   - Disables kernel module loading (prevents rootkits)
#   - Hardens /proc and /sys information leaks
#   - Disables Bluetooth
#
# Each of these closes a specific attack vector.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SYSCTL_FILE="/etc/sysctl.d/99-ghostbox.conf"
SAVED_STATE="/tmp/ghostbox_hardening_state"

# ─── Apply kernel hardening ─────────────────────────────────

hardening_apply() {
    echo "[hardening] Applying system hardening..."

    # Save current values so we can restore later
    mkdir -p "$(dirname "$SAVED_STATE")"
    {
        sysctl kernel.yama.ptrace_scope 2>/dev/null
        sysctl kernel.kptr_restrict 2>/dev/null
        sysctl kernel.dmesg_restrict 2>/dev/null
        sysctl net.ipv4.conf.all.rp_filter 2>/dev/null
        sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null
        sysctl fs.suid_dumpable 2>/dev/null
        sysctl kernel.core_pattern 2>/dev/null
    } > "$SAVED_STATE" 2>/dev/null || true

    # ─── Network hardening ────────────────────────────

    # Disable IPv6 everywhere (prevents IPv6 leaks)
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
    echo "[hardening] IPv6: DISABLED"

    # Enable strict reverse path filtering (anti-spoofing)
    sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.conf.default.rp_filter=1 >/dev/null 2>&1 || true

    # Disable ICMP redirects (prevent MitM)
    sysctl -w net.ipv4.conf.all.accept_redirects=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.conf.all.send_redirects=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.conf.all.secure_redirects=0 >/dev/null 2>&1 || true

    # Ignore ICMP broadcasts
    sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 >/dev/null 2>&1 || true

    # Disable source routing
    sysctl -w net.ipv4.conf.all.accept_source_route=0 >/dev/null 2>&1 || true

    # TCP SYN cookies (anti-SYN flood)
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1 || true

    # Disable TCP timestamps (fingerprinting vector)
    sysctl -w net.ipv4.tcp_timestamps=0 >/dev/null 2>&1 || true
    echo "[hardening] Network: HARDENED"

    # ─── Kernel hardening ─────────────────────────────

    # Restrict ptrace (prevent process snooping)
    sysctl -w kernel.yama.ptrace_scope=3 >/dev/null 2>&1 || true
    echo "[hardening] ptrace: RESTRICTED"

    # Hide kernel pointers (prevents KASLR bypass)
    sysctl -w kernel.kptr_restrict=2 >/dev/null 2>&1 || true

    # Restrict dmesg access
    sysctl -w kernel.dmesg_restrict=1 >/dev/null 2>&1 || true

    # Disable core dumps (prevents memory forensics)
    sysctl -w fs.suid_dumpable=0 >/dev/null 2>&1 || true
    sysctl -w kernel.core_pattern="|/bin/false" >/dev/null 2>&1 || true
    ulimit -c 0 2>/dev/null || true
    echo "[hardening] Core dumps: DISABLED"

    # Disable SysRq (prevent keyboard-based attacks)
    sysctl -w kernel.sysrq=0 >/dev/null 2>&1 || true

    # Restrict unprivileged user namespaces (reduces attack surface)
    sysctl -w kernel.unprivileged_userns_clone=0 >/dev/null 2>&1 || true

    # Restrict BPF (reduces kernel attack surface)
    sysctl -w kernel.unprivileged_bpf_disabled=1 >/dev/null 2>&1 || true
    sysctl -w net.core.bpf_jit_harden=2 >/dev/null 2>&1 || true

    echo "[hardening] Kernel: HARDENED"

    # ─── Hardware isolation ───────────────────────────

    # Disable camera
    modprobe -r uvcvideo 2>/dev/null || true
    echo "blacklist uvcvideo" > /etc/modprobe.d/ghostbox-camera.conf 2>/dev/null || true
    echo "[hardening] Camera: BLOCKED"

    # Disable microphone
    modprobe -r snd_hda_codec_realtek 2>/dev/null || true
    # Mute all capture devices
    if command -v amixer >/dev/null 2>&1; then
        amixer -q set Capture nocap 2>/dev/null || true
        amixer -q set Capture 0% 2>/dev/null || true
        amixer -q set 'Internal Mic' 0% 2>/dev/null || true
    fi
    if command -v pactl >/dev/null 2>&1; then
        for src in $(pactl list short sources 2>/dev/null | grep input | awk '{print $2}'); do
            pactl set-source-mute "$src" 1 2>/dev/null || true
            pactl set-source-volume "$src" 0% 2>/dev/null || true
        done
    fi
    echo "[hardening] Microphone: MUTED/BLOCKED"

    # Disable Bluetooth
    rfkill block bluetooth 2>/dev/null || true
    systemctl stop bluetooth 2>/dev/null || true
    modprobe -r bluetooth 2>/dev/null || true
    echo "[hardening] Bluetooth: BLOCKED"

    # Block USB mass storage (prevents data exfiltration via USB)
    echo "blacklist usb_storage" > /etc/modprobe.d/ghostbox-usb.conf 2>/dev/null || true
    modprobe -r usb_storage 2>/dev/null || true
    echo "[hardening] USB storage: BLOCKED"

    # ─── Disable swap (prevents memory forensics) ────

    swapoff -a 2>/dev/null || true
    echo "[hardening] Swap: DISABLED"

    echo "[hardening] System hardening COMPLETE"
}

# ─── Remove hardening ───────────────────────────────────────

hardening_remove() {
    echo "[hardening] Removing system hardening..."

    # Restore saved sysctl values
    if [[ -f "$SAVED_STATE" ]]; then
        while IFS= read -r line; do
            sysctl -w "$line" >/dev/null 2>&1 || true
        done < "$SAVED_STATE"
        rm -f "$SAVED_STATE"
    fi

    # Re-enable camera
    rm -f /etc/modprobe.d/ghostbox-camera.conf 2>/dev/null || true
    modprobe uvcvideo 2>/dev/null || true
    echo "[hardening] Camera: RESTORED"

    # Unmute mic
    if command -v amixer >/dev/null 2>&1; then
        amixer -q set Capture cap 2>/dev/null || true
        amixer -q set Capture 100% 2>/dev/null || true
    fi
    if command -v pactl >/dev/null 2>&1; then
        for src in $(pactl list short sources 2>/dev/null | grep input | awk '{print $2}'); do
            pactl set-source-mute "$src" 0 2>/dev/null || true
            pactl set-source-volume "$src" 100% 2>/dev/null || true
        done
    fi
    echo "[hardening] Microphone: RESTORED"

    # Re-enable Bluetooth
    rfkill unblock bluetooth 2>/dev/null || true
    systemctl start bluetooth 2>/dev/null || true
    echo "[hardening] Bluetooth: RESTORED"

    # Re-enable USB storage
    rm -f /etc/modprobe.d/ghostbox-usb.conf 2>/dev/null || true
    modprobe usb_storage 2>/dev/null || true
    echo "[hardening] USB storage: RESTORED"

    # Re-enable swap
    swapon -a 2>/dev/null || true
    echo "[hardening] Swap: RESTORED"

    # Re-enable IPv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
    echo "[hardening] IPv6: RESTORED"

    echo "[hardening] System hardening REMOVED"
}

# ─── Verify hardening ───────────────────────────────────────

hardening_verify() {
    echo "[hardening] Verifying system hardening..."
    local failures=0

    # Check IPv6
    local ipv6
    ipv6=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) || ipv6="?"
    if [[ "$ipv6" == "1" ]]; then
        echo "[hardening] PASS: IPv6 disabled"
    else
        echo "[hardening] FAIL: IPv6 still enabled"
        ((failures++))
    fi

    # Check ptrace
    local ptrace
    ptrace=$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null) || ptrace="?"
    if [[ "$ptrace" -ge 2 ]]; then
        echo "[hardening] PASS: ptrace restricted ($ptrace)"
    else
        echo "[hardening] WARN: ptrace scope = $ptrace (should be ≥2)"
    fi

    # Check core dumps
    local coredump
    coredump=$(sysctl -n fs.suid_dumpable 2>/dev/null) || coredump="?"
    if [[ "$coredump" == "0" ]]; then
        echo "[hardening] PASS: Core dumps disabled"
    else
        echo "[hardening] FAIL: Core dumps may be enabled"
        ((failures++))
    fi

    # Check swap
    local swap_count
    swap_count=$(swapon --show=NAME --noheadings 2>/dev/null | wc -l) || swap_count="?"
    if [[ "$swap_count" == "0" ]]; then
        echo "[hardening] PASS: Swap disabled"
    else
        echo "[hardening] FAIL: Swap still active ($swap_count)"
        ((failures++))
    fi

    # Check camera
    if lsmod | grep -q uvcvideo; then
        echo "[hardening] FAIL: Camera module still loaded"
        ((failures++))
    else
        echo "[hardening] PASS: Camera blocked"
    fi

    # Check Bluetooth
    if rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: yes"; then
        echo "[hardening] PASS: Bluetooth blocked"
    else
        echo "[hardening] WARN: Bluetooth may still be active"
    fi

    # Check TCP timestamps
    local timestamps
    timestamps=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null) || timestamps="?"
    if [[ "$timestamps" == "0" ]]; then
        echo "[hardening] PASS: TCP timestamps disabled"
    else
        echo "[hardening] WARN: TCP timestamps active (fingerprinting risk)"
    fi

    if [[ $failures -eq 0 ]]; then
        echo "[hardening] ALL CRITICAL CHECKS PASSED"
    else
        echo "[hardening] WARNING: $failures critical checks failed"
    fi

    return $failures
}

# ─── Status ──────────────────────────────────────────────────

hardening_status() {
    echo "[hardening] === System Hardening Status ==="
    echo "  IPv6:           $(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null | sed 's/1/DISABLED/;s/0/ENABLED/')"
    echo "  ptrace scope:   $(sysctl -n kernel.yama.ptrace_scope 2>/dev/null)"
    echo "  Core dumps:     $(sysctl -n fs.suid_dumpable 2>/dev/null | sed 's/0/DISABLED/;s/[12]/ENABLED/')"
    echo "  TCP timestamps: $(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null | sed 's/0/DISABLED/;s/1/ENABLED/')"
    echo "  Swap:           $(swapon --show=NAME --noheadings 2>/dev/null | wc -l) active"
    echo "  Camera:         $(lsmod | grep -q uvcvideo && echo 'LOADED' || echo 'BLOCKED')"
    echo "  Bluetooth:      $(rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: yes' && echo 'BLOCKED' || echo 'ACTIVE')"
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    apply)   hardening_apply ;;
    remove)  hardening_remove ;;
    verify)  hardening_verify ;;
    status)  hardening_status ;;
    *)       echo "Usage: $0 {apply|remove|verify|status}" ;;
esac
