---
name: tart-dev-management
description: Use when contributing to Remo itself and you need to bootstrap the shared Tart VM after clone, attach a new worktree to remo-dev, connect through CLI or Remote SSH editors, or clean worktree-local Tart caches.
---

# Tart Dev Management

Use this skill when working on the Remo repository itself inside the shared Tart
development VM.

This skill is for repository contributors. It is not for downstream iOS
projects integrating the Remo SDK.

The Tart workflow is driven by the `remo-tart` Python CLI under
`tools/remo-tart/`. See [docs/tart-development-guide.md](../../docs/tart-development-guide.md)
for the full guide and [docs/tart-dev-vm.md](../../docs/tart-dev-vm.md) for
the architectural reference.

## Workflow

### 1. First clone bootstrap

After cloning Remo:

1. install Tart and uv on the host:
   ```bash
   brew install cirruslabs/cli/tart astral-sh/uv/uv
   ```
2. run `make setup` from the repo root
3. install the CLI editable: `uv tool install --editable tools/remo-tart`
4. run `remo-tart up`

`remo-tart up` is idempotent: it creates or reuses the shared project VM
`remo-dev`, mounts the current worktree, provisions the guest, and drops you
into a CLI shell.

To explicitly recreate the VM from the base image:

```bash
remo-tart destroy --force
remo-tart up
```

### 2. Attach a new worktree

For follow-up feature work:

1. create a new worktree with `git worktree add`
2. `cd` into that new worktree
3. run `remo-tart up`

This attaches the new worktree to the same shared `remo-dev` VM. If the VM is
running with a different worktree mounted, `up` restarts it with the new mount
attached.

To attach without connecting (useful in scripts):

```bash
remo-tart use
remo-tart use /path/to/other/worktree
```

### 3. Connect for daily development

```bash
remo-tart up cli       # interactive shell inside the VM
remo-tart up cursor    # open through Cursor Remote SSH
remo-tart up vscode    # open through VS Code Remote SSH
```

If the VM is already running and the current worktree is attached, use
`remo-tart connect <mode>` to skip the attach step.

Once the environment is ready, switch to [`skills/remo/SKILL.md`](../remo/SKILL.md)
for verified development and evidence capture.

### 4. Clean only the current worktree

When you want to remove the current worktree from the shared VM's mount
manifest (without destroying the VM):

```bash
remo-tart clean-worktree              # current worktree
remo-tart clean-worktree /path/to/old-worktree
```

Per-worktree generated state under `.tart/` (DerivedData, cargo-target, npm-cache,
tmp) can be removed with `rm -rf` from inside the worktree — it's gitignored
and recreated on next provisioning.

Tracked Tart configuration must NOT be removed:

- `.tart/project.toml`
- `.tart/provision.sh`, `.tart/verify-worktree.sh`
- `.tart/packs/*.sh`

### 5. Inspect health before debugging

Use these before assuming the VM flow is broken:

```bash
remo-tart status            # human-readable
remo-tart status --json     # machine-readable
remo-tart doctor            # runs ~10 checks, exit 1 on any issue
```

Use `remo-tart destroy --force` only when you intentionally want to reset the
entire project VM, not as a substitute for worktree-local cache cleanup.

### 6. Shell and agent tooling

Provisioning the VM installs:

- **`shell` pack** — sets zsh as the guest login shell, installs oh-my-zsh
  with the `clean` theme, and enables these plugins: `git`, `macos`, `rust`,
  `node`, `npm`, `xcode`, `gh`, `vi-mode`, `zsh-autosuggestions`,
  `zsh-syntax-highlighting`, `zsh-completions`. It also writes
  `~/.remo-worktree-env.sh` so new interactive terminals inherit the
  worktree's cargo target dir, npm cache, and DerivedData path.
- **`agents` pack** — installs the Claude Code CLI (`claude`) and the
  XcodeBuildMCP CLI (`xcodebuildmcp`) as npm globals.

Claude Code login is **not** automated. After the first provision, open an
interactive shell in the VM (`remo-tart up cli`) and run:

```bash
claude
```

Follow the prompts to complete login. This is a one-time step per VM.

To opt a downstream project out of either pack, edit `.tart/project.toml` and
remove the pack name from `[packs] enabled`.

## Common Mistakes

- Do not create a new VM per worktree. Remo uses one shared `remo-dev` VM per
  project.
- Do not use `remo-tart destroy --force` when you only need to clear one
  worktree's mount.
- Do not treat `.tart/project.toml` or `.tart/packs/` as disposable cache.
  Those are tracked repo configuration.
- Do not switch to the `remo` verification workflow before the Tart environment
  is connected and healthy.
