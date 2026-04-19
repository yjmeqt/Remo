# Tart Dev VM

Remo can be developed inside a shared Tart macOS VM per project.

This document is the lower-level implementation and troubleshooting reference.
For the contributor-facing day-to-day workflow, start with
[docs/tart-development-guide.md](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/docs/tart-development-guide.md).

The model is:

- one VM per project, for example `remo-dev`
- many worktrees from that project mounted into the same VM
- one isolated `.tart/` directory per worktree for build outputs and caches

For Remo worktrees, the guest paths look like:

- `/Volumes/My Shared Files/remo`
- `/Volumes/My Shared Files/remo-tart-vm`
- `/Volumes/My Shared Files/remo-feature-x`

Project-specific dependency policy now lives under:

- `.tart/project.sh`
- `.tart/packs/*.sh`

## Host Prerequisites

- Apple Silicon Mac running macOS 13 or newer
- [Tart](https://tart.run/quick-start/) installed on the host
- enough free disk for a macOS + Xcode VM image
- outbound network access for guest-side Cargo, npm, and SwiftPM resolution

Install Tart on the host:

```bash
brew install cirruslabs/cli/tart
```

The scripts use `tart exec`, so `sshpass` is not required.

## Storage Layout

Tart keeps VM assets on the host outside the repository:

- VMs: `~/.tart/vms/`
- OCI cache: `~/.tart/cache/OCIs/`

Remo keeps a small amount of project-specific Tart state on the host:

- mount manifest: `~/.config/remo/tart/<vm-name>.mounts`
- Tart run log: `~/.config/remo/tart/<vm-name>.log`
- managed SSH config snippet: `~/.config/remo/tart/ssh_config`
- per-VM SSH keys: `~/.config/remo/tart/ssh/<vm-name>_ed25519(.pub)`

The source code itself stays in your existing worktrees and is mounted into the guest at runtime.

## Create Or Reuse The Project VM

From a Remo worktree:

```bash
scripts/tart/create-dev-vm.sh --network bridged:en0 --mount "$PWD:remo-tart-vm"
```

To rebuild the VM from the base image:

```bash
scripts/tart/create-dev-vm.sh --recreate --network bridged:en0 --mount "$PWD:remo-tart-vm"
```

Default behavior:

- default VM name: `remo-dev`
- default base image: `ghcr.io/cirruslabs/macos-tahoe-xcode:26`
- default CPU / memory profile: 6 CPU, 12 GB RAM

This default targets:

- `macOS 26` (`tahoe`)
- `Xcode 26`

On this host, Tart's default shared NAT networking is not usable: the guest gets a
route and DNS server at `192.168.64.1`, but cannot reach the gateway or the public
internet. Use `--network bridged:en0` for real provisioning and verification.

`softnet` is not the default because Tart currently prompts for host-side sudo to
set the Softnet SUID bit before it can be used.

What the script does:

1. creates the project VM if it does not exist
2. records the requested mount in the host-side manifest
3. boots the VM with all known project mounts
4. runs guest provisioning from the mounted repo
5. runs toolchain verification
6. runs worktree verification for the primary mounted worktree

Mount parsing is now handled in shared helpers.
This means the same validation rules apply consistently everywhere:

- host mount paths must already exist and be directories
- explicit guest mount names must match `[A-Za-z0-9][A-Za-z0-9._-]*`
- omitted guest mount names are derived automatically from the host path

The create path now also self-heals two stale host-side states before boot:

- manifest entries whose host path has been deleted
- stale `launchd` jobs for VMs that no longer exist

The shared create path now reads project defaults from `.tart/project.sh` rather
than hardcoding them directly in the shell entrypoint.

Guest provisioning now retries transient install failures for Rustup, Rust target
downloads, `cargo install cbindgen`, `brew install node`, and `npm install -g @openai/codex`.

The VM is launched under `launchd`, not as a shell background job. This is intentional: on this host, `tart run --no-graphics` survives under `launchd` but exits when backgrounded directly from a shell.

## Important Behavior: Mount Changes Restart The VM

Tart directory shares are attached when the VM is started.

That means:

- if you add a new worktree mount to an already-running project VM, the script restarts that VM so the new mount appears
- if you reuse the same set of mounts, the script can keep using the existing VM

This is why the project keeps a host-side mount manifest.

## Important Behavior: Git Worktrees Need A Hidden `.git` Bridge

Mounted worktrees keep their host-side `.git` file, and that file points at the
host's absolute `.git/worktrees/...` path.

To make guest-side Git commands work, the create script automatically:

- adds a hidden mount for the shared `.git` directory, for example `/Volumes/My Shared Files/remo-git-root`
- creates a guest-side symlink that maps the host-style `.git` path to that hidden mount

Without this bridge, `make setup` fails with `fatal: not a git repository` inside
the guest.

## Worktree Isolation

Each mounted worktree owns its own `.tart/` directory:

- `.tart/DerivedData`
- `.tart/cargo-target`
- `.tart/npm-cache`
- `.tart/tmp`

The scripts export these worktree-local paths when entering the guest:

```bash
export REMO_TART_WORKTREE_ROOT=<worktree>
export REMO_TART_DERIVED_DATA=<worktree>/.tart/DerivedData
export CARGO_TARGET_DIR=<worktree>/.tart/cargo-target
export npm_config_cache=<worktree>/.tart/npm-cache
export TMPDIR=<worktree>/.tart/tmp
```

`build-ios.sh` respects `CARGO_TARGET_DIR`, so XCFramework packaging follows the
same isolated per-worktree target directory instead of assuming `target/`.

Shared across all worktrees in the same project VM:

- Xcode installation
- simulator devices and runtime state
- guest user login state
- globally installed tools such as `codex`

## Status And Doctor Entry Points

Machine-friendly runtime status:

```bash
scripts/tart/status-dev-vm.sh
```

This prints `key=value` output for:

- VM existence and current state
- enabled pack set
- `launchd` job presence
- managed SSH config and key presence
- mount manifest count
- selected mount resolution into its guest path

Human-friendly health checks:

```bash
scripts/tart/doctor-dev-vm.sh
```

This intentionally checks only a small, stable set of failure modes:

- missing `.tart/project.sh`
- missing VM
- stale `launchd` job for a missing VM
- missing or empty mount manifest
- missing selected mount
- stale host mount paths
- missing hidden `.git` mount
- invalid or missing Tart pack files declared by the project manifest

The create path already auto-prunes stale manifest paths and stale missing-VM
`launchd` jobs. `doctor-dev-vm.sh` is for the failures that still require attention.

Warnings such as a stopped VM or missing managed SSH setup do not fail the script.
Blocking issues exit non-zero.

## Guest Provisioning

The guest provisioning script is now pack-driven.

For Remo, `.tart/project.sh` enables:

- `ios`
- `rust`
- `node`

That pack set currently provides:

- Xcode verification
- `rustup`
- Rust targets from [`rust-toolchain.toml`](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/rust-toolchain.toml)
- `cbindgen`
- `node` / `npm`
- `@openai/codex`

After pack-level ensures run, the project manifest's provision hook runs:

```bash
make setup
```

## Codex In The Guest

The scripts only install the CLI:

```bash
npm install -g @openai/codex
```

Convenience wrapper for starting Codex in the current mounted worktree:

```bash
scripts/tart/codex-dev-vm.sh
```

To trigger guest-local login:

```bash
scripts/tart/codex-dev-vm.sh --login
```

Authentication is guest-local.

Current blocker for this repository workflow:

- ChatGPT Enterprise / company-account login inside the VM is currently treated as blocked.
- `codex` remains installed in the guest, but enterprise sign-in is not considered part of the supported Tart workflow.
- `Claude` login working in the same VM suggests the failure is specific to Codex enterprise login rather than a general VM auth limitation.
- Do not spend more time investigating guest `codex login` unless explicitly requested.

Use one of:

```bash
codex login
```

or:

```bash
export OPENAI_API_KEY=...
```

The host's OpenAI credentials are not copied into the VM automatically.

Provisioning retry knobs:

- `REMO_TART_RETRY_ATTEMPTS` defaults to `3`
- `REMO_TART_RETRY_DELAY_SECONDS` defaults to `2`

## Public, Private, And Host-Local Dependencies

Public network fetches should work normally from inside the guest:

- Cargo crates
- npm packages
- SwiftPM packages hosted on public Git providers

Private package sources also work, but credentials must be configured inside the guest:

- guest-local SSH keys
- HTTPS access tokens
- npm auth tokens

Host-local registries or services are the fragile case. If a dependency source lives on the host rather than on the public internet:

- the service must listen on `0.0.0.0`
- the guest must reach the host over Tart's NAT-visible address
- on macOS 15+, host-side Local Network permission prompts may matter

## Enter The VM At A Worktree

If you are already in a worktree directory:

```bash
scripts/tart/ssh-dev-vm.sh
```

Or target a specific mount name:

```bash
scripts/tart/ssh-dev-vm.sh remo-tart-vm
```

This opens an interactive shell in the guest at:

```bash
/Volumes/My Shared Files/remo-tart-vm
```

with the worktree-local environment variables exported.

## Inspect VM Status

Use:

```bash
scripts/tart/status-dev-vm.sh
```

or:

```bash
scripts/tart/status-dev-vm.sh remo-tart-vm
```

This prints machine-friendly `key=value` lines that summarize:

- VM state: `missing`, `stopped`, or `running`
- whether the launchd job is still present
- whether the managed SSH config and per-VM key exist
- how many mounts are recorded in the manifest
- whether the selected mount is present in that manifest

This is intended as the first diagnostic step before using `open-*`, `ssh-dev-vm.sh`, or a recreate flow.

## Open The Mounted Worktree In VS Code Or Cursor

Because direct host to guest SSH over the bridged guest IP resets on this
machine, the editor launchers do not connect to the guest IP directly.
Instead they:

- prepare a managed SSH alias such as `tart-remo-dev`
- install a per-VM SSH key on the host and authorize it inside the guest
- write a managed SSH snippet at `~/.config/remo/tart/ssh_config`
- ensure `~/.ssh/config` includes that snippet near the top of the file
- proxy the SSH session through `tart exec -i <vm-name> /usr/bin/nc 127.0.0.1 22`

Prepare the alias without opening an editor:

```bash
scripts/tart/prepare-remote-ssh-dev-vm.sh
```

VS Code:

```bash
scripts/tart/open-vscode-dev-vm.sh
```

Cursor:

```bash
scripts/tart/open-cursor-dev-vm.sh
```

These launchers:

- use the editor's Remote SSH entrypoint with the managed Tart alias
- open the mounted guest worktree path
- maintain a small managed include block in `~/.ssh/config`

The shared `remo_tart_ssh` helper now uses this same managed alias path, so
internal script reuse no longer risks falling back to the broken bridged-IP SSH route.

Dry-run:

```bash
scripts/tart/open-vscode-dev-vm.sh --print-only
scripts/tart/open-cursor-dev-vm.sh --print-only
```

## Destroy The Project VM

Deletion is explicit:

```bash
scripts/tart/destroy-dev-vm.sh --force
```

This stops and deletes the Tart VM and removes its host-side mount manifest and run log.
It also removes the corresponding `launchd` job that keeps the VM alive and
cleans up the managed SSH alias/key state for that VM.

## Verification Commands

Toolchain verification:

```bash
scripts/tart/provision-dev-vm.sh verify-toolchain /Volumes/My Shared Files/remo-tart-vm
```

Worktree verification:

```bash
scripts/tart/provision-dev-vm.sh verify-worktree /Volumes/My Shared Files/remo-tart-vm
```

That worktree verification currently runs:

```bash
cargo check --workspace
./build-ios.sh sim
```

## Run The Existing E2E Script Inside The VM

Preferred entrypoint:

```bash
scripts/tart/e2e-dev-vm.sh -- --screenshots
```

This wrapper intentionally reuses the repository's existing
[scripts/e2e-test.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/e2e-test.sh)
instead of introducing a second example-app test flow.

Tart-specific behavior in the wrapper:

- `ARTIFACTS_DIR` points at `<worktree>/.tart/tmp/remo-e2e`
- `DERIVED_DATA_PATH` points at `<worktree>/.tart/DerivedData/RemoExample`
- `REMO_BIN` points at the guest-local e2e cargo target
- `CARGO_TARGET_DIR` points at a guest-local `/tmp/remo-tart-e2e/<mount>/cargo-target`

The guest-local Cargo target is deliberate: full `cargo build` for the e2e CLI
was not reliable on Tart's shared mount, while artifacts and screenshots still
need to land back in the mounted worktree.

Verified in this worktree on 2026-04-15 with:

- `14` passing e2e assertions
- simulator: `iPhone 16e`
- screenshot output: [remo-e2e](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/tmp/remo-e2e)

The older manual `xcodebuild + simctl` sequence still works for ad hoc checks,
but the wrapper above is the maintained path.

## Troubleshooting

If Tart fails to start VMs on a host running macOS 15 or newer:

- confirm the host has an unlocked `login.keychain`
- check whether the host needs to grant Local Network access to Tart

If guest provisioning fails:

- inspect `~/.config/remo/tart/<vm-name>.log`
- rerun `scripts/tart/create-dev-vm.sh --no-verify ...` to separate boot/provision from project verification

If a private SwiftPM dependency fails:

- verify the same credentials exist inside the guest
- try `xcodebuild -resolvePackageDependencies -derivedDataPath <worktree>/.tart/DerivedData`
