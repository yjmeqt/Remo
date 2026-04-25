# Tart Dev VM Reference

This document is the **architectural reference** for the Remo Tart workflow.
For day-to-day usage (install, attach, connect, clean), start with
[docs/tart-development-guide.md](./tart-development-guide.md).

This file covers what the dev guide intentionally omits: how the pieces fit
together. Useful when something breaks in a way `remo-tart doctor` doesn't
explain, or when you're extending the CLI.

## Host Prerequisites

- macOS host running `tart` (`brew install cirruslabs/cli/tart`)
- `uv` (`brew install astral-sh/uv/uv`)
- Apple Silicon required for the macOS guest images
- Active virtualization-friendly bridged interface (default `en0`); other
  network modes (`shared`, `softnet`) work but require config edits

## Storage Layout

Three locations of state:

**Repository (tracked, per-project):**

- `.tart/project.toml` — declarative project config (VM name, packs, scripts)
- `.tart/provision.sh` — guest-side provision hook
- `.tart/verify-worktree.sh` — guest-side worktree verification hook
- `.tart/packs/*.sh` — user-extensible bash packs

**Repository (gitignored, per-worktree):**

- `.tart/DerivedData`, `.tart/cargo-target`, `.tart/npm-cache`, `.tart/tmp`

**Host-side state, shared across worktrees:**

- `~/.config/remo/tart/<vm-name>.mounts` — mount manifest (tab-separated:
  `<name>\t<host-path>` per line)
- `~/.config/remo/tart/<vm-name>.log` — VM stdout/stderr captured by launchd
- `~/.config/remo/tart/ssh_config` — managed SSH `Host` block, included from
  `~/.ssh/config` via a managed `Include` directive
- `~/.config/remo/tart/ssh/<vm-name>_ed25519` — generated SSH keypair
- `~/.tart/vms/`, `~/.tart/cache/OCIs/` — Tart's own VM disks and image cache

## State Machine

`remo-tart up` is idempotent. The decision function (`remo_tart.state.decide`)
maps a `VmState(exists, running, mount_matches)` to one or more actions:

| `exists` | `running` | `mount_matches` | Actions |
|---|---|---|---|
| F | — | — | CREATE |
| T | F | F | ATTACH_MOUNT_AND_START |
| T | F | T | START |
| T | T | F | UPDATE_MOUNT_AND_RESTART |
| T | T | T | NOTHING |

`mount_matches` is computed against the manifest **before** the upsert, so it
reflects what the currently-running VM was booted with. If it's `False`, the
running VM doesn't see the active worktree's mount and a restart is required.

## Mount Changes Require A VM Restart

Tart attaches directory shares (`--dir <name>:<host-path>:rw`) at boot only.
Adding or changing a mount cannot be done live. The orchestrator
(`remo_tart.worktree`) handles this by:

1. Writing the new mount entry into the manifest atomically.
2. `launchctl remove`-ing the running tart job.
3. Polling for the VM to stop AND for launchctl to drop the label.
4. `launchctl submit`-ing a new tart job with the updated `--dir` arguments.
5. Waiting for the guest agent to respond to `tart exec /usr/bin/true` before
   proceeding.

Step 5 is stricter than just "VM running" because the guest agent comes up
several seconds after the VM is technically running, and downstream SSH key
injection needs the agent to be live.

## Git Worktree `.git` Bridge

Each git worktree has a small `.git` file (not directory) pointing back to the
shared `.git` directory in the main checkout. To make this work inside the
guest, the orchestrator:

1. Adds a special bridge mount entry named `<slug>-git-root` whose host path
   is the actual `.git` directory of the project.
2. Generates a guest-side bash script (`mount.guest_bridge_script`) that, on
   each non-bridge mount, replaces `<mount>/.git` with a symlink to
   `/Volumes/My Shared Files/<slug>-git-root`.
3. Runs the script via `vm.exec_interactive` after the VM is up.

This means every mounted worktree resolves git operations against the same
shared object database, so commits made in one worktree are visible in others
without duplication.

## Launchd Integration

Each `remo-tart up` submits a launchd job rather than running `tart run`
directly. Why: the job survives a closed terminal, captures stdout/stderr to a
log file, and integrates with macOS session lifecycle.

Implementation: `launchctl submit -l com.remo.tart.<slug> -- /bin/zsh -lc
"exec tart run <args> > <log> 2>&1"`. **No plist file is written** — the
submission is in-memory.

Job presence is checked with `launchctl print gui/<uid>/<label>`.

The orchestrator clears the label (`launchctl remove`) before every fresh
submit to avoid `submit` failing on an already-registered label (e.g. after a
crash).

## SSH Configuration

The CLI maintains two SSH config artefacts:

- `~/.config/remo/tart/ssh_config` — a managed `Host` block:

  ```
  # >>> remo tart managed: remo-dev >>>
  Host tart-remo-dev
    HostName 127.0.0.1
    User admin
    IdentityFile ~/.config/remo/tart/ssh/remo-dev_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ProxyCommand tart exec -i remo-dev /usr/bin/nc 127.0.0.1 22
  # <<< remo tart managed: remo-dev <<<
  ```

- `~/.ssh/config` — a managed `Include` directive that pulls the above:

  ```
  # >>> remo tart include >>>
  Include ~/.config/remo/tart/ssh_config
  # <<< remo tart include <<<
  ```

Marker pairs are byte-identical to the legacy bash format so existing
`~/.ssh/config` files keep working without manual cleanup.

The matching SSH keypair (`~/.config/remo/tart/ssh/<vm>_ed25519`) is generated
once and reused. The public key is injected into the guest's
`~/.ssh/authorized_keys` idempotently (grep-skip-if-present).

`remo-tart destroy --force` removes the managed block, the include directive,
and (per future work) the key files.

## Mount Name Derivation

`mount.mount_name_for_path(slug, host_path)` follows these rules:

1. Take basename of host path.
2. Lowercase, collapse `[^a-z0-9]+` to `-`, strip leading/trailing `-`.
3. If result equals project slug → return as-is (`remo`).
4. If result starts with `<slug>-` → return as-is (`remo-feature-x`).
5. Otherwise → prepend `<slug>-` (`remo-fix-e2e`).

This is byte-compatible with the legacy bash slug logic.

## Pack Scripts

`.tart/packs/<name>.sh` files are user-extensible bash. Each pack defines
functions named `tart_pack_<name>_ensure` (called by
`provision.run_provision`) and may also define
`tart_pack_<name>_verify_toolchain` and worktree env exports.

The CLI does not parse or validate pack contents — the contract is "this is a
bash file that defines specific shell functions." Declarative packs (TOML
schema) are tracked as future work in `docs/README-TODO.md`.

## CLI Architecture

`tools/remo-tart/src/remo_tart/` modules:

| Module | Responsibility |
|---|---|
| `paths` | Centralised on-disk paths + `find_repo_root` |
| `config` | Pydantic-validated `.tart/project.toml` loader |
| `mount` | Mount manifest read/write + name derivation + git bridge |
| `ssh` | Managed block editor + keypair |
| `launchd` | `launchctl submit/remove/print` wrapper |
| `vm` | `tart` CLI subprocess wrappers |
| `state` | Pure decision function for `up` |
| `worktree` | Attach/boot orchestrator (uses everything above) |
| `provision` | Guest-side bash script generation + `vm.exec_interactive` |
| `connect` | cli/vscode/cursor dispatch |
| `status` | Collector + human/JSON renderer |
| `doctor` | Checks + findings renderer |
| `cli` | Click command tree |
| `errors` | `RemoTartError` with `hint` field |
| `console` | Rich console + `render_error` |

Pure modules are fully unit-tested. Subprocess wrappers (`vm`, `launchd`) are
tested via mock. Real-VM integration is verified manually before each
release.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `vm is not running: <name>` | VM stopped or never created | `remo-tart up` |
| `unable to find the Remo repo root` | cwd has no `.tart/project.toml` ancestor | `cd` into a worktree |
| `no mounts attached to this VM` | manifest empty for this VM | `remo-tart use` |
| `failed to install ssh public key into guest` | guest agent not ready | wait, then re-run; check VM log |
| Stale launchd job (`doctor` warns) | crash left a dangling label | `remo-tart up` (clears stale before submit) |
| VS Code says "host can't be reached" | SSH include/key drift | `remo-tart destroy --force` then `remo-tart up vscode` |

When `remo-tart doctor` reports issues, the `hint:` line points at the next
action. The VM log path is `~/.config/remo/tart/<vm-name>.log`.
