# Tart Dev VM Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repeatable Tart VM tooling for Remo so one project-level macOS VM can host multiple mounted worktrees with per-worktree build/cache isolation, then validate it against the current `tart-vm` worktree.

**Architecture:** Keep Tart lifecycle logic on the host in small shell entrypoints under `scripts/tart/`, and keep guest configuration in a dedicated provisioning script that runs from the mounted repo. Centralize path naming, worktree-local environment variables, and SSH execution helpers in a shared shell library so creation, SSH entry, and verification all use the same rules. Document both the happy path and the likely networking/authentication caveats for SwiftPM, Codex, and simulator workflows.

**Tech Stack:** Bash, Tart CLI, macOS `ssh`/`sshpass`, Xcode/xcodebuild, rustup/cargo, npm, Codex CLI

---

## File Structure

- Create: `scripts/tart/common.sh`
  - Shared shell helpers for VM naming, mount naming, guest paths, SSH command construction, worktree-local env exports, and preflight checks.
- Create: `scripts/tart/create-dev-vm.sh`
  - Main entrypoint to create or reuse a project VM, boot it with one or more mounted worktrees, run guest provisioning, and optionally run verification.
- Create: `scripts/tart/provision-dev-vm.sh`
  - Guest-side provisioning and verification helpers: install/verify rustup, Rust targets, cbindgen, node/npm, Codex CLI, and worktree-local `.tart/` directories.
- Create: `scripts/tart/ssh-dev-vm.sh`
  - Convenience entrypoint to open a shell in the guest at a selected mounted worktree with the correct local env exported.
- Create: `scripts/tart/destroy-dev-vm.sh`
  - Explicit cleanup for stopping and deleting the project VM.
- Create: `docs/tart-dev-vm.md`
  - User-facing guide for prerequisites, creation flow, multi-worktree usage, Codex login, SwiftPM behavior, simulator install/screenshot workflow, and troubleshooting.
- Modify: `README.md`
  - Add a short contributor-facing link to the Tart VM guide in the development section.
- Modify: `docs/superpowers/specs/2026-04-12-tart-dev-vm-design.md`
  - Keep the accepted design in sync if small implementation-specific clarifications are needed during execution.

## Chunk 1: Shell Foundation

### Task 1: Add shared Tart shell helpers

**Files:**
- Create: `scripts/tart/common.sh`

- [ ] **Step 1: Define the core helper surface before writing callers**

Document in the file header which functions are exported for callers:

- `remo_tart_repo_root`
- `remo_tart_default_vm_name`
- `remo_tart_mount_name_for_path`
- `remo_tart_guest_mount_path`
- `remo_tart_worktree_env_exports`
- `remo_tart_require_cmd`
- `remo_tart_vm_ip`
- `remo_tart_ssh`
- `remo_tart_ssh_script`

- [ ] **Step 2: Implement minimal path and naming helpers**

Implement Bash helpers that:

- resolve repo root from the current script location
- derive a stable project VM name such as `remo-dev`
- derive a stable mount name from a worktree path
- map mount names to `/Volumes/My Shared Files/<mount-name>`

- [ ] **Step 3: Implement worktree-local environment export helpers**

Generate shell-safe exports for:

- `REMO_TART_WORKTREE_ROOT`
- `CARGO_TARGET_DIR`
- `npm_config_cache`
- `TMPDIR`
- `REMO_TART_DERIVED_DATA`

using `<worktree>/.tart/...` paths.

- [ ] **Step 4: Implement host preflight and SSH helpers**

Add helpers for:

- checking required host commands (`tart`, `ssh`, optional `sshpass`)
- fetching the VM IP via `tart ip`
- executing a command over SSH
- piping a local script body to the guest over SSH

- [ ] **Step 5: Run shell syntax verification**

Run: `bash -n scripts/tart/common.sh`
Expected: exit 0

## Chunk 2: VM Lifecycle and Guest Provisioning

### Task 2: Implement project VM creation and mounting

**Files:**
- Create: `scripts/tart/create-dev-vm.sh`
- Modify: `scripts/tart/common.sh`

- [ ] **Step 1: Parse CLI options and validate inputs**

Support:

- `--name <vm-name>`
- `--base-image <image>`
- `--mount <host-path[:guest-name]>` repeatable
- `--recreate`
- `--no-verify`

Default to mounting the current working directory when no explicit `--mount` is supplied.

- [ ] **Step 2: Implement VM existence, recreate, and boot behavior**

Add host-side logic to:

- clone the configured base image if the local VM does not exist
- delete and recreate the VM when `--recreate` is provided
- set a more realistic default CPU and memory profile for Xcode plus simulator work
- start the VM with one or more `--dir` mounts

- [ ] **Step 3: Run guest provisioning from the mounted repo**

After boot:

- locate the selected primary mounted worktree path in the guest
- run `scripts/tart/provision-dev-vm.sh` inside the guest against that worktree

- [ ] **Step 4: Add optional verification stage**

Unless `--no-verify` is set, invoke guest-side verification for:

- toolchain checks
- `cargo check --workspace`
- `./build-ios.sh sim`

- [ ] **Step 5: Run shell syntax verification**

Run:

```bash
bash -n scripts/tart/common.sh scripts/tart/create-dev-vm.sh
```

Expected: exit 0

### Task 3: Implement guest provisioning and worktree verification

**Files:**
- Create: `scripts/tart/provision-dev-vm.sh`
- Modify: `scripts/tart/common.sh`

- [ ] **Step 1: Add guest-side command helpers**

Implement guest helpers for:

- creating `.tart/DerivedData`, `.tart/cargo-target`, `.tart/npm-cache`, `.tart/tmp`
- applying per-worktree environment variables
- checking whether a command exists before installing it

- [ ] **Step 2: Implement provisioning commands**

Provision or verify:

- Xcode availability
- `rustup`
- Rust targets from `rust-toolchain.toml`
- `cbindgen`
- `node` and `npm`
- `@openai/codex`
- `make setup`

Use idempotent checks so repeated runs are cheap.

- [ ] **Step 3: Implement verification subcommands**

Expose guest-side modes such as:

- `provision`
- `verify-toolchain`
- `verify-worktree`

`verify-worktree` should export worktree-local env vars and run:

- `cargo check --workspace`
- `./build-ios.sh sim`

- [ ] **Step 4: Run shell syntax verification**

Run:

```bash
bash -n scripts/tart/provision-dev-vm.sh scripts/tart/common.sh
```

Expected: exit 0

## Chunk 3: Day-to-Day Entry Points

### Task 4: Implement SSH entry and destroy commands

**Files:**
- Create: `scripts/tart/ssh-dev-vm.sh`
- Create: `scripts/tart/destroy-dev-vm.sh`
- Modify: `scripts/tart/common.sh`

- [ ] **Step 1: Implement SSH entry for a selected mount**

Allow:

- defaulting to the current worktree's derived mount name
- or accepting an explicit mount name / host path

Open an interactive shell in the guest at the mounted worktree and pre-export the worktree-local environment variables.

- [ ] **Step 2: Implement explicit destroy flow**

Add a script that:

- resolves the project VM name
- stops it if running
- deletes it only when explicitly requested

- [ ] **Step 3: Run shell syntax verification**

Run:

```bash
bash -n scripts/tart/ssh-dev-vm.sh scripts/tart/destroy-dev-vm.sh scripts/tart/common.sh
```

Expected: exit 0

## Chunk 4: Documentation and Real Validation

### Task 5: Document Tart VM usage and caveats

**Files:**
- Create: `docs/tart-dev-vm.md`
- Modify: `README.md`

- [ ] **Step 1: Document prerequisites and base workflow**

Cover:

- required host tools
- default base image
- where Tart stores VMs and caches
- one-VM-per-project / many-worktrees-per-project model

- [ ] **Step 2: Document worktree isolation**

Explain the per-worktree `.tart/` directories and which paths are isolated versus shared.

- [ ] **Step 3: Document Codex and dependency resolution**

Include:

- `npm install -g @openai/codex`
- `codex login` versus `OPENAI_API_KEY`
- public SwiftPM/Cargo/npm fetches working in the guest
- private registries needing guest-local credentials
- host-local services being the fragile case

- [ ] **Step 4: Document simulator build/install/screenshot workflow**

Show a concrete flow for:

- selecting a simulator
- building `examples/ios`
- installing `RemoExample.app`
- launching bundle id `com.remo.example`
- taking a screenshot with `xcrun simctl io booted screenshot`

- [ ] **Step 5: Add a README pointer**

Add a short development-section link to `docs/tart-dev-vm.md`.

### Task 6: Validate the current worktree path end to end

**Files:**
- Verify only

- [ ] **Step 1: Verify script syntax before execution**

Run:

```bash
bash -n scripts/tart/common.sh \
  scripts/tart/create-dev-vm.sh \
  scripts/tart/provision-dev-vm.sh \
  scripts/tart/ssh-dev-vm.sh \
  scripts/tart/destroy-dev-vm.sh
```

Expected: exit 0

- [ ] **Step 2: Create or recreate the VM for the current worktree**

Run:

```bash
scripts/tart/create-dev-vm.sh --recreate --mount "$PWD:remo-tart-vm"
```

Expected:

- VM is created or recreated from the configured Xcode image
- current worktree appears in the guest at `/Volumes/My Shared Files/remo-tart-vm`
- provisioning completes

- [ ] **Step 3: Confirm toolchain verification evidence**

Expected inside guest output:

- `xcodebuild -version`
- `cargo --version`
- `npm --version`
- `codex --version`
- `cbindgen --version`

- [ ] **Step 4: Confirm project verification evidence**

Expected inside guest output:

- `cargo check --workspace` exits 0
- `./build-ios.sh sim` exits 0

- [ ] **Step 5: Confirm interactive entry works**

Run:

```bash
scripts/tart/ssh-dev-vm.sh remo-tart-vm
```

Expected: interactive shell opens at `/Volumes/My Shared Files/remo-tart-vm` with worktree-local env vars exported.
