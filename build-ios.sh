#!/usr/bin/env bash
set -euo pipefail

# Build remo-sdk for iOS targets and package into an XCFramework.
#
# Usage:
#   ./build-ios.sh sim        # arm64 simulator only (debug, fastest)
#   ./build-ios.sh device     # arm64 device only (debug)
#   ./build-ios.sh debug      # all targets (debug)
#   ./build-ios.sh release    # all targets (release, for CI)
#   ./build-ios.sh            # defaults to release
#
# Requires: rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-release}"

# Determine profile and which targets to build.
case "$MODE" in
    sim)
        PROFILE="debug"
        FLAGS=""
        TARGETS="sim"
        ;;
    device)
        PROFILE="debug"
        FLAGS=""
        TARGETS="device"
        ;;
    debug)
        PROFILE="debug"
        FLAGS=""
        TARGETS="all"
        ;;
    release)
        PROFILE="release"
        FLAGS="--release"
        TARGETS="all"
        ;;
    *)
        echo "Usage: $0 {sim|device|debug|release}"
        exit 1
        ;;
esac

HEADER="swift/RemoSwift/Sources/RemoSwift/include/remo.h"
XCFRAMEWORK="swift/RemoSDK.xcframework"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

if [ "$TARGETS" = "device" ] || [ "$TARGETS" = "all" ]; then
    echo "==> Building remo-sdk for aarch64-apple-ios ($PROFILE)..."
    cargo build -p remo-sdk --features ios --target aarch64-apple-ios $FLAGS
fi

if [ "$TARGETS" = "sim" ] || [ "$TARGETS" = "all" ]; then
    echo "==> Building remo-sdk for aarch64-apple-ios-sim ($PROFILE)..."
    cargo build -p remo-sdk --features ios --target aarch64-apple-ios-sim $FLAGS
fi

if [ "$TARGETS" = "all" ]; then
    echo "==> Building remo-sdk for x86_64-apple-ios ($PROFILE)..."
    cargo build -p remo-sdk --features ios --target x86_64-apple-ios $FLAGS
fi

# ---------------------------------------------------------------------------
# Package XCFramework
# ---------------------------------------------------------------------------

echo "==> Creating XCFramework..."
rm -rf "$XCFRAMEWORK"

prepare_headers() {
    local dir="$1"
    mkdir -p "$dir/Headers"
    cp "$HEADER" "$dir/Headers/"
    cat > "$dir/Headers/module.modulemap" <<'MODULEMAP'
module CRemo {
    header "remo.h"
    export *
}
MODULEMAP
}

if [ "$TARGETS" = "sim" ]; then
    # Simulator-only XCFramework (single architecture).
    SIM_LIB="target/aarch64-apple-ios-sim/$PROFILE/libremo_sdk.a"
    TMPDIR_SIM=$(mktemp -d)
    prepare_headers "$TMPDIR_SIM"
    cp "$SIM_LIB" "$TMPDIR_SIM/"

    xcodebuild -create-xcframework \
        -library "$TMPDIR_SIM/libremo_sdk.a" -headers "$TMPDIR_SIM/Headers" \
        -output "$XCFRAMEWORK"
    rm -rf "$TMPDIR_SIM"

elif [ "$TARGETS" = "device" ]; then
    # Device-only XCFramework (single architecture).
    DEVICE_LIB="target/aarch64-apple-ios/$PROFILE/libremo_sdk.a"
    TMPDIR_DEVICE=$(mktemp -d)
    prepare_headers "$TMPDIR_DEVICE"
    cp "$DEVICE_LIB" "$TMPDIR_DEVICE/"

    xcodebuild -create-xcframework \
        -library "$TMPDIR_DEVICE/libremo_sdk.a" -headers "$TMPDIR_DEVICE/Headers" \
        -output "$XCFRAMEWORK"
    rm -rf "$TMPDIR_DEVICE"

else
    # Full XCFramework: device + universal simulator (arm64 + x86_64).
    DEVICE_LIB="target/aarch64-apple-ios/$PROFILE/libremo_sdk.a"
    SIM_ARM_LIB="target/aarch64-apple-ios-sim/$PROFILE/libremo_sdk.a"
    SIM_X86_LIB="target/x86_64-apple-ios/$PROFILE/libremo_sdk.a"

    echo "==> Creating universal simulator library..."
    mkdir -p target/sim-universal
    SIM_LIB="target/sim-universal/libremo_sdk.a"
    lipo -create "$SIM_ARM_LIB" "$SIM_X86_LIB" -output "$SIM_LIB"

    TMPDIR_DEVICE=$(mktemp -d)
    TMPDIR_SIM=$(mktemp -d)
    prepare_headers "$TMPDIR_DEVICE"
    prepare_headers "$TMPDIR_SIM"
    cp "$DEVICE_LIB" "$TMPDIR_DEVICE/"
    cp "$SIM_LIB" "$TMPDIR_SIM/"

    xcodebuild -create-xcframework \
        -library "$TMPDIR_DEVICE/libremo_sdk.a" -headers "$TMPDIR_DEVICE/Headers" \
        -library "$TMPDIR_SIM/libremo_sdk.a" -headers "$TMPDIR_SIM/Headers" \
        -output "$XCFRAMEWORK"
    rm -rf "$TMPDIR_DEVICE" "$TMPDIR_SIM"
fi

echo ""
echo "Done. ($MODE)"
echo "  XCFramework: $XCFRAMEWORK"
ls -lh "$XCFRAMEWORK"
