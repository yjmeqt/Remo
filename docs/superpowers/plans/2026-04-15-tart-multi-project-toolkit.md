# Tart Multi-Project Toolkit Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the current Remo-specific Tart VM workflow into a reusable project-manifest plus language-pack system that can support multiple macOS+iOS repositories with different language stacks.

**Architecture:** Keep VM lifecycle, mount management, `.git` bridge handling, Remote SSH, and diagnostics in the shared shell layer under `scripts/tart/`. Move project-specific dependency and verification behavior into a repo-local `.tart/project.sh` manifest plus reusable language-pack helpers under `.tart/packs/`. Make Remo the first consumer by declaring `ios`, `rust`, and `node` packs and its existing project-specific verify commands.

**Tech Stack:** Bash, Tart CLI, macOS launchd/ssh, Xcode/xcodebuild, rustup/cargo, npm/node, Go, Python

---

## File Structure

- Create: `.tart/project.sh`
  - Project manifest: VM/base-image/network defaults, enabled packs, project-specific provision hooks, and project-specific verification commands.
- Create: `.tart/packs/ios.sh`
  - Shared iOS/Xcode guest provisioning and verify helpers.
- Create: `.tart/packs/rust.sh`
  - Shared Rust guest provisioning and worktree cache/export helpers.
- Create: `.tart/packs/node.sh`
  - Shared Node/npm guest provisioning and cache/export helpers.
- Create: `.tart/packs/go.sh`
  - Shared Go guest provisioning and cache/export helpers.
- Create: `.tart/packs/python.sh`
  - Shared Python guest provisioning and cache/export helpers.
- Modify: `scripts/tart/common.sh`
  - Load `.tart/project.sh`, expose project-manifest accessors, and generalize worktree-local env exports beyond the current Rust/Node/iOS defaults.
- Modify: `scripts/tart/create-dev-vm.sh`
  - Read project manifest defaults instead of hardcoded Remo-specific values and continue to own the shared Tart lifecycle.
- Modify: `scripts/tart/provision-dev-vm.sh`
  - Replace hardcoded Rust/Node/iOS provisioning with manifest-driven pack loading and pack-level hooks.
- Modify: `scripts/tart/status-dev-vm.sh`
  - Surface enabled packs in machine-readable status so operators know which project contract is active.
- Modify: `scripts/tart/doctor-dev-vm.sh`
  - Mention missing project manifest / malformed pack declarations as actionable issues.
- Modify: `tests/tart_vm_scripts.sh`
  - Cover project-manifest loading, pack parsing, and `.git`-only compatibility mount expectations.
- Modify: `tests/tart_vm_provision.sh`
  - Cover manifest-driven pack resolution and pack-level worktree env exports.
- Modify: `tests/tart_vm_status.sh`
  - Cover status output for enabled packs and manifest presence.
- Modify: `tests/tart_vm_doctor.sh`
  - Cover doctor output for missing/invalid project manifest or pack declarations.
- Modify: `docs/tart-development-guide.md`
  - Document the new `.tart/project.sh` contract, language packs, and multi-project reuse story.
- Modify: `docs/tart-dev-vm.md`
  - Document shared vs project-specific Tart layers and pack responsibilities.
- Modify: `docs/tart-dev-vm-handoff.md`
  - Record the refactor and the new configuration model.
- Modify: `README.md`
  - Keep the Tart guide entry aligned with the new manifest-driven setup.
- Modify: `AGENTS.md`
  - Point agents at `.tart/project.sh` and pack docs when working on Tart VM behavior.

## Chunk 1: Project Manifest Foundation

### Task 1: Add a repo-local Tart project manifest contract

**Files:**
- Create: `.tart/project.sh`
- Modify: `scripts/tart/common.sh`
- Test: `tests/tart_vm_scripts.sh`

- [ ] **Step 1: Write failing shell tests for project-manifest loading**

Add assertions in `tests/tart_vm_scripts.sh` for:

- loading `.tart/project.sh`
- resolving enabled packs in declaration order
- resolving project defaults for VM name, base image, network mode, CPU, and memory
- falling back to current shared defaults when a project function is omitted

- [ ] **Step 2: Run the shell test to verify it fails**

Run: `bash tests/tart_vm_scripts.sh`
Expected: FAIL because the shared helpers do not yet load `.tart/project.sh` or expose pack/default accessors.

- [ ] **Step 3: Add `.tart/project.sh` for Remo**

Define minimal manifest functions for:

- project slug / VM name
- base image
- network mode
- CPU / memory
- enabled packs: `ios`, `rust`, `node`
- project-specific `make setup`
- project-specific worktree verification (`cargo check --workspace`, `./build-ios.sh sim`)

- [ ] **Step 4: Implement shared manifest-loading helpers**

In `scripts/tart/common.sh`, add minimal helpers for:

- loading `.tart/project.sh` once
- listing enabled packs
- fetching project defaults with fallbacks
- running optional project-level hook functions if present

- [ ] **Step 5: Re-run the shell test to verify it passes**

Run: `bash tests/tart_vm_scripts.sh`
Expected: PASS

## Chunk 2: Language Pack Layer

### Task 2: Introduce pack files and pack-driven worktree env exports

**Files:**
- Create: `.tart/packs/ios.sh`
- Create: `.tart/packs/rust.sh`
- Create: `.tart/packs/node.sh`
- Create: `.tart/packs/go.sh`
- Create: `.tart/packs/python.sh`
- Modify: `scripts/tart/common.sh`
- Modify: `tests/tart_vm_scripts.sh`
- Modify: `tests/tart_vm_provision.sh`

- [ ] **Step 1: Write failing tests for pack-specific env exports**

Extend tests to assert that:

- `rust` adds `.tart/cargo-target`
- `node` adds `.tart/npm-cache`
- `go` adds `.tart/go-build` and `.tart/go-mod`
- `python` adds `.tart/venv` and `.tart/pip-cache`
- `ios` keeps `.tart/DerivedData`

- [ ] **Step 2: Run the relevant tests to verify failure**

Run:

```bash
bash tests/tart_vm_scripts.sh
bash tests/tart_vm_provision.sh
```

Expected: FAIL because pack files and generalized worktree env helpers do not exist yet.

- [ ] **Step 3: Create the pack files with focused responsibilities**

Each pack file should expose only the functions it owns:

- env exports for worktree-local caches/dirs
- guest-side ensure/verify helpers for that language/toolchain

- [ ] **Step 4: Update shared worktree env handling to aggregate enabled packs**

Generalize `remo_tart_worktree_env_exports` so it:

- always creates `.tart/tmp`
- adds pack-specific exports only for enabled packs
- preserves current Remo behavior under `ios`, `rust`, and `node`

- [ ] **Step 5: Re-run the tests to verify they pass**

Run:

```bash
bash tests/tart_vm_scripts.sh
bash tests/tart_vm_provision.sh
```

Expected: PASS

## Chunk 3: Manifest-Driven Guest Provisioning

### Task 3: Replace hardcoded provisioning with pack-driven hooks

**Files:**
- Modify: `scripts/tart/provision-dev-vm.sh`
- Modify: `.tart/project.sh`
- Modify: `.tart/packs/ios.sh`
- Modify: `.tart/packs/rust.sh`
- Modify: `.tart/packs/node.sh`
- Modify: `tests/tart_vm_provision.sh`

- [ ] **Step 1: Write failing tests for pack-driven provisioning order**

Add tests that confirm:

- only enabled packs are consulted
- project-level provision hooks still run after pack-level ensures
- project-level verify hooks still run for `verify-worktree`

- [ ] **Step 2: Run the provisioning test to verify it fails**

Run: `bash tests/tart_vm_provision.sh`
Expected: FAIL because provisioning is still hardcoded to Rust/Node/Codex/Remo commands.

- [ ] **Step 3: Implement minimal pack-driven provision flow**

Refactor `scripts/tart/provision-dev-vm.sh` so it:

- loads enabled packs from the project manifest
- sources the corresponding `.tart/packs/*.sh` files
- runs pack-level ensure hooks for `provision`
- runs project-level provision hook afterward

- [ ] **Step 4: Implement minimal pack-driven verify flow**

Refactor `verify-toolchain` and `verify-worktree` so they:

- aggregate pack-level toolchain version output
- run project-level worktree verification commands from the manifest

- [ ] **Step 5: Re-run the provisioning test to verify it passes**

Run: `bash tests/tart_vm_provision.sh`
Expected: PASS

## Chunk 4: Shared Entrypoints Read Project Defaults

### Task 4: Switch shared entrypoints to project-derived defaults

**Files:**
- Modify: `scripts/tart/common.sh`
- Modify: `scripts/tart/create-dev-vm.sh`
- Modify: `scripts/tart/status-dev-vm.sh`
- Modify: `scripts/tart/doctor-dev-vm.sh`
- Modify: `tests/tart_vm_scripts.sh`
- Modify: `tests/tart_vm_status.sh`
- Modify: `tests/tart_vm_doctor.sh`

- [ ] **Step 1: Write failing tests for status/doctor manifest awareness**

Add assertions for:

- enabled pack list in `status-dev-vm.sh`
- missing `.tart/project.sh` reported by `doctor-dev-vm.sh`
- defaults coming from the manifest instead of old hardcoded constants

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
bash tests/tart_vm_scripts.sh
bash tests/tart_vm_status.sh
bash tests/tart_vm_doctor.sh
```

Expected: FAIL because the entrypoints do not yet expose manifest-driven state.

- [ ] **Step 3: Wire shared entrypoints to manifest defaults**

Make the create/status/doctor path read:

- VM name
- base image
- network mode
- CPU / memory
- enabled packs

from the project manifest with current defaults as fallback.

- [ ] **Step 4: Re-run the tests to verify they pass**

Run:

```bash
bash tests/tart_vm_scripts.sh
bash tests/tart_vm_status.sh
bash tests/tart_vm_doctor.sh
```

Expected: PASS

## Chunk 5: Docs And Real Remo Verification

### Task 5: Document the new multi-project contract and verify Remo still works

**Files:**
- Modify: `docs/tart-development-guide.md`
- Modify: `docs/tart-dev-vm.md`
- Modify: `docs/tart-dev-vm-handoff.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Update docs for the new configuration model**

Document:

- `.tart/project.sh`
- `.tart/packs/*.sh`
- current Remo pack set (`ios`, `rust`, `node`)
- how another project would declare `go`, `python`, or both

- [ ] **Step 2: Run the full repository-side Tart regression suite**

Run:

```bash
bash tests/tart_vm_scripts.sh
bash tests/tart_vm_entrypoints.sh
bash tests/tart_vm_provision.sh
bash tests/tart_vm_status.sh
bash tests/tart_vm_doctor.sh
bash tests/build_ios_target_dir.sh
bash -n scripts/tart/common.sh scripts/tart/create-dev-vm.sh scripts/tart/provision-dev-vm.sh scripts/tart/ssh-dev-vm.sh scripts/tart/destroy-dev-vm.sh scripts/tart/prepare-remote-ssh-dev-vm.sh scripts/tart/open-editor-dev-vm.sh scripts/tart/open-vscode-dev-vm.sh scripts/tart/open-cursor-dev-vm.sh scripts/tart/codex-dev-vm.sh scripts/tart/status-dev-vm.sh scripts/tart/doctor-dev-vm.sh tests/tart_vm_scripts.sh tests/tart_vm_provision.sh tests/tart_vm_status.sh tests/tart_vm_doctor.sh
```

Expected: PASS

- [ ] **Step 3: Re-run the real Remo VM update path**

Run:

```bash
scripts/tart/create-dev-vm.sh --network bridged:en0 --mount "$PWD:remo-tart-vm" --no-verify
```

Expected:

- manifest still contains only `remo-tart-vm` and `remo-git-root`
- pack-driven provisioning completes for Remo

- [ ] **Step 4: Verify guest-side Git and project verification still work**

Run:

```bash
tart exec remo-dev /bin/zsh -lc 'cd "/Volumes/My Shared Files/remo-tart-vm" && git rev-parse --git-dir && git rev-parse --git-common-dir'
tart exec remo-dev /bin/zsh -lc 'script="/Volumes/My Shared Files/remo-tart-vm/scripts/tart/provision-dev-vm.sh"; "$script" verify-toolchain "/Volumes/My Shared Files/remo-tart-vm"'
```

Expected: PASS with `.git`-root paths resolving under `/Volumes/My Shared Files/remo-git-root`

