# Contributing to Remo

Thanks for your interest in contributing! This guide will help you get started.

## Prerequisites

- **Rust 1.82+** (see `rust-toolchain.toml`)
- **Xcode 26+** (for iOS targets and Apple platform headers)
- **cbindgen** (`cargo install cbindgen`) for generating C/Swift headers

## Building

```bash
# Build the workspace
cargo build

# Build the iOS framework (requires macOS with Xcode)
./build-ios.sh
```

## Testing

```bash
cargo test
```

Tests that require a connected device or usbmuxd socket are ignored by default.
Run them explicitly with `cargo test -- --ignored` when a device is available.

## Linting

```bash
# Check for common mistakes
cargo clippy -- -D warnings

# Check formatting
cargo fmt --check

# Auto-format
cargo fmt
```

## Submitting Changes

1. **Fork** the repository
2. **Create a branch** from `main` (`git checkout -b my-feature`)
3. **Make your changes** and add tests where appropriate
4. **Run checks** locally: `cargo fmt --check && cargo clippy -- -D warnings && cargo test`
5. **Commit** with a clear message describing the change
6. **Open a Pull Request** against `main`

## Guidelines

- Keep PRs focused on a single change
- Follow existing code style (run `cargo fmt`)
- Add or update tests for new functionality
- Update documentation if behavior changes

## Questions?

Open an issue if something is unclear or you need help getting started.
