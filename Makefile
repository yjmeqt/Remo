.PHONY: setup build check test cli ios ios-sim ios-device clean fmt lint e2e

# First-time setup (run once after clone or worktree creation)
setup:
	git config core.hooksPath .githooks
	@echo "Git hooks configured."

# Build everything (macOS)
build:
	cargo build --workspace

# Type-check only
check:
	cargo check --workspace

# Run tests
test:
	cargo test --workspace

# Build macOS CLI
cli:
	cargo build -p remo-cli --release
	@echo "Binary: target/release/remo"

# Build iOS XCFramework — pick the fastest option for your workflow:
#   make ios-sim     arm64 simulator only (~16s, local dev)
#   make ios-device  arm64 device only    (~16s, real device)
#   make ios         all targets, release (~50s, CI / distribution)
ios:
	./build-ios.sh release

ios-sim:
	./build-ios.sh sim

ios-device:
	./build-ios.sh device

# E2E test — build everything, launch on simulator, exercise all capabilities
e2e:
	./scripts/e2e-test.sh

# Format
fmt:
	cargo fmt --all

# Lint
lint:
	cargo clippy --workspace -- -D warnings

# Clean
clean:
	cargo clean
