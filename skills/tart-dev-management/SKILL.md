---
name: tart-dev-management
description: Use when contributing to Remo itself and you need to bootstrap the shared Tart VM after clone, attach a new worktree to remo-dev, connect through CLI or Remote SSH editors, or clean worktree-local Tart caches.
---

# Tart Dev Management

Use this skill when working on the Remo repository itself inside the shared Tart
development VM.

This skill is for repository contributors. It is not for downstream iOS
projects integrating the Remo SDK.

## Workflow

### 1. First clone bootstrap

After cloning Remo:

1. install Tart on the host with `brew install cirruslabs/cli/tart`
2. run `make setup` from the repo root on the host
3. run `scripts/tart/bootstrap-dev-vm.sh`

That creates or reuses the shared project VM `remo-dev`, mounts the current
worktree, provisions the guest, and runs the default verification path.

Use `--recreate` only when you intentionally want a fresh VM from the base
image. Use `--no-verify` only when you are trying to recover a broken setup and
need to separate VM creation from worktree verification.

### 2. Attach a new worktree

For follow-up feature work:

1. create a new worktree with `git worktree add`
2. `cd` into that new worktree
3. run `scripts/tart/use-worktree-dev-vm.sh`

This attaches the new worktree to the same shared `remo-dev` VM instead of
creating a second VM.

If you need a custom guest mount name, use:

```bash
scripts/tart/use-worktree-dev-vm.sh --mount-name <name>
```

### 3. Connect for daily development

Use the contributor-facing connect wrapper:

```bash
scripts/tart/connect-dev-vm.sh cli
scripts/tart/connect-dev-vm.sh cursor
scripts/tart/connect-dev-vm.sh vscode
```

This separates three connection modes clearly:

- `cli` opens an interactive shell inside the VM
- `cursor` opens the mounted worktree through Cursor Remote SSH
- `vscode` opens the mounted worktree through VS Code Remote SSH

Once the environment is ready, switch to [`skills/remo/SKILL.md`](../remo/SKILL.md)
for verified development and evidence capture.

### 4. Clean only the current worktree

When you want to clear generated state without touching the whole project VM:

```bash
scripts/tart/clean-worktree-dev-vm.sh
```

Default cleanup removes:

- `.tart/DerivedData`
- `.tart/npm-cache`
- `.tart/tmp`

To also remove the Rust incremental target cache:

```bash
scripts/tart/clean-worktree-dev-vm.sh --full
```

This cleanup must not remove tracked Tart configuration:

- `.tart/project.sh`
- `.tart/packs/`

### 5. Inspect health before debugging

Use these before assuming the VM flow is broken:

```bash
scripts/tart/status-dev-vm.sh
scripts/tart/doctor-dev-vm.sh
```

Use `destroy-dev-vm.sh --force` only when you intentionally want to reset the
entire project VM, not as a substitute for worktree-local cache cleanup.

## Common Mistakes

- Do not create a new VM per worktree. Remo uses one shared `remo-dev` VM per
  project.
- Do not use `destroy-dev-vm.sh --force` when you only need to clear one
  worktree’s build outputs.
- Do not treat `.tart/project.sh` or `.tart/packs/` as disposable cache. Those
  are tracked repo configuration.
- Do not switch to the `remo` verification workflow before the Tart environment
  is connected and healthy.
