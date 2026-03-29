# CLI Release Distribution Design

## Summary

Remo SDK is already publishable and integrable through the existing XCFramework release flow, but the `remo` CLI is still effectively source-only. This spec defines a macOS-only distribution model that makes the CLI installable without Rust toolchains while keeping the release surface small and maintainable.

The recommended release stack is:

1. GitHub Release with prebuilt macOS binaries
2. First-party Homebrew tap backed by those release artifacts
3. First-party install and uninstall shell scripts

`homebrew-core` remains a future TODO, not part of the initial scope. Mint support is explicitly out of scope.

## Goals

- Make `remo` installable on macOS without `cargo install`
- Keep a single canonical release artifact source
- Support both package-manager and one-command installation flows
- Keep uninstall behavior predictable and low-risk
- Fit naturally into the existing tag-driven release workflow

## Non-Goals

- Linux distribution
- Windows distribution
- Mint support
- Direct submission to `homebrew-core` in the first release phase
- Signing, notarization, or privileged installer packaging in this phase

## Product Decisions

### Supported Platforms

- macOS Apple Silicon (`arm64`)
- macOS Intel (`x86_64`)

The first release phase is macOS-only. This keeps the build matrix, testing burden, and release/debug surface aligned with the current product focus.

### Official Install Paths

Remo CLI should have three official user-facing installation paths:

1. **Homebrew tap**
   - Primary recommended install path
   - Command shape: `brew install yjmeqt/tap/remo`
2. **GitHub Release download**
   - Direct manual install path for users who do not want Homebrew
   - Provides architecture-specific tarballs plus checksums
3. **Install script**
   - One-command convenience path
   - Downloads the correct release artifact and installs the binary into the standard user-visible path

### Official Uninstall Paths

1. **Homebrew uninstall**
   - Command shape: `brew uninstall remo`
2. **Uninstall script**
   - Removes files created by the install script only

The uninstall script must not attempt broad cleanup of unrelated state, caches, or user data. It should only remove files the script itself installed.

## Distribution Architecture

### Canonical Artifact Model

GitHub Releases are the canonical source of truth for CLI distribution.

Each release tag should publish:

- `remo-macos-arm64.tar.gz`
- `remo-macos-x86_64.tar.gz`
- `checksums.txt`

Each archive should contain:

- `remo` binary
- short README or install note
- license file if needed for redistribution consistency

Homebrew and the install script should both consume these release artifacts rather than creating separate packaging flows.

### Homebrew Tap Strategy

The first Homebrew integration should use a first-party tap, not `homebrew-core`.

Reasons:

- It avoids `homebrew-core` acceptance constraints while the release flow is still stabilizing
- It allows using prebuilt release artifacts immediately
- It keeps formula iteration under Remo's control

The tap formula should point to the GitHub Release tarballs and validate checksums per architecture.

### Install Script Strategy

The install script should:

- detect `arm64` vs `x86_64`
- resolve the requested version, defaulting to latest stable release
- download the matching tarball from GitHub Releases
- verify the checksum before installation
- install `remo` into a conventional location such as `/usr/local/bin` or `/opt/homebrew/bin`, with a user-level fallback if needed

The script should prefer transparency over magic. It should print what it will download, where it will install, and how to uninstall.

### Uninstall Script Strategy

The uninstall script should:

- remove only the binary and files created by the install script
- print a clear result message when nothing is installed
- avoid touching Homebrew-managed installations

If a Homebrew installation is detected, the script should instruct the user to use `brew uninstall remo` instead of trying to manage that installation itself.

## Release Workflow Changes

The existing release workflow already builds and publishes SDK artifacts. The CLI design extends that same tag-triggered workflow.

At a high level, a tagged release should:

1. build the macOS CLI binaries for `arm64` and `x86_64`
2. package each binary into a release tarball
3. generate checksums
4. attach the CLI artifacts to the GitHub Release alongside the SDK artifact
5. update the first-party Homebrew tap to point to the new assets and checksums

This keeps a single release event responsible for both SDK and CLI publication.

## Documentation Requirements

The user-facing docs should be updated to present installation in this order:

1. Homebrew tap
2. Install script
3. Manual GitHub Release download
4. Source install via Cargo for contributors and advanced users

The docs should also explain the difference between script-managed installs and Homebrew-managed installs so uninstall instructions stay clear.

## Testing Requirements

Before treating CLI distribution as complete, the release design should be validated with:

- artifact build verification for both macOS architectures
- checksum verification tests
- Homebrew install test from the first-party tap
- install script smoke test on clean macOS environments
- uninstall script smoke test for script-managed installs
- regression check that SDK release behavior remains intact

## Future TODOs

### `homebrew-core`

Leave explicit room for a later migration or parallel submission to `homebrew-core`.

This future work should be reconsidered only after:

- the GitHub Release artifacts are stable
- the tap formula has seen real-world usage
- the project is comfortable with `homebrew-core` review and maintenance expectations

### Mint

Do not support Mint in this design phase.

Mint is not a natural fit for the current Rust CLI distribution model. Supporting it would require a packaging indirection that adds maintenance cost without improving the core macOS installation story.
