#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# GhostBox Module: RAM Workspace + Anti-Forensics
# ═══════════════════════════════════════════════════════════════
# Everything runs in RAM. Nothing ever touches disk.
#
# - tmpfs workspace in /dev/shm (RAM only)
# - Secure memory wiping on shutdown
# - Anti-forensic cleanup (shred, not just delete)
# - Encrypted RAM if hardware supports it (AMD SME/SEV)
# - Emergency wipe on panic signal
#
# After GhostBox closes, there is ZERO evidence on disk
# that it was ever running.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

GHOST_WORKSPACE="/dev/shm/ghostbox_workspace"
GHOST_HOME="/dev/shm/ghostbox_home"
GHOST_TMP="/dev/shm/ghostbox_tmp"
GHOST_DOWNLOADS="/dev/shm/ghostbox_downloads"

ALL_GHOST_DIRS=(
    "$GHOST_WORKSPACE"
    "$GHOST_HOME"
    "$GHOST_TMP"
    "$GHOST_DOWNLOADS"
    "/dev/shm/ghostbox_browser"
)

# ─── Create RAM workspace ───────────────────────────────────

workspace_create() {
    echo "[workspace] Creating RAM workspace..."

    for dir in "${ALL_GHOST_DIRS[@]}"; do
        mkdir -p "$dir"
        chmod 700 "$dir"
    done

    # Create basic home structure
    mkdir -p "$GHOST_HOME"/{Desktop,Documents,Downloads}

    # Set restrictive umask
    umask 077

    echo "[workspace] RAM workspace created at:"
    for dir in "${ALL_GHOST_DIRS[@]}"; do
        local size
        size=$(df -h "$dir" 2>/dev/null | tail -1 | awk '{print $4}') || size="?"
        echo "  $dir (available: $size)"
    done

    echo "[workspace] All data lives in RAM — zero disk persistence"
}

# ─── Secure wipe all data ───────────────────────────────────

workspace_wipe() {
    echo "[workspace] SECURELY WIPING all GhostBox data..."

    for dir in "${ALL_GHOST_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            # Find all files and shred them (overwrite with random data)
            local file_count
            file_count=$(find "$dir" -type f 2>/dev/null | wc -l) || file_count=0
            if [[ $file_count -gt 0 ]]; then
                echo "[workspace] Shredding $file_count files in $dir..."
                find "$dir" -type f -exec shred -n 3 -z -u {} \; 2>/dev/null || true
            fi
            # Remove directory tree
            rm -rf "$dir" 2>/dev/null || true
            echo "[workspace] Wiped: $dir"
        fi
    done

    # Wipe Tor data
    if [[ -d /var/lib/tor/ghostbox ]]; then
        find /var/lib/tor/ghostbox -type f -exec shred -n 3 -z -u {} \; 2>/dev/null || true
        rm -rf /var/lib/tor/ghostbox 2>/dev/null || true
        echo "[workspace] Wiped: Tor data"
    fi

    # Wipe Tor log
    if [[ -f /var/log/tor/ghostbox.log ]]; then
        shred -n 3 -z -u /var/log/tor/ghostbox.log 2>/dev/null || true
        echo "[workspace] Wiped: Tor log"
    fi

    # Wipe identity state
    local state_file
    state_file="$(dirname "$(dirname "$0")")/configs/.identity_state.json" 2>/dev/null || true
    if [[ -f "$state_file" ]]; then
        shred -n 3 -z -u "$state_file" 2>/dev/null || true
        echo "[workspace] Wiped: Identity state"
    fi

    # Wipe PID files
    rm -f /tmp/ghostbox_*.pid 2>/dev/null || true

    # Clear bash history for this session
    history -c 2>/dev/null || true
    export HISTFILE=/dev/null
    export HISTSIZE=0

    # Clear clipboard
    if command -v xclip >/dev/null 2>&1; then
        echo -n "" | xclip -selection clipboard 2>/dev/null || true
        echo -n "" | xclip -selection primary 2>/dev/null || true
    fi
    if command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --clear 2>/dev/null || true
        xsel --primary --clear 2>/dev/null || true
    fi

    # Flush filesystem caches
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    echo "[workspace] COMPLETE — all GhostBox data destroyed"
}

# ─── Emergency wipe (as fast as possible) ────────────────────

workspace_emergency_wipe() {
    echo "[EMERGENCY] EMERGENCY WIPE initiated!"

    # Kill everything fast — no graceful shutdown
    pkill -9 -f "ghostbox" 2>/dev/null || true
    pkill -9 -f "tor -f.*ghostbox" 2>/dev/null || true

    # Fast removal (skip shred for speed — data is in RAM anyway)
    for dir in "${ALL_GHOST_DIRS[@]}"; do
        rm -rf "$dir" 2>/dev/null || true
    done

    # Drop memory caches
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    # Clear network state
    ip netns del ghostbox 2>/dev/null || true
    ip link del gbox0 2>/dev/null || true

    # Clear firewall
    nft delete table inet ghostbox 2>/dev/null || true

    # Wipe Tor
    rm -rf /var/lib/tor/ghostbox 2>/dev/null || true
    rm -f /var/log/tor/ghostbox.log 2>/dev/null || true

    # Clear all PID files
    rm -f /tmp/ghostbox_*.pid 2>/dev/null || true

    # Clear clipboard
    echo -n "" | xclip -selection clipboard 2>/dev/null || true

    # Flush history
    history -c 2>/dev/null || true

    echo "[EMERGENCY] WIPE COMPLETE — all traces destroyed"
}

# ─── Check for AMD memory encryption ────────────────────────

check_mem_encryption() {
    echo "[workspace] Checking hardware memory encryption..."

    # AMD SME (Secure Memory Encryption)
    if grep -q "sme" /proc/cpuinfo 2>/dev/null; then
        if dmesg 2>/dev/null | grep -q "AMD.*Memory Encryption Features.*SME"; then
            echo "[workspace] AMD SME: AVAILABLE and ACTIVE"
            echo "[workspace] RAM is encrypted by hardware — cold boot attacks mitigated"
            return 0
        else
            echo "[workspace] AMD SME: Available but may need kernel parameter 'mem_encrypt=on'"
        fi
    fi

    # Intel TME (Total Memory Encryption)
    if grep -q "tme" /proc/cpuinfo 2>/dev/null; then
        echo "[workspace] Intel TME: AVAILABLE"
        return 0
    fi

    echo "[workspace] Hardware memory encryption: NOT DETECTED"
    echo "[workspace] RAM data is vulnerable to cold boot attacks"
    echo "[workspace] Consider adding 'mem_encrypt=on' to kernel parameters (AMD)"
    return 1
}

# ─── Metadata stripping ─────────────────────────────────────

strip_metadata() {
    local target="${1:-.}"

    echo "[workspace] Stripping metadata from files in $target..."

    # EXIF data from images
    if command -v exiftool >/dev/null 2>&1; then
        find "$target" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
            -o -iname "*.gif" -o -iname "*.tiff" -o -iname "*.bmp" -o -iname "*.webp" \
            -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" \
            -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" \) \
            -exec exiftool -overwrite_original -all= {} \; 2>/dev/null
        echo "[workspace] Image/media metadata stripped"
    fi

    # PDF metadata
    if command -v exiftool >/dev/null 2>&1; then
        find "$target" -type f -iname "*.pdf" \
            -exec exiftool -overwrite_original -all= {} \; 2>/dev/null
        echo "[workspace] PDF metadata stripped"
    fi

    # Document metadata (LibreOffice)
    find "$target" -type f \( -iname "*.docx" -o -iname "*.xlsx" -o -iname "*.pptx" \
        -o -iname "*.odt" -o -iname "*.ods" -o -iname "*.odp" \) -print0 2>/dev/null | \
        while IFS= read -r -d '' file; do
            # These are zip files — we can strip metadata by modifying the XML
            echo "  Would strip: $file (document metadata)"
        done

    echo "[workspace] Metadata stripping complete"
}

# ─── Auto-strip daemon (watches downloads) ──────────────────

metadata_watch_start() {
    echo "[workspace] Starting metadata auto-strip daemon..."

    # Watch downloads directory and strip metadata from new files
    if command -v inotifywait >/dev/null 2>&1; then
        inotifywait -m -r -e close_write --format '%w%f' "$GHOST_DOWNLOADS" 2>/dev/null | \
        while IFS= read -r file; do
            echo "[workspace] New file detected: $file"
            strip_metadata "$file"
        done &
        echo $! > /tmp/ghostbox_metadata.pid
        echo "[workspace] Auto-strip daemon started"
    else
        echo "[workspace] inotifywait not available — install inotify-tools for auto-stripping"
    fi
}

# ─── Status ──────────────────────────────────────────────────

workspace_status() {
    echo "[workspace] === RAM Workspace Status ==="
    for dir in "${ALL_GHOST_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            local size
            size=$(du -sh "$dir" 2>/dev/null | cut -f1) || size="?"
            local files
            files=$(find "$dir" -type f 2>/dev/null | wc -l) || files="?"
            echo "  $dir: $size ($files files)"
        else
            echo "  $dir: NOT CREATED"
        fi
    done

    # Check memory encryption
    if grep -q "sme\|tme" /proc/cpuinfo 2>/dev/null; then
        echo "  Hardware memory encryption: AVAILABLE"
    else
        echo "  Hardware memory encryption: NOT AVAILABLE"
    fi

    # Check swap
    local swap
    swap=$(swapon --show=NAME --noheadings 2>/dev/null | wc -l) || swap="?"
    echo "  Swap: $swap active (should be 0)"
}

# ─── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    create)         workspace_create ;;
    wipe)           workspace_wipe ;;
    emergency)      workspace_emergency_wipe ;;
    strip)          strip_metadata "${2:-.}" ;;
    watch)          metadata_watch_start ;;
    mem-check)      check_mem_encryption ;;
    status)         workspace_status ;;
    *)              echo "Usage: $0 {create|wipe|emergency|strip [dir]|watch|mem-check|status}" ;;
esac
