# Tart Development Guide

This is the main contributor guide for working on Remo inside the shared Tart
development VM.

Use this document for:

- first-time setup after cloning Remo
- attaching each new worktree to the shared `remo-dev` VM
- connecting through CLI, Cursor, or VS Code
- cleaning only the current worktree’s generated Tart caches
- checking `status` / `doctor` before debugging a broken workflow

For lower-level script behavior and troubleshooting internals, see
[docs/tart-dev-vm.md](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/docs/tart-dev-vm.md).

For the latest verified runtime evidence and implementation history, see
[docs/tart-dev-vm-handoff.md](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/docs/tart-dev-vm-handoff.md).

For agents working on the Remo repository itself, the matching workflow skill is
[skills/tart-dev-management/SKILL.md](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/skills/tart-dev-management/SKILL.md).

## Why Remo Uses Tart For Contributor Development

Remo uses one shared Tart VM per project.

For this repository:

- project VM: `remo-dev`
- base image: `ghcr.io/cirruslabs/macos-tahoe-xcode:26`
- current working network mode on this host: `bridged:en0`

Multiple worktrees from the same project are mounted into the same VM. The VM
shares Xcode, Rust, Node, and simulator state, while each worktree keeps its
own generated state under `.tart/`.

Tracked Tart configuration for this repository lives in:

- `.tart/project.sh`
- `.tart/packs/*.sh`

Generated per-worktree state lives in directories such as:

- `.tart/DerivedData`
- `.tart/cargo-target`
- `.tart/npm-cache`
- `.tart/tmp`

Tart stores VM disks and OCI image caches outside the repository:

- `~/.tart/vms/`
- `~/.tart/cache/OCIs/`

Remo-specific host state for this workflow lives in:

- `~/.config/remo/tart/`

## First-Time Setup After Clone

Run this once after cloning Remo:

```bash
git clone https://github.com/yjmeqt/Remo.git
cd Remo
make setup
brew install cirruslabs/cli/tart
scripts/tart/bootstrap-dev-vm.sh
```

What `bootstrap-dev-vm.sh` does:

1. checks that `tart` exists on the host
2. creates or reuses the shared `remo-dev` VM
3. mounts the current worktree into the guest
4. provisions the guest using the current `.tart/project.sh` and enabled packs
5. runs the default worktree verification path
6. prints the next-step connect commands

Useful variants:

```bash
scripts/tart/bootstrap-dev-vm.sh --recreate
scripts/tart/bootstrap-dev-vm.sh --no-verify
```

Use `--recreate` only when you intentionally want a fresh VM from the base
image. Use `--no-verify` only when you want to separate VM creation from
worktree verification.

## Create And Attach A New Worktree

Remo uses one shared VM, not one VM per worktree.

For each new worktree:

```bash
git worktree add .worktrees/my-branch -b my-branch
cd .worktrees/my-branch
scripts/tart/use-worktree-dev-vm.sh
```

That attaches the new worktree to the existing `remo-dev` VM and prepares it
for development inside the same shared guest.

If you need a custom guest mount name:

```bash
scripts/tart/use-worktree-dev-vm.sh --mount-name remo-my-branch
```

The helper prints the exact connection commands to use next.

## Connect Through CLI, Cursor, Or VS Code

Use the contributor-facing connection wrapper:

```bash
scripts/tart/connect-dev-vm.sh cli
scripts/tart/connect-dev-vm.sh cursor
scripts/tart/connect-dev-vm.sh vscode
```

Connection modes:

- `cli` opens an interactive shell inside the VM at the selected worktree
- `cursor` opens the mounted worktree through Cursor Remote SSH
- `vscode` opens the mounted worktree through VS Code Remote SSH

Optional target selection:

```bash
scripts/tart/connect-dev-vm.sh cli remo-my-branch
scripts/tart/connect-dev-vm.sh cursor /absolute/path/to/worktree
scripts/tart/connect-dev-vm.sh vscode --new-window
```

The editor connection scripts use the managed SSH alias/proxy path that tunnels
through `tart exec` into guest loopback `sshd`. On this host, that is the
working path; direct bridged guest-IP SSH is not reliable.

## Daily Development Inside The VM

Typical flow after connecting:

```bash
cargo check --workspace
./build-ios.sh sim
scripts/tart/e2e-dev-vm.sh -- --screenshots
```

If you need to build the example app directly:

```bash
cd examples/ios
REMO_LOCAL=1 xcodebuild build -workspace RemoExample.xcworkspace -scheme RemoExample \
  -derivedDataPath "$REMO_TART_DERIVED_DATA/RemoExample" \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The important rule is that builds should use the worktree-local `.tart` paths
exported by the Tart shell helpers rather than default global cache locations.

`scripts/tart/e2e-dev-vm.sh` is the maintained way to reuse the repository’s
existing `scripts/e2e-test.sh` flow inside the VM while keeping artifacts and
DerivedData worktree-local.

## Clean Current Worktree Caches

When you want to clear generated state for only the current worktree:

```bash
scripts/tart/clean-worktree-dev-vm.sh
```

Default cleanup removes:

- `.tart/DerivedData`
- `.tart/npm-cache`
- `.tart/tmp`

To also remove Rust incremental build output:

```bash
scripts/tart/clean-worktree-dev-vm.sh --full
```

This cleanup preserves tracked Tart configuration:

- `.tart/project.sh`
- `.tart/packs/`

Use this for worktree-local reset. Do not use `destroy-dev-vm.sh --force` when
you only need to clear generated state for one worktree.

## Inspect Health With Status And Doctor

Raw status:

```bash
scripts/tart/status-dev-vm.sh
scripts/tart/status-dev-vm.sh remo-my-branch
```

Human-readable health check:

```bash
scripts/tart/doctor-dev-vm.sh
scripts/tart/doctor-dev-vm.sh remo-my-branch
```

Use these before assuming the Tart flow is broken. They surface:

- missing or stopped VM state
- stale mount manifest entries from deleted worktrees
- missing hidden `.git` mount state
- missing managed SSH config
- malformed or missing `.tart/packs` declarations

## Destroy The Whole Project VM Intentionally

Only use this when you intentionally want to reset the entire `remo-dev` VM:

```bash
scripts/tart/destroy-dev-vm.sh --force
```

This is whole-project cleanup. It is not the right command for normal worktree
cache cleanup.
