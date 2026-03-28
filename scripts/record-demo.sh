#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Remo Demo Recorder
#
# Captures a demo video and timestamps by driving the curated capability
# sequence on a running RemoExample simulator.
#
# Usage:
#   ./scripts/record-demo.sh                     # full run (builds first)
#   SKIP_BUILD=1 ./scripts/record-demo.sh        # skip build, app must be running
#
# Prerequisites:
#   - A booted iOS Simulator
#   - RemoExample.app built and installed (or omit SKIP_BUILD)
#
# Outputs (in $ARTIFACTS_DIR, default /tmp/remo-demo):
#   demo.mp4              — screen recording of the app
#   demo-timestamps.json  — array of { capability, params, elapsed_s }
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-/tmp/remo-demo}"
SKIP_BUILD="${SKIP_BUILD:-0}"
REMO_BIN="${REMO_BIN:-$ROOT/target/debug/remo}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

RECORD_PID=""
APP_LAUNCHED=false

cleanup() {
    echo ""
    echo -e "${CYAN}--- Cleanup ---${RESET}"
    if [ -n "$RECORD_PID" ] && kill -0 "$RECORD_PID" 2>/dev/null; then
        echo "Stopping screen recording (pid=$RECORD_PID)..."
        kill -INT "$RECORD_PID" 2>/dev/null || true
        wait "$RECORD_PID" 2>/dev/null || true
    fi
    if [ "$APP_LAUNCHED" = true ] && [ -n "${DEVICE_UUID:-}" ]; then
        echo "Terminating app..."
        xcrun simctl terminate "$DEVICE_UUID" com.remo.example 2>/dev/null || true
    fi
}
trap cleanup EXIT

log()  { echo -e "${CYAN}==>${RESET} ${BOLD}$*${RESET}"; }

# High-resolution elapsed time (seconds since epoch, millisecond precision)
now_s() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time()'; }

remo_call() {
    local capability="$1"
    local params="${2:-\{\}}"
    "$REMO_BIN" call -a "$ADDR" "$capability" "$params" 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | sed -n '/^{/,/^}/p'
}

# ---------------------------------------------------------------------------
# Phase 0: Build (optional)
# ---------------------------------------------------------------------------

log "Phase 0: Build"

if [ "$SKIP_BUILD" = "1" ]; then
    echo "  Skipping build (SKIP_BUILD=1)"
    if [ ! -f "$REMO_BIN" ]; then
        echo -e "${RED}ERROR:${RESET} remo binary not found at $REMO_BIN"
        exit 1
    fi
else
    log "Building iOS SDK (simulator)..."
    (cd "$ROOT" && make ios-sim)

    log "Building CLI..."
    (cd "$ROOT" && cargo build -p remo-cli)
fi

echo "  remo: $REMO_BIN"

# ---------------------------------------------------------------------------
# Phase 1: Install & Launch
# ---------------------------------------------------------------------------

log "Phase 1: Install & Launch"

DEVICE_UUID="${DEVICE_UUID:-$(xcrun simctl list devices booted -j | jq -r '.devices[][] | select(.state == "Booted") | .udid' | head -1)}"
if [ -z "$DEVICE_UUID" ]; then
    echo -e "${RED}ERROR:${RESET} No booted simulator found."
    exit 1
fi
DEVICE_NAME=$(xcrun simctl list devices -j | jq -r --arg uuid "$DEVICE_UUID" '.devices[][] | select(.udid == $uuid) | .name')
echo "  Device: $DEVICE_NAME ($DEVICE_UUID)"

if [ "$SKIP_BUILD" != "1" ]; then
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "RemoExample.app" -path "*/Debug-iphonesimulator/*" -maxdepth 5 2>/dev/null | head -1)
    if [ -z "$APP_PATH" ]; then
        echo -e "${RED}ERROR:${RESET} RemoExample.app not found in DerivedData"
        exit 1
    fi

    # Fresh install
    for uuid in $(xcrun simctl list devices booted -j | jq -r '.devices[][] | .udid'); do
        xcrun simctl terminate "$uuid" com.remo.example 2>/dev/null || true
    done
    xcrun simctl uninstall "$DEVICE_UUID" com.remo.example 2>/dev/null || true
    sleep 1
    "$REMO_BIN" stop 2>/dev/null || true
    sleep 0.5

    echo "  Installing $APP_PATH..."
    xcrun simctl install "$DEVICE_UUID" "$APP_PATH"
    echo "  Launching..."
    LAUNCH_OUTPUT=$(xcrun simctl launch "$DEVICE_UUID" com.remo.example)
    APP_LAUNCHED=true
    APP_PID=$(echo "$LAUNCH_OUTPUT" | grep -oE '[0-9]+$' || true)
    echo "  PID: $APP_PID"
fi

# ---------------------------------------------------------------------------
# Phase 2: Discover Port
# ---------------------------------------------------------------------------

log "Phase 2: Discover Remo Port"

ADDR="${ADDR:-}"

# Skip discovery if ADDR was provided via environment
if [ -n "$ADDR" ]; then
    echo "  Using provided ADDR=$ADDR"
# If we launched the app, find port via lsof
elif [ -n "${APP_PID:-}" ]; then
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        echo "  Attempt $attempt/10 (lsof)..."
        sleep 2
        PORT=$(lsof -nP -iTCP -sTCP:LISTEN -a -p "$APP_PID" 2>/dev/null \
            | awk '/LISTEN/{print $9}' \
            | grep -oE '[0-9]+$' \
            | head -1 || true)
        if [ -n "$PORT" ]; then
            ADDR="127.0.0.1:$PORT"
            if remo_call __ping '{}' 2>/dev/null | jq -e '.data.pong == true' >/dev/null 2>&1; then
                echo "  Found device at $ADDR (via lsof)"
                break
            else
                ADDR=""
            fi
        fi
    done
fi

# Fallback: Bonjour discovery
if [ -z "$ADDR" ]; then
    echo "  Falling back to Bonjour discovery..."
    for attempt in 1 2 3 4 5; do
        echo "  Attempt $attempt/5 (Bonjour)..."
        sleep 3
        DEVICES_OUTPUT=$("$REMO_BIN" devices 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true)
        ADDR=$(echo "$DEVICES_OUTPUT" \
            | grep -E '^Bonjour ' \
            | awk '{print $NF}' \
            | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$' \
            | head -1 || true)
        if [ -n "$ADDR" ]; then
            if remo_call __ping '{}' 2>/dev/null | jq -e '.data.pong == true' >/dev/null 2>&1; then
                echo "  Found device at $ADDR (via Bonjour)"
                break
            else
                ADDR=""
            fi
        fi
    done
fi

if [ -z "$ADDR" ]; then
    echo -e "${RED}ERROR:${RESET} Could not discover Remo device"
    exit 1
fi

# ---------------------------------------------------------------------------
# Phase 3: Start Recording
# ---------------------------------------------------------------------------

mkdir -p "$ARTIFACTS_DIR"
TIMESTAMPS_FILE="$ARTIFACTS_DIR/demo-timestamps.json"

# NOTE: We use simctl recordVideo instead of `remo mirror --save` because
# the remo mirror MP4 muxer uses a hardcoded frame duration (3000 in 90kHz
# timescale = 33.3ms per frame) regardless of actual frame arrival intervals.
# This causes idle periods to be compressed — a 17s real recording becomes
# ~10s of video. simctl recordVideo maintains proper wall-clock timing.
# See: https://github.com/yjmeqt/Remo/issues/18 (remo mirror MP4 timing)
log "Starting screen recording..."
xcrun simctl io "$DEVICE_UUID" recordVideo --codec=h264 --force "$ARTIFACTS_DIR/demo.mp4" &
RECORD_PID=$!
sleep 1
echo "  Recording to $ARTIFACTS_DIR/demo.mp4 (pid=$RECORD_PID)"

# Mark time zero — all elapsed_s values are relative to this
EPOCH=$(now_s)

# Start JSON array
echo "[" > "$TIMESTAMPS_FILE"

# Helper: call a capability, log timestamp, sleep for UI animation
demo_step() {
    local capability="$1"
    local params="${2:-\{\}}"
    local sleep_after="${3:-0.5}"

    remo_call "$capability" "$params" >/dev/null
    local elapsed
    elapsed=$(perl -e "printf '%.2f', $(now_s) - $EPOCH")

    echo -e "  ${GREEN}[$elapsed s]${RESET} $capability $params"

    # Append JSON entry (last entry added manually without trailing comma)
    cat >> "$TIMESTAMPS_FILE" <<ENTRY
  { "capability": "$capability", "params": $params, "elapsed_s": $elapsed },
ENTRY

    sleep "$sleep_after"
}

# Helper: take a screenshot and log timestamp
demo_screenshot() {
    local name="${1:-screenshot}"
    "$REMO_BIN" screenshot -a "$ADDR" -o "$ARTIFACTS_DIR/${name}.jpg" --format jpeg --quality 0.8 2>/dev/null || true
    local elapsed
    elapsed=$(perl -e "printf '%.2f', $(now_s) - $EPOCH")
    echo -e "  ${GREEN}[$elapsed s]${RESET} screenshot → ${name}.jpg"
    cat >> "$TIMESTAMPS_FILE" <<ENTRY
  { "capability": "screenshot", "params": {"name":"$name"}, "elapsed_s": $elapsed },
ENTRY
    sleep 0.5
}

# ---------------------------------------------------------------------------
# Phase 4: Demo Sequence
#
# Pacing is deliberately slow so that UI animations (confetti, toasts,
# tab transitions) are fully visible in the recording.
# ---------------------------------------------------------------------------

log "Phase 4: Running demo sequence..."

echo ""
echo -e "${BOLD}[Counter]${RESET}"
demo_step "counter.increment" '{"amount":1}' 1.0
demo_step "counter.increment" '{"amount":1}' 1.0
demo_step "counter.increment" '{"amount":1}' 1.0
demo_screenshot "01-counter"

echo ""
echo -e "${BOLD}[UI Effects]${RESET}"
demo_step "ui.toast" '{"message":"Features verified ✓"}' 2.5
demo_screenshot "02-toast"
demo_step "ui.setAccentColor" '{"color":"purple"}' 1.5
demo_screenshot "03-accent"
demo_step "ui.confetti" '{}' 3.0
demo_screenshot "04-confetti"

echo ""
echo -e "${BOLD}[Navigation & Items]${RESET}"
demo_step "navigate" '{"route":"items"}' 1.5
demo_screenshot "05-items-page"
demo_step "items.add" '{"name":"Test Item 1"}' 1.0
demo_step "items.add" '{"name":"Test Item 2"}' 1.0
demo_screenshot "06-items-added"

# Close JSON array — strip trailing comma from last entry
sed -i '' '$ s/,$//' "$TIMESTAMPS_FILE"
echo "]" >> "$TIMESTAMPS_FILE"

# ---------------------------------------------------------------------------
# Phase 5: Stop Recording
# ---------------------------------------------------------------------------

log "Stopping screen recording..."
kill -INT "$RECORD_PID" 2>/dev/null || true
wait "$RECORD_PID" 2>/dev/null || true
RECORD_PID=""
sleep 1

# Verify recording
if [ -f "$ARTIFACTS_DIR/demo.mp4" ] && [ -s "$ARTIFACTS_DIR/demo.mp4" ]; then
    RECORDING_SIZE=$(ls -lh "$ARTIFACTS_DIR/demo.mp4" | awk '{print $5}')
    echo "  Video saved: $RECORDING_SIZE"
else
    echo -e "${RED}WARNING:${RESET} demo.mp4 missing or empty"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "==========================================="
echo -e " ${BOLD}Demo recording complete${RESET}"
echo "==========================================="
echo "  Video:       $ARTIFACTS_DIR/demo.mp4"
echo "  Timestamps:  $ARTIFACTS_DIR/demo-timestamps.json"
echo "  Screenshot:  $ARTIFACTS_DIR/demo-screenshot.jpg"
echo ""
echo "Timestamps:"
cat "$TIMESTAMPS_FILE"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. cp $ARTIFACTS_DIR/demo.mp4 website/public/demo.mp4"
echo "  2. Update website/src/components/DemoHero/timeline.ts"
echo "     with elapsed_s values from demo-timestamps.json"
