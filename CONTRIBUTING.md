# Contributing to Remo

Thanks for your interest in contributing! This guide will help you get started.

## Prerequisites

- **Rust 1.82+** (see `rust-toolchain.toml`)
- **Xcode 26+** (for iOS targets and Apple platform headers)
- **cbindgen** (`cargo install cbindgen`) for generating C/Swift headers

## Setup

```bash
# Install git hooks (runs fmt + clippy before each commit)
git config core.hooksPath .githooks
```

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
cargo clippy --workspace -- -D warnings

# Check formatting
cargo fmt --all --check

# Auto-format
cargo fmt --all
```

## Submitting Changes

1. **Fork** the repository
2. **Create a branch** from `main` (`git checkout -b my-feature`)
3. **Set up git hooks**: `git config core.hooksPath .githooks`
4. **Make your changes** and add tests where appropriate
5. **Commit** — the pre-commit hook will run `cargo fmt --check` and `cargo clippy` automatically
6. **Open a Pull Request** against `main`

## Guidelines

- Keep PRs focused on a single change
- Follow existing code style (run `cargo fmt`)
- Add or update tests for new functionality
- Update documentation if behavior changes

## Questions?

Open an issue if something is unclear or you need help getting started.
