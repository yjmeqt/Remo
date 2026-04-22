# Tart Start UX Design

Date: 2026-04-22
Status: Approved for planning
Branch: `refactor/tart-start-ux`

## Summary

Refactor the Tart contributor start/connect flow so `scripts/tart/connect-dev-vm.sh`
is the forgiving day-to-day entrypoint for the shared `remo-dev` VM.

The main user-facing change is:

- `connect-dev-vm.sh` should prepare the selected worktree mount and shared VM
  when needed before delegating to `cli`, `cursor`, or `vscode`
- `use-worktree-dev-vm.sh` should remain available as an explicit attach helper,
  but it should no longer be required knowledge before a normal connect

This keeps the existing lifecycle ownership in `create-dev-vm.sh` while removing
the current footgun where `connect` sounds like the right first command but
fails on a stopped VM.

## Problem

The current Tart workflow exposes internal lifecycle details that contributors
should not need to understand for routine work.

Today:

- `connect-dev-vm.sh` is only a dispatcher
- `open-editor-dev-vm.sh` and `ssh-dev-vm.sh` fail if the VM is not already
  running
- `use-worktree-dev-vm.sh` mixes two responsibilities: attach a worktree mount
  and ensure the VM is booted/provisioned

This creates a misleading user model:

- `connect` looks like the normal entrypoint, but it is not safe as a first
  command
- the user must learn whether the VM is missing, stopped, or missing a mount
- failure output explains what is false, but not what action should happen next

The resulting UX is easy to misunderstand even when the system is behaving as
designed.

## Goals

- Make `connect-dev-vm.sh` the obvious safe entrypoint for daily contributor use
- Preserve one shared project VM (`remo-dev`) across worktrees
- Reuse the existing create/start/provision path instead of duplicating
  lifecycle logic across multiple scripts
- Improve failure messages so direct leaf-script callers get a clear recovery
  path
- Keep the change small enough to land with focused shell tests and doc updates

## Non-Goals

- Introduce a new `up-dev-vm.sh` command
- Replace the shared-project-VM model with one VM per worktree
- Move mount mutation logic out of `create-dev-vm.sh`
- Redesign low-level Tart provisioning or pack loading behavior
- Automatically guess the host path for an unknown mount name that is not
  recorded in the manifest

## Chosen Direction

Use Option B from the handoff discussion:

- keep the current command names
- make `connect-dev-vm.sh` auto-ensure the requested worktree mount and running
  VM state before delegating
- keep `ssh-dev-vm.sh` and editor leaf scripts strict, but improve their error
  messages to point users back to `connect-dev-vm.sh`

This directly fixes the main contributor footgun without introducing a larger
command taxonomy change.

## User-Facing Command Contract

The happy path becomes:

```bash
scripts/tart/connect-dev-vm.sh cli
scripts/tart/connect-dev-vm.sh cursor
scripts/tart/connect-dev-vm.sh vscode --new-window
```

Behavior for `connect-dev-vm.sh`:

1. Resolve the selected target from:
   - explicit `<mount-name|host-path>`
   - or `PWD` when the target is omitted
2. Determine whether the target can be attached or resolved from existing
   manifest state
3. If lifecycle work is required, call the existing create path
4. Delegate to the existing connection leaf script for the requested mode

Expected outcomes:

- If the VM is already running and the target mount is already recorded, connect
  immediately
- If the VM is stopped or missing, prepare it and then connect
- If the VM is running but a new host-path target is not recorded, record the
  mount, restart through the existing create path, and then connect
- If the user passes an unrecorded mount name with no host path, fail with an
  explicit recovery message instead of guessing

`use-worktree-dev-vm.sh` remains valid for users who want to attach a worktree
explicitly ahead of time, but it is no longer required as the documented first
step before connecting.

## Internal Design

### Lifecycle Ownership

`create-dev-vm.sh` remains the only script that owns:

- host manifest pruning and updates
- hidden `.git` bridge mount handling
- VM creation, boot, and restart for mount changes
- guest provisioning and optional verification

The refactor should not duplicate any of that behavior inside `connect`.

### Connect Preflight

`connect-dev-vm.sh` should gain a preflight stage before its mode dispatch:

- Parse mode, VM name override, editor flags, and optional target as today
- Resolve the effective target
- Decide whether it is a host path or a mount name
- Determine whether the mount is already recorded in the manifest
- Determine whether the VM is running
- Invoke the shared create path only when lifecycle work is actually needed

The preflight should use shared Tart helpers where possible. If the current
helpers do not cleanly expose the needed checks, add a small shared helper in
`scripts/tart/common.sh` rather than embedding the logic in multiple scripts.

### Target Resolution Rules

If the target is omitted:

- Use `PWD`
- Treat it as a host path target

If the target is a host path:

- Resolve the absolute path
- Derive the mount name from that path
- Allow `connect` to attach it automatically through the create path

If the target is a mount name:

- Resolve it from the manifest when present
- If it is missing from the manifest, fail with a recovery message that tells
  the user to re-run from the worktree or pass an absolute path

This avoids unsafe guessing for unknown mount names while still making the
common host-path and current-directory flows forgiving.

### Decision Matrix

#### VM running + mount recorded

- Do not call `create-dev-vm.sh`
- Delegate directly to the existing leaf script

#### VM stopped or missing + target resolved

- Print a concise prepare message
- Call `create-dev-vm.sh --mount <host-path:mount-name>`
- Delegate after the create path succeeds

#### VM running + host-path target not recorded

- Print that the worktree is being attached and that Tart will restart the VM to
  apply the new mount
- Call `create-dev-vm.sh --mount <host-path:mount-name>`
- Delegate after the create path succeeds

#### Mount-name target not recorded

- Fail fast before calling the leaf script
- Do not guess or synthesize a host path
- Print an explicit next step

## Failure Messaging

The key UX improvement is not only automatic recovery, but also clear messages
when automatic recovery is not possible.

### `connect-dev-vm.sh`

For an unrecorded mount-name target, the error should be explicit and actionable:

```text
mount is not recorded for remo-dev: <name>
Re-run this command from that worktree or pass its absolute path to attach it.
```

For lifecycle work, the script should print a short high-level line before
calling the create path, for example:

```text
Preparing shared Tart VM for mount: remo-feature-x
```

or, when a running VM must restart for a new mount:

```text
Attaching worktree mount remo-feature-x; Tart will restart the shared VM to apply new mounts.
```

The output should make it obvious that the command is making progress rather
than simply failing or silently reusing a hidden codepath.

### Leaf Scripts

`ssh-dev-vm.sh` and `open-editor-dev-vm.sh` should remain strict leaf scripts.
They should not grow their own lifecycle logic.

If called directly while the VM is stopped, their error text should include the
safe recovery path through `connect-dev-vm.sh`, for example:

```text
vm is not running: remo-dev
Use scripts/tart/connect-dev-vm.sh <mode> [target] to prepare the VM and reconnect.
```

This keeps direct callers from falling into the same dead end as before.

## Files In Scope

Primary behavior changes:

- `scripts/tart/connect-dev-vm.sh`
- `scripts/tart/common.sh`
- `scripts/tart/open-editor-dev-vm.sh`
- `scripts/tart/ssh-dev-vm.sh`

Docs:

- `docs/tart-development-guide.md`
- `docs/tart-dev-vm.md`

Tests:

- `tests/tart_vm_workflow.sh`
- `tests/tart_vm_entrypoints.sh`

Related files to read while implementing:

- `scripts/tart/use-worktree-dev-vm.sh`
- `scripts/tart/create-dev-vm.sh`
- `scripts/tart/status-dev-vm.sh`
- `scripts/tart/doctor-dev-vm.sh`

## Testing Strategy

Add focused shell coverage around the new `connect` preflight behavior.

Required regression cases:

1. VM already running and mount already recorded:
   - `connect` should skip the create path
   - `connect` should delegate directly to `ssh-dev-vm.sh`

2. VM stopped and target resolved from current directory or explicit host path:
   - `connect` should invoke the create path with the resolved mount
   - then delegate to the leaf script

3. VM running and a new host-path target is not recorded:
   - `connect` should invoke the create path to attach the mount
   - editor flags such as `--new-window` and `--reuse-window` must still reach
     the editor launchers unchanged

4. Mount-name target not recorded:
   - `connect` should fail with the explicit recovery message
   - the create path should not be invoked

5. Direct leaf-script invocation with a stopped VM:
   - `ssh-dev-vm.sh` should include the new connect-based recovery message
   - editor leaf scripts should include the same guidance

6. Help text:
   - `connect-dev-vm.sh --help` should describe that the command prepares the
     shared VM when needed

The tests should stay shell-first and stub-driven, following the current Tart
script test style.

## Documentation Changes

### `docs/tart-development-guide.md`

Update the contributor guide so `connect-dev-vm.sh` is clearly presented as the
forgiving primary entrypoint for CLI, Cursor, and VS Code.

The “Create And Attach A New Worktree” section should still document
`use-worktree-dev-vm.sh`, but it should describe it as an explicit attach helper
instead of a required first step before connecting.

### `docs/tart-dev-vm.md`

Update the lower-level reference to explain that `connect-dev-vm.sh` now reuses
the existing create path when it needs to ensure the selected mount and running
VM state.

This document should continue to describe `create-dev-vm.sh` as the lifecycle
owner.

## Risks And Guardrails

- Calling `create-dev-vm.sh` unconditionally from `connect` would over-couple
  normal connect operations to provisioning work; the preflight must only invoke
  it when necessary
- Unknown mount names must not be silently guessed into host paths
- The leaf scripts must not each grow their own lifecycle behavior
- Mount-change restarts are expected Tart behavior and should be explained, not
  hidden

## Success Criteria

This refactor is successful when:

- a contributor can run `scripts/tart/connect-dev-vm.sh <mode>` as the normal
  first command from a mounted worktree
- the command auto-recovers from the common stopped-VM case
- the command can auto-attach a host-path target when enough information exists
- error output for unresolved mount names is explicit about the next step
- docs and help text match the new primary workflow
- shell tests lock the behavior so the UX regression does not return
