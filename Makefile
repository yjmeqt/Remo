.PHONY: setup build check test cli ios clean fmt lint

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

# Build iOS static library (device + simulator)
ios:
	./build-ios.sh release

ios-debug:
	./build-ios.sh debug

# Format
fmt:
	cargo fmt --all

# Lint
lint:
	cargo clippy --workspace -- -D warnings

# Clean
clean:
	cargo clean
