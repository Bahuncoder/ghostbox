#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#   GhostBox Identity Test
#   Verifies identity rotation is consistent and working
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/../modules"

PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}✓ PASS${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${NC} $1"; ((FAIL++)); }

echo -e "${CYAN}${BOLD}"
echo "  GhostBox Identity Test"
echo "  ═══════════════════════"
echo -e "${NC}"

# ═══════════════════════════════════════════════════════════════
# TEST 1: Generate identity
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 1: Identity Generation ───${NC}"

output=$(python3 "$MODULES_DIR/identity_engine.py" generate 2>&1)
if [[ $? -eq 0 ]]; then
    pass "Identity generated successfully"
else
    fail "Identity generation failed"
    echo "  Output: $output"
fi

# ═══════════════════════════════════════════════════════════════
# TEST 2: Show identity
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 2: Identity Display ───${NC}"

show_output=$(python3 "$MODULES_DIR/identity_engine.py" show 2>&1)
if [[ $? -eq 0 ]]; then
    pass "Identity display works"
else
    fail "Identity display failed"
fi

# Check required fields
for field in "Region" "MAC" "Hostname" "Timezone" "Platform"; do
    if echo "$show_output" | grep -q "$field"; then
        pass "Field present: $field"
    else
        fail "Field missing: $field"
    fi
done

# ═══════════════════════════════════════════════════════════════
# TEST 3: Identity consistency
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 3: Identity Consistency ───${NC}"

# Generate for a specific region
python3 "$MODULES_DIR/identity_engine.py" generate --region us-east >/dev/null 2>&1
show1=$(python3 "$MODULES_DIR/identity_engine.py" show 2>&1)

# Check timezone matches region
tz1=$(echo "$show1" | grep "Timezone" | awk '{print $NF}')
if [[ "$tz1" == *"America/New_York"* || "$tz1" == *"America/Chicago"* ]]; then
    pass "Timezone matches US-East region ($tz1)"
else
    fail "Timezone doesn't match region ($tz1)"
fi

# Generate for different region
python3 "$MODULES_DIR/identity_engine.py" generate --region asia-east >/dev/null 2>&1
show2=$(python3 "$MODULES_DIR/identity_engine.py" show 2>&1)

# Check timezone changed
tz2=$(echo "$show2" | grep "Timezone" | awk '{print $NF}')
if [[ "$tz1" != "$tz2" ]]; then
    pass "Timezone changed with region ($tz1 → $tz2)"
else
    fail "Timezone didn't change with region"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 4: Identity rotation (uniqueness)
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 4: Identity Uniqueness ───${NC}"

declare -a macs=()
for i in {1..5}; do
    python3 "$MODULES_DIR/identity_engine.py" generate >/dev/null 2>&1
    show_out=$(python3 "$MODULES_DIR/identity_engine.py" show 2>&1)
    mac=$(echo "$show_out" | grep "MAC" | awk '{print $NF}')
    macs+=("$mac")
done

# Check all MACs are different
unique_macs=$(printf '%s\n' "${macs[@]}" | sort -u | wc -l)
if [[ $unique_macs -ge 4 ]]; then
    pass "Generated $unique_macs/5 unique MACs"
else
    fail "Only $unique_macs/5 unique MACs (identity not rotating properly)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 5: Environment export
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 5: Environment Export ───${NC}"

python3 "$MODULES_DIR/identity_engine.py" generate >/dev/null 2>&1
env_output=$(python3 "$MODULES_DIR/identity_engine.py" export-env 2>&1)

for var in "GHOST_MAC" "GHOST_HOSTNAME" "GHOST_TZ" "GHOST_LAT" "GHOST_LON"; do
    if echo "$env_output" | grep -q "$var="; then
        pass "Environment variable: $var"
    else
        fail "Missing env variable: $var"
    fi
done

echo ""

# ═══════════════════════════════════════════════════════════════
# TEST 6: Browser spoof JS
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}  ─── Test 6: Browser Spoof Script ───${NC}"

python3 "$MODULES_DIR/identity_engine.py" export-js >/dev/null 2>&1
JS_FILE="$(dirname "$MODULES_DIR")/configs/browser_profile/spoof.js"

if [[ -f "$JS_FILE" ]]; then
    pass "Spoof JS file generated"
else
    fail "Spoof JS file not generated"
fi

if [[ -f "$JS_FILE" ]]; then
    for keyword in "navigator" "geolocation" "WebGLRenderingContext" "timezone" "canvas"; do
        if grep -q "$keyword" "$JS_FILE"; then
            pass "JS overrides: $keyword"
        else
            fail "JS missing override: $keyword"
        fi
    done
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# RESULTS
# ═══════════════════════════════════════════════════════════════
TOTAL=$((PASS + FAIL))
echo -e "${BOLD}  ═══════════════════════════════════════${NC}"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} / $TOTAL tests"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  All identity tests passed!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}  $FAIL test(s) failed!${NC}"
    exit 1
fi
