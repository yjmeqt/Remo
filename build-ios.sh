#!/usr/bin/env bash
set -euo pipefail

# Build remo-sdk for iOS targets and package into an XCFramework.
# Requires: rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PROFILE="${1:-release}"
FLAGS=""
if [ "$PROFILE" = "release" ]; then
    FLAGS="--release"
fi

echo "==> Building remo-sdk for aarch64-apple-ios ($PROFILE)..."
cargo build -p remo-sdk --features ios --target aarch64-apple-ios $FLAGS

echo "==> Building remo-sdk for aarch64-apple-ios-sim ($PROFILE)..."
cargo build -p remo-sdk --features ios --target aarch64-apple-ios-sim $FLAGS

echo "==> Building remo-sdk for x86_64-apple-ios ($PROFILE)..."
cargo build -p remo-sdk --features ios --target x86_64-apple-ios $FLAGS

DEVICE_LIB="target/aarch64-apple-ios/$PROFILE/libremo_sdk.a"
SIM_ARM_LIB="target/aarch64-apple-ios-sim/$PROFILE/libremo_sdk.a"
SIM_X86_LIB="target/x86_64-apple-ios/$PROFILE/libremo_sdk.a"

echo "==> Creating universal simulator library..."
mkdir -p target/sim-universal
SIM_LIB="target/sim-universal/libremo_sdk.a"
lipo -create "$SIM_ARM_LIB" "$SIM_X86_LIB" -output "$SIM_LIB"

HEADER="swift/RemoSwift/Sources/RemoSwift/include/remo.h"
XCFRAMEWORK="swift/RemoSDK.xcframework"

# Generate C header via cbindgen (if installed)
if command -v cbindgen &> /dev/null; then
    echo "==> Generating C header..."
    cbindgen --crate remo-sdk --output "$HEADER" --lang c
    echo "  Header written to $HEADER"
else
    echo "  [skip] cbindgen not found, using existing header"
fi

# Create XCFramework
echo "==> Creating XCFramework..."
rm -rf "$XCFRAMEWORK"

# Prepare temporary directories with headers + modulemap
TMPDIR_DEVICE=$(mktemp -d)
TMPDIR_SIM=$(mktemp -d)

for DIR in "$TMPDIR_DEVICE" "$TMPDIR_SIM"; do
    mkdir -p "$DIR/Headers"
    cp "$HEADER" "$DIR/Headers/"
    cat > "$DIR/Headers/module.modulemap" <<'MODULEMAP'
module CRemo {
    header "remo.h"
    export *
}
MODULEMAP
done

cp "$DEVICE_LIB" "$TMPDIR_DEVICE/"
cp "$SIM_LIB" "$TMPDIR_SIM/"

xcodebuild -create-xcframework \
    -library "$TMPDIR_DEVICE/libremo_sdk.a" -headers "$TMPDIR_DEVICE/Headers" \
    -library "$TMPDIR_SIM/libremo_sdk.a" -headers "$TMPDIR_SIM/Headers" \
    -output "$XCFRAMEWORK"

rm -rf "$TMPDIR_DEVICE" "$TMPDIR_SIM"

echo ""
echo "Done."
echo "  XCFramework: $XCFRAMEWORK"
ls -lh "$XCFRAMEWORK"
