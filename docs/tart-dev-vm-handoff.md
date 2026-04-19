# Tart Dev VM Handoff

Status snapshot for the Tart-based Remo development VM work as of 2026-04-15.

This document is runtime evidence and implementation history, not the primary
contributor onboarding guide. For the day-to-day workflow, start with
[docs/tart-development-guide.md](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/docs/tart-development-guide.md).

## What Was Implemented

The repository now contains a working Tart workflow for project-scoped macOS VMs:

- [scripts/tart/common.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/common.sh)
- [scripts/tart/bootstrap-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/bootstrap-dev-vm.sh)
- [scripts/tart/create-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/create-dev-vm.sh)
- [scripts/tart/use-worktree-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/use-worktree-dev-vm.sh)
- [scripts/tart/connect-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/connect-dev-vm.sh)
- [scripts/tart/clean-worktree-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/clean-worktree-dev-vm.sh)
- [scripts/tart/provision-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/provision-dev-vm.sh)
- [scripts/tart/ssh-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/ssh-dev-vm.sh)
- [scripts/tart/destroy-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/destroy-dev-vm.sh)
- [scripts/tart/prepare-remote-ssh-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/prepare-remote-ssh-dev-vm.sh)
- [scripts/tart/open-vscode-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/open-vscode-dev-vm.sh)
- [scripts/tart/open-cursor-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/open-cursor-dev-vm.sh)
- [scripts/tart/status-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/status-dev-vm.sh)
- [scripts/tart/doctor-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/doctor-dev-vm.sh)

Project-specific Tart configuration now also lives in:

- [.tart/project.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/project.sh)
- [.tart/packs/ios.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/ios.sh)
- [.tart/packs/rust.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/rust.sh)
- [.tart/packs/node.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/node.sh)
- [.tart/packs/go.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/go.sh)
- [.tart/packs/python.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/python.sh)

Supporting docs and plan/spec files:

- [docs/tart-dev-vm.md](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/docs/tart-dev-vm.md)
- [docs/tart-development-guide.md](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/docs/tart-development-guide.md)

Regression coverage added for the Tart shell layer and the iOS packaging path:

- [tests/tart_vm_scripts.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/tart_vm_scripts.sh)
- [tests/tart_vm_entrypoints.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/tart_vm_entrypoints.sh)
- [tests/build_ios_target_dir.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/build_ios_target_dir.sh)

## What Was Verified

### 1. `macOS 26 / Xcode 26` image works

The base image `ghcr.io/cirruslabs/macos-tahoe-xcode:26` was pulled, cloned, and booted.

Inside the guest:

- `sw_vers` reported `macOS 26.0`
- `xcodebuild -version` reported `Xcode 26.0` / `Build version 17A324`

### 2. `launchd` is required for a stable Tart runtime on this host

Direct shell backgrounding was unreliable:

- `nohup tart run --no-graphics ... &`
- `tart run --no-graphics ... &`

Observed behavior:

- the VM exited or never stayed in `running`
- logs were empty or nearly empty
- one run produced `Trace/BPT trap: 5`

The scripts now use `launchctl submit` to keep the VM alive. That path works reliably.

### 3. Tart shared NAT is broken on this host, but bridged networking works

Under Tart's default shared network mode, both `macOS 26 / Xcode 26` and a comparison
`macOS 15 / Xcode 16` guest showed the same failure pattern:

- guest route and DNS were configured against `192.168.64.1`
- `ping 192.168.64.1` failed
- `ping 1.1.1.1` failed
- `curl https://sh.rustup.rs` timed out

This is a host-side Tart/vmnet problem, not an image-specific issue.

`bridged:en0` is the current working workaround on this machine.

With:

```bash
scripts/tart/create-dev-vm.sh --network bridged:en0 --mount "$PWD:remo-tart-vm"
```

the guest had working outbound TCP/HTTPS, and provisioning completed.

`softnet` was tested but is not the current default because Tart first requests
host-side sudo to set the Softnet executable SUID bit.

### 4. Guest-side Git for mounted worktrees now works

Initial provisioning failed at:

```bash
make setup
```

with:

```text
fatal: not a git repository: /Users/yi.jiang/Developer/Remo/.git/worktrees/tart-vm
```

Root cause:

- mounted worktrees keep their host `.git` file
- that file points at the host's absolute `.git/worktrees/...` path
- the guest initially only mounted the worktree itself, not the shared `.git` path that absolute reference depends on

Implemented fix:

- auto-add a hidden `.git` mount, for example `remo-git-root`
- create a guest-side symlink from the host-style `.git` path to that hidden mount

After that bridge was added, `make setup` completed successfully in the guest.

### 5. Worktree-local target isolation now works with `build-ios.sh`

After `make setup` was fixed, the next failure was:

```text
cp: target/aarch64-apple-ios-sim/debug/libremo_sdk.a: No such file or directory
```

Root cause:

- Tart guest verification exports `CARGO_TARGET_DIR=<worktree>/.tart/cargo-target`
- `build-ios.sh` still assumed the output always lived under `target/...`

Implemented fix:

- `build-ios.sh` now uses `TARGET_DIR="${CARGO_TARGET_DIR:-target}"`
- XCFramework packaging paths now follow the effective Cargo target directory

Regression coverage for this lives in:

- [tests/build_ios_target_dir.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/build_ios_target_dir.sh)

### 6. Full create/provision/verify flow passed for the current worktree

This command completed successfully:

```bash
scripts/tart/create-dev-vm.sh --network bridged:en0 --mount /Users/yi.jiang/Developer/Remo/.worktrees/tart-vm:remo-tart-vm
```

What completed inside the guest:

- `rustup` install / verification
- Rust target installation
- `cargo install cbindgen`
- `npm install -g @openai/codex`
- `make setup`
- `cargo check --workspace`
- `./build-ios.sh sim`

Observed toolchain versions during verification:

- `Xcode 26.0`
- `cargo 1.94.1`
- `npm 10.8.2`
- `codex-cli 0.120.0`
- `cbindgen 0.29.2`

### 7. `RemoExample` built, installed, launched, and was captured on the guest simulator

The example app was verified inside the Tart guest on:

- simulator: `iPhone 17`
- simulator id: `83C98ACA-2EE4-49CE-9B93-FF2CD032CF4E`
- runtime: `iOS 26.0`

Verified flow:

1. `./build-ios.sh sim`
2. `REMO_LOCAL=1 xcodebuild build -workspace RemoExample.xcworkspace -scheme RemoExample -derivedDataPath <worktree>/.tart/DerivedData/RemoExample -destination "platform=iOS Simulator,id=<sim-id>"`
3. `xcrun simctl install <sim-id> <derived-data>/Build/Products/Debug-iphonesimulator/RemoExample.app`
4. `xcrun simctl launch <sim-id> com.remo.example`
5. `xcrun simctl io <sim-id> screenshot <worktree>/.tart/tmp/remo-example-sim.png`

Observed evidence:

- `simctl launch` returned PID `2379`
- `simctl get_app_container` returned a valid installed app bundle path
- screenshot written to [remo-example-sim.png](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/tmp/remo-example-sim.png)

During the first example build attempt, Xcode reported that the local binary target
did not contain a binary artifact. After explicitly regenerating
`swift/RemoSDK.xcframework` with `./build-ios.sh sim`, the local package resolved
correctly and the example build succeeded. This has not yet been reduced to a
separate reproducible root cause beyond that successful regeneration path.

### 7a. The existing repository e2e script now runs inside the VM through a thin Tart wrapper

Implemented:

- [scripts/tart/e2e-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/e2e-dev-vm.sh)

This wrapper does not introduce a second test flow. It reuses the repository's
existing [scripts/e2e-test.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/e2e-test.sh)
inside the guest and only adapts the environment around it:

- worktree-local `.tart/tmp/remo-e2e` artifacts
- worktree-local DerivedData for `RemoExample`
- guest-local Cargo target under `/tmp/remo-tart-e2e/<mount>/cargo-target`
- guest-local `REMO_BIN` path that matches that Cargo target

The guest-local Cargo target is deliberate. Full `cargo build` for the CLI was
not reliable on Tart's shared mount, producing zero-length `.rlib` archives for
the e2e build. Moving the e2e Cargo target to guest-local storage fixed that
without changing the repository's normal development target isolation.

Verified evidence on 2026-04-15:

- `SKIP_BUILD=1 DEVICE_UUID=F96B906F-904A-485D-B246-8500D193C80B scripts/tart/e2e-dev-vm.sh /Users/yi.jiang/Developer/Remo/.worktrees/tart-vm -- --screenshots`
- `14` tests passed
- port discovery succeeded via `lsof`
- screenshots written to [remo-e2e](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/tmp/remo-e2e)

### 8. VS Code and Cursor Remote SSH now work through a managed Tart SSH alias

Direct host to guest SSH over the bridged guest IP does not work reliably on
this machine.

Observed root cause evidence:

- direct `ssh admin@<guest-ip>` reset before completing the SSH banner exchange
- a temporary guest HTTP server on port `2223` also reset after `connect()`
- the same SSH daemon worked correctly when reached from inside the guest at `127.0.0.1`

So the issue is not guest `sshd` itself. It is the host to guest bridged data
path.

Implemented workaround:

- create a stable SSH alias such as `tart-remo-dev`
- install a per-VM SSH key under `~/.config/remo/tart/ssh/`
- authorize that key inside the guest
- write a managed SSH snippet to `~/.config/remo/tart/ssh_config`
- ensure `~/.ssh/config` includes that snippet near the top of the file
- proxy SSH through `tart exec -i remo-dev /usr/bin/nc 127.0.0.1 22`

Verified evidence:

- `ssh -G tart-remo-dev` showed the expected `proxycommand`, `identityfile`, `user`, and `hostname`
- `ssh -vvv -o ConnectTimeout=8 tart-remo-dev 'printf ok'` authenticated with the managed key and returned `ok`

This is the path now used by:

- [scripts/tart/prepare-remote-ssh-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/prepare-remote-ssh-dev-vm.sh)
- [scripts/tart/open-vscode-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/open-vscode-dev-vm.sh)
- [scripts/tart/open-cursor-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/open-cursor-dev-vm.sh)

### 9. `codex` is installed in the guest, but ChatGPT Enterprise sign-in inside the VM is blocked

What is verified:

- `codex-cli 0.120.0` is installed in the guest
- the helper wrapper [scripts/tart/codex-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/codex-dev-vm.sh) can launch guest Codex in a PTY

Current blocker:

- ChatGPT Enterprise / company-account sign-in inside the Tart VM is currently treated as blocked for this workflow
- `Claude` login working in the same VM suggests the issue is specific to Codex enterprise sign-in rather than a general Tart VM auth failure
- do not continue debugging guest `codex login` unless the user explicitly asks to reopen that line of work

### 10. The shell layer received a hardening pass for reuse and cleanup

The latest shell-layer hardening work focused on removing stale paths and making
shared helpers safe to reuse from future scripts.

Implemented changes:

- mount-spec parsing moved into shared helpers in `common.sh`
- mount validation now fails early for missing host directories and invalid explicit guest mount names
- target resolution for `host-path|mount-name` is centralized instead of duplicated in entrypoint scripts
- `remo_tart_ssh` now uses the same managed alias/proxy path as the editor launchers
- `destroy-dev-vm.sh` now cleans up the managed SSH key and alias state for that VM
- managed file updates now go through reusable block/line helpers, including cleanup of legacy bare `Include` lines

Verified evidence:

- `source scripts/tart/common.sh && remo_tart_ssh remo-dev "printf ok"` returned `ok`
- `bash tests/tart_vm_scripts.sh` covers managed block replacement, include cleanup, SSH local-state cleanup, and mount-spec validation

### 11. Guest provisioning is now more defensive against transient install failures

The provisioning entrypoint was hardened further:

- it is now safe to source in tests because it no longer auto-runs its CLI path when sourced
- transient network/package-manager installs now use a shared retry helper
- retry defaults are controlled by `REMO_TART_RETRY_ATTEMPTS=3` and `REMO_TART_RETRY_DELAY_SECONDS=2`
- scripts that source `common.sh` now resolve their own directory via `BASH_SOURCE[0]` instead of `$0`

This currently covers retries for:

- Rustup installation
- Rust target installation
- `cargo install cbindgen`
- `brew install node`
- `npm install -g @openai/codex`

Verified evidence:

- [tests/tart_vm_provision.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/tart_vm_provision.sh) verifies retry success and retry exhaustion behavior
- `tart exec ... provision-dev-vm.sh verify-toolchain ...` still runs normally inside the guest after the source-safe refactor

### 12. A small status entrypoint now exposes runtime state without opening the VM

Implemented:

- [scripts/tart/status-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/status-dev-vm.sh)

It reports machine-friendly `key=value` status including:

- VM existence and state
- enabled Tart pack set from `.tart/project.sh`
- launchd job presence
- managed SSH alias/config/key presence
- mount manifest count and entries
- selected mount resolution into guest path

Verified evidence:

- [tests/tart_vm_status.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/tart_vm_status.sh) covers running and missing-VM cases with stubbed `tart` and `launchctl`
- a real run of `scripts/tart/status-dev-vm.sh --name remo-dev /Users/yi.jiang/Developer/Remo/.worktrees/tart-vm` completed successfully against the current host state

### 13. A small doctor entrypoint now converts raw state into actionable findings

Implemented:

- [scripts/tart/doctor-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/doctor-dev-vm.sh)

It checks:

- whether `.tart/project.sh` exists
- whether the VM exists
- whether a stale `launchd` job remains for a missing VM
- whether the mount manifest exists and still points at real host paths
- whether the selected mount is recorded
- whether the hidden `.git` mount is still present
- whether each declared Tart pack name is valid and its `.tart/packs/<name>.sh` file exists

It exits non-zero only for blocking issues. A stopped VM or a missing managed SSH setup remains a warning.

### 14. The Tart shell layer is now reusable through a project manifest plus language packs

Implemented:

- [.tart/project.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/project.sh)
- [.tart/packs/ios.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/ios.sh)
- [.tart/packs/rust.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/rust.sh)
- [.tart/packs/node.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/node.sh)
- [.tart/packs/go.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/go.sh)
- [.tart/packs/python.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/.tart/packs/python.sh)

The shared entrypoints now read project-specific defaults from `.tart/project.sh`:

- VM name
- base image
- network mode
- CPU / memory
- enabled pack set
- project-level provision hook
- project-level worktree verification hook

For Remo, the current manifest enables:

- `ios`
- `rust`
- `node`

That means the same shared shell layer can now be reused by another project by
changing only the local `.tart/project.sh` and the enabled pack list.

Verified evidence:

- [tests/tart_vm_scripts.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/tart_vm_scripts.sh) covers manifest defaults, pack parsing, and project-config path override behavior
- [tests/tart_vm_provision.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/tart_vm_provision.sh) covers pack-driven provisioning order and worktree env exports
- a fresh real run of `scripts/tart/status-dev-vm.sh --name remo-dev /Users/yi.jiang/Developer/Remo/.worktrees/tart-vm` reported `packs=ios,rust,node`

### 15. The create path now self-heals stale host-side state before boot

Implemented in shared helpers and wired into
[scripts/tart/create-dev-vm.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/scripts/tart/create-dev-vm.sh):

- stale mount-manifest entries are pruned if their host path no longer exists
- a stale `launchd` job is removed when the VM itself is already missing

Regression coverage for the helpers lives in:

- [tests/tart_vm_scripts.sh](/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm/tests/tart_vm_scripts.sh)

### 16. The hidden compatibility mount now exposes only `.git`, not the whole project root

The original bridge mounted the entire project root into the guest so the worktree's
absolute `.git/worktrees/...` path would resolve.

That was broader than necessary. The current implementation now:

- mounts only `/Users/yi.jiang/Developer/Remo/.git`
- bridges only the host-style `.git` path inside the guest
- removes the legacy `remo-host-root` manifest entry on the next create/update run

### 17. A second Remo worktree was mounted into the same VM and resolved correctly in the guest

A detached sibling worktree was created at:

- `/Users/yi.jiang/Developer/Remo/.worktrees/tart-vm-smoke`

Then the shared VM was recreated with both project worktrees mounted.

Verified evidence:

- `status-dev-vm.sh --name remo-dev /Users/yi.jiang/Developer/Remo/.worktrees/tart-vm-smoke` reported:
  - `mount_count=3`
  - `selected_mount=remo-tart-vm-smoke`
  - `selected_guest_root=/Volumes/My Shared Files/remo-tart-vm-smoke`
- inside the guest:
  - `pwd` in the new mount returned `/Volumes/My Shared Files/remo-tart-vm-smoke`
  - `git rev-parse --show-toplevel` returned `/Volumes/My Shared Files/remo-tart-vm-smoke`
  - `git rev-parse --git-common-dir` returned `/Volumes/My Shared Files/remo-git-root`

This is the verified “one project VM, many mounted worktrees” path for Remo.

## Current Runtime State

At the time of this handoff:

- `remo-dev` exists and is currently `stopped`
- `launchd` still has a loaded `com.remo.tart.remo-dev` job for that VM
- `status-dev-vm.sh` reports `packs=ios,rust,node`
- `doctor-dev-vm.sh` reports `status=ok`, `issues=0`, `warnings=1`
- base image OCI caches for `macos-tahoe-xcode:26` and earlier test images remain on the host

## Verified Local Checks

These repository-side checks were run after the latest changes:

- `bash tests/tart_vm_scripts.sh`
- `bash tests/tart_vm_entrypoints.sh`
- `bash tests/tart_vm_provision.sh`
- `bash tests/tart_vm_status.sh`
- `bash tests/tart_vm_doctor.sh`
- `bash tests/build_ios_target_dir.sh`
- `bash -n build-ios.sh scripts/tart/common.sh scripts/tart/create-dev-vm.sh scripts/tart/provision-dev-vm.sh scripts/tart/ssh-dev-vm.sh scripts/tart/destroy-dev-vm.sh scripts/tart/prepare-remote-ssh-dev-vm.sh scripts/tart/open-editor-dev-vm.sh scripts/tart/open-vscode-dev-vm.sh scripts/tart/open-cursor-dev-vm.sh scripts/tart/codex-dev-vm.sh scripts/tart/status-dev-vm.sh scripts/tart/doctor-dev-vm.sh tests/build_ios_target_dir.sh tests/tart_vm_provision.sh tests/tart_vm_status.sh tests/tart_vm_doctor.sh`

## What Remains

The Tart development VM path is now working for provisioning, project verification,
manual example-app simulator validation, and editor Remote SSH access through the
managed alias.

Remaining follow-up items are improvements, not blockers:

1. Automate simulator validation.
   The manual validation path now works.
   The remaining gap is script automation for build, install, launch, and screenshot.

2. Improve network-mode ergonomics.
   On this host, `--network bridged:en0` is required for real work.
   The scripts currently support `--network`, but they do not auto-detect or persist the best mode per host.

3. Decide whether `bridged:en0` should become the local default or remain explicit.
   Leaving it explicit is safer for portability.
   Making it the default is more convenient on this machine.

4. Consider persisting more guest convenience state.
   `codex` is installed, but enterprise sign-in inside the VM is currently blocked for this workflow.
   If a guest-local API-key path is later desired, document that separately from ChatGPT workspace login.

## Practical Recommendation

For this machine, treat the Tart VM path as usable now.

Use:

```bash
scripts/tart/create-dev-vm.sh --network bridged:en0 --mount "$PWD:$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
```

or, for this worktree specifically:

```bash
scripts/tart/create-dev-vm.sh --network bridged:en0 --mount "$PWD:remo-tart-vm"
```

If more validation is needed, the next highest-value task is turning the working
manual simulator sequence into a first-class Tart verification command.
