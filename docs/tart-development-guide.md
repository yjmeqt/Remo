# Tart Development Guide

This is the main contributor guide for working on Remo inside the shared Tart
development VM.

Use this document for:

- first-time setup after cloning Remo
- attaching each new worktree to the shared `remo-dev` VM
- connecting through CLI, Cursor, or VS Code
- cleaning a worktree's mount when it's no longer needed
- checking `status` / `doctor` before debugging a broken workflow

For lower-level reference (state machine, mount manifest format, troubleshooting),
see [docs/tart-dev-vm.md](./tart-dev-vm.md).

For agents working on the Remo repository itself, the matching workflow skill
is [skills/tart-dev-management/SKILL.md](../skills/tart-dev-management/SKILL.md).

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

- `.tart/project.toml` — declarative project config (VM name, packs, scripts)
- `.tart/provision.sh` — shell run on the guest after pack ensures
- `.tart/verify-worktree.sh` — shell run to verify a worktree builds
- `.tart/packs/*.sh` — user-extensible pack scripts run on the guest

Generated per-worktree state lives under `.tart/`:

- `.tart/DerivedData`
- `.tart/cargo-target`
- `.tart/npm-cache`
- `.tart/tmp`

Tart stores VM disks and OCI image caches outside the repository:

- `~/.tart/vms/`
- `~/.tart/cache/OCIs/`

Remo-specific host state for this workflow lives in:

- `~/.config/remo/tart/`

## Install the CLI

The Tart workflow is driven by the `remo-tart` Python CLI under
`tools/remo-tart/`. Install it editable so source edits take effect immediately:

```bash
brew install cirruslabs/cli/tart
brew install astral-sh/uv/uv
uv tool install --editable tools/remo-tart
remo-tart --help
```

If you have multiple worktrees, pick one as your "CLI dev" worktree — `uv tool
install --editable` points at one path, and other worktrees consume that same
installed binary.

## First-Time Setup After Clone

```bash
git clone https://github.com/yjmeqt/Remo.git
cd Remo
make setup
uv tool install --editable tools/remo-tart
remo-tart up
```

`remo-tart up` is idempotent: it creates the VM if missing, attaches the current
worktree, boots, provisions, and drops you into a CLI shell. Subsequent runs
from the same worktree reuse the running VM with no reboot.

Useful variants:

```bash
remo-tart up vscode    # attach + open VS Code Remote SSH
remo-tart up cursor    # attach + open Cursor Remote SSH
remo-tart bootstrap    # explicit first-time setup (alias of up cli)
```

## Attaching a New Worktree

When you create a new git worktree:

```bash
git worktree add ../remo-feature my-branch
cd ../remo-feature
remo-tart up
```

`remo-tart up` derives the mount name from the worktree directory and re-attaches
the VM with the new mount. If the VM is currently running with a different
worktree mounted, it restarts the VM with the new mount attached.

To attach without connecting (useful in scripts):

```bash
remo-tart use            # attach current worktree
remo-tart use /path/to/other/worktree
```

## Connecting Without Re-Attaching

If the VM is already running and the current worktree is already attached,
connect directly:

```bash
remo-tart connect cli
remo-tart connect vscode
remo-tart connect cursor
```

Each opens the editor against the worktree's mount inside the guest at
`/Volumes/My Shared Files/<mount-name>`.

If the VM is not running, `connect` fails with a hint pointing at `remo-tart up`.

## Cleaning Up a Worktree

When you're done with a worktree:

```bash
remo-tart clean-worktree              # current worktree
remo-tart clean-worktree /path/to/old-worktree
```

This removes the mount from the manifest. The VM is not restarted automatically;
the next `remo-tart up` from a different worktree will pick up the cleaned
manifest.

To destroy the entire VM:

```bash
remo-tart destroy --force
```

This also cleans up the managed SSH config block and the include in
`~/.ssh/config`.

## Status and Doctor

Two non-destructive observability commands:

```bash
remo-tart status            # human-readable
remo-tart status --json     # machine-readable
remo-tart doctor            # health checks; exit code 1 if any issue
```

`status` reports VM state, launchd job presence, mount manifest contents, and
SSH config state. `doctor` runs ~10 checks covering project config, VM state,
launchd consistency, mount-path existence, pack file presence, SSH config,
and SSH key.

Use `doctor` before opening an issue — it usually surfaces the actual cause.

## Running Tests Inside the VM

Open a CLI shell and run the project's tests there:

```bash
remo-tart up cli
# inside the VM:
cargo test --workspace
./build-ios.sh sim
```

Or use the project-defined verification script:

```bash
remo-tart use            # attach + run .tart/verify-worktree.sh
```

(`.tart/verify-worktree.sh` runs after every `remo-tart use` unless you've
disabled verification — currently this happens implicitly inside the
provisioning step.)

## When Things Break

Order of operations:

1. `remo-tart doctor` — what does it say?
2. `remo-tart status` — does the actual state match what you expected?
3. `remo-tart destroy --force && remo-tart up` — last resort; recreates the VM.

Common failure modes:

- **`vm is not running`**: run `remo-tart up` (creates and connects) or
  `remo-tart start` (boots without changing mounts).
- **`unable to find the Remo repo root`**: you're outside a worktree containing
  `.tart/project.toml`. `cd` into one.
- **`no mounts attached`**: VM is running but this worktree was never attached.
  Run `remo-tart use` from this worktree.
- **Stale launchd job**: `remo-tart doctor` reports a launchd job present but
  VM not running. Run `remo-tart up` again — the orchestrator clears the stale
  job before re-submitting.

## Project Config Schema

`.tart/project.toml` is the declarative config. All fields:

```toml
[project]
slug = "remo"

[vm]
name = "remo-dev"
base_image = "ghcr.io/cirruslabs/macos-tahoe-xcode:26"
cpu = 6
memory_gb = 12
network = "bridged:en0"        # "shared" | "softnet" | "bridged:<iface>"
guest_user = "admin"            # optional; defaults to "admin"
guest_password = "admin"        # optional; defaults to "admin"

[packs]
enabled = ["shell", "ios", "rust", "node", "agents"]

[scripts]
provision = ".tart/provision.sh"
verify_worktree = ".tart/verify-worktree.sh"
```

Pack scripts under `.tart/packs/<name>.sh` are user-extensible — write a bash
file that defines `tart_pack_<name>_ensure` and reference it in
`[packs] enabled`.

## Working On the CLI Itself

Source layout:

- `tools/remo-tart/src/remo_tart/` — Python package
- `tools/remo-tart/tests/` — pytest unit tests
- `tools/remo-tart/pyproject.toml` — uv project manifest

Daily commands from inside `tools/remo-tart/`:

```bash
uv run ruff check .
uv run ruff format .
uv run pytest -v
```

The pre-commit hook automatically runs ruff when `tools/remo-tart/**` or
`.tart/**` files change. CI runs ruff + pytest on every push.

After editing CLI source, the editable install picks up changes immediately —
no reinstall needed.
