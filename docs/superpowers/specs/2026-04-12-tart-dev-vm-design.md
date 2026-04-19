# Tart Dev VM Design

## Goal

Provide a repeatable Tart-based macOS development environment for Remo that is fast to reuse, easy to attach to any Remo worktree, and isolated enough that one worktree does not trample another worktree's build outputs or caches.

The environment must support Remo's real development workflow, not just Rust compilation. That includes Xcode, simulator-oriented iOS builds, Rust, `cbindgen`, `npm`, and the OpenAI Codex CLI.

## Scope

- Add repository-owned scripts and documentation for creating and reusing a Tart development VM.
- Use one shared VM per project, not one VM per worktree.
- Allow multiple worktrees from the same project to be mounted into the same VM at distinct paths.
- Isolate worktree-local derived data, build products, caches, and temp files.
- Support validation against the current Remo build workflow, including `cargo check --workspace` and `./build-ios.sh sim`.

## Non-Goals

- Manage Tart installation on the host machine.
- Build a custom base image pipeline or publish a team image registry in this first iteration.
- Automatically authenticate Codex, copy host credentials, or manage OpenAI secrets.
- Provide full machine isolation between worktrees in the same project VM.
- Solve CI provisioning. This design is for local development first.

## Constraints

- Remo development requires more than a Rust toolchain. The VM must support Xcode-driven iOS and simulator builds.
- The repository already defines Rust targets in `rust-toolchain.toml`; the VM should align with that file instead of inventing its own target list.
- Worktree isolation matters for `DerivedData`, Cargo outputs, npm cache state, and temporary files.
- The repository should remain source-only. Tart VM disk images should not live inside a worktree.

## Recommended Model

### VM topology

Use one shared Tart VM per project.

Examples:

- `Remo` gets one VM.
- Project `A` gets one VM.
- Project `B` gets one VM.

Inside a given project VM, mount multiple project worktrees at the same time under separate shared-directory paths.

For Remo, guest-visible paths might look like:

- `/Volumes/My Shared Files/remo-main`
- `/Volumes/My Shared Files/remo-tart-vm`
- `/Volumes/My Shared Files/remo-feature-x`

This gives project-level environment reuse while keeping worktree source paths distinct.

Because Tart directory shares are attached at run time, not stored permanently in VM configuration, adding a new worktree mount to an already-running project VM requires a restart. The tooling should make this explicit and persist a small host-side mount manifest so later boots can re-attach the full known set of project worktrees.

### Why not one VM per worktree

One VM per worktree gives stronger isolation, but it is the wrong default for this project because it duplicates Xcode, Rust caches, and provisioned tools across large VM disks. It also makes branch switching expensive and raises local disk usage significantly.

### Why not place the VM inside the worktree

Tart VM disks should remain in Tart's normal storage under the host user's Tart directories. The repository should only contribute scripts, not large VM disk artifacts.

This avoids:

- accidental deletion when removing a worktree
- giant non-source files living next to source code
- polluting source-oriented tools such as search, backup, and sync

## Base Image Strategy

Start from a public Tart macOS image that already includes Xcode.

Default base image:

- `ghcr.io/cirruslabs/macos-tahoe-xcode:26`

The scripts should allow overriding this via environment variable or flag so the project can later pin a specific tag or digest without changing script structure.

This first version should use a public base image plus repository-driven provisioning. If startup cost becomes painful, the same script layout can later evolve into a local pre-provisioned project base image.

## Host Storage Layout

Keep VM storage in Tart's normal host directories:

- local VMs under `~/.tart/vms/`
- OCI image cache under `~/.tart/cache/OCIs/`

The source tree stays on the host in its existing worktree path and is mounted into the guest at runtime. The repository is not copied into the VM disk as part of setup.

The implementation may also keep small host-side project state outside the repository, such as a mount manifest and recent Tart run log, because these are operational artifacts rather than source files.

## Guest Provisioning

Provisioning should be idempotent and safe to re-run.

Required tools and checks:

- verify Xcode is available
- verify or install `rustup`
- install Rust targets from `rust-toolchain.toml`
- verify or install `cbindgen`
- verify or install `node` and `npm`
- install `@openai/codex`
- run `make setup` in the mounted repository

Provisioning logic should live in repository scripts executed inside the guest, rather than being scattered across ad hoc host-side SSH commands.

Guest-side execution should prefer `tart exec` over SSH when the Tart Guest Agent is available. Public non-vanilla Cirrus Labs images already include that agent, so `tart exec` is the preferred transport for provisioning and verification.

If host testing shows that `tart run --no-graphics` does not survive as a plain shell background job, the implementation should use `launchd` to own the long-running Tart process instead of `nohup` or `&`.

## Network and Package Resolution

The guest VM should be treated as a normal networked macOS machine for dependency resolution.

### Public package registries

The default expectation is that public dependency fetches work normally from inside the guest:

- Cargo crates from public registries
- npm packages from public registries
- SwiftPM packages hosted on public Git providers such as GitHub

This means the VM setup may rely on guest-side network access for:

- `cargo check --workspace`
- `npm install` or `npm ci`
- `xcodebuild` resolving SwiftPM dependencies

### SwiftPM behavior

SwiftPM package resolution should happen inside the guest as part of normal Xcode or `xcodebuild` usage.

For scripted builds, the design should prefer a worktree-local derived data path:

- `xcodebuild ... -derivedDataPath <worktree>/.tart/DerivedData`

This keeps `SourcePackages` and other Xcode-derived artifacts scoped to the active worktree instead of a global shared location.

### Private package sources

Private package sources are supported, but guest-local credentials must be configured separately.

Examples:

- HTTPS tokens for private Git hosting
- guest-local SSH keys for private repositories
- npm auth tokens inside the guest

Host credentials must not be copied into the guest automatically.

### Host-local services and registries

If a dependency source lives on the host machine rather than on the public internet, the guest must access it via the host's router-side address on Tart's default NAT network, and the host-side service must be bound to `0.0.0.0`.

This is a special-case path and should be documented as more fragile than normal public internet access.

## Host Prerequisites and Operational Caveats

The repository scripts should assume that Tart itself is already installed on the host, but the documentation must call out the most important host-side caveats.

### Headless and keychain behavior

On macOS 15 and later, Tart may require an existing and unlocked `login.keychain` in order to start VMs successfully. This is a host concern, not a guest provisioning concern.

### Local Network permission prompts

On macOS 15 and later, host-side tools interacting with Tart guests over private IPv4 networking can trigger a Local Network permission prompt on the host.

This does not usually block normal outbound guest access to public package sources, but it can affect host-to-guest or host-local-service workflows and should be documented as a likely troubleshooting point.

## Credential Handling

Do not copy host credentials into the VM automatically.

Codex support in this first version means:

- install the `codex` CLI
- let the user run `codex login` inside the VM, or set `OPENAI_API_KEY` themselves

This keeps the automation shareable and avoids silently materializing user secrets inside guest state.

## Worktree Isolation Model

The worktrees share one project VM, but each worktree gets isolated build and cache directories inside its own source tree.

Each worktree should own a local `.tart/` directory containing:

- `.tart/DerivedData`
- `.tart/cargo-target`
- `.tart/npm-cache`
- `.tart/tmp`

### Cargo

Use:

- `CARGO_TARGET_DIR=<worktree>/.tart/cargo-target`

This prevents `target/` collisions between worktrees in the same VM.

### npm

Use:

- `npm_config_cache=<worktree>/.tart/npm-cache`

This avoids cache cross-talk when switching branches or dependency trees.

### Temporary files

Use:

- `TMPDIR=<worktree>/.tart/tmp`

This keeps project-local temp output and scratch files out of shared guest temp locations.

### Xcode derived data

All scripted validation should use:

- `xcodebuild ... -derivedDataPath <worktree>/.tart/DerivedData`

For Remo specifically, helper scripts should also prefer the same worktree-local `DerivedData` path so iOS builds from different worktrees do not stampede a shared global `~/Library/Developer/Xcode/DerivedData`.

### Isolation boundary

This is worktree-local cache and artifact isolation, not full machine isolation.

Shared across all worktrees in the same project VM:

- Xcode installation
- simulator device set
- user login state
- globally installed CLI tools
- any guest-global directories not explicitly redirected per worktree

## Script Surface

The first iteration should keep the command surface small.

### `scripts/tart/create-dev-vm.sh`

Responsibilities:

- preflight checks on the host
- select or override a base image
- create the project VM if missing
- optionally recreate it
- start the VM
- mount one or more project worktrees
- run guest provisioning
- run verification unless disabled

Expected flags:

- `--name <vm-name>`
- `--base-image <image>`
- `--mount <host-path[:guest-name]>` repeatable
- `--recreate`
- `--no-verify`

Default VM naming should be project-oriented, not worktree-oriented.

For this worktree, the default should be something like `remo-dev`.

### `scripts/tart/provision-dev-vm.sh`

Responsibilities:

- run inside the guest
- install or verify required developer tools
- ensure worktree-local `.tart/` directories exist
- apply the worktree-local environment variables
- run project bootstrap such as `make setup`

### `scripts/tart/ssh-dev-vm.sh`

Responsibilities:

- connect to the running project VM
- optionally select a mounted worktree
- open a shell already pointed at that worktree path with the correct local environment variables exported

### `scripts/tart/destroy-dev-vm.sh`

Responsibilities:

- stop and delete the project VM when explicitly requested

## Verification

Verification should be split into two layers.

### Toolchain verification

Inside the guest, confirm:

- `xcodebuild -version`
- `cargo --version`
- `npm --version`
- `codex --version`
- `cbindgen --version`

### Project verification

Inside the mounted Remo worktree, run:

- `cargo check --workspace`
- `./build-ios.sh sim`

If a target workspace uses remote SwiftPM packages, project verification should also allow an explicit package-resolution check such as:

- `xcodebuild -resolvePackageDependencies ... -derivedDataPath <worktree>/.tart/DerivedData`

These commands should run with worktree-local environment variables so their outputs land in that worktree's `.tart/` directories.

## Current Worktree Trial

After implementation, the first real-world validation should use the current worktree.

Target flow:

1. Run `scripts/tart/create-dev-vm.sh --recreate --mount "$PWD:remo-tart-vm"`.
2. Boot or reuse the project VM.
3. Mount the current worktree into the guest at `/Volumes/My Shared Files/remo-tart-vm`.
4. Provision the guest if needed.
5. Run toolchain verification.
6. Run Remo project verification in this mounted worktree.
7. Enter the VM with `scripts/tart/ssh-dev-vm.sh remo-tart-vm`.

## Risks

- Public base image tags may drift over time if `latest` is used.
- GUI-driven Xcode usage may still default to shared global locations unless helper scripts or local conventions are followed consistently.
- A shared project VM means simulator state and login state are still shared across worktrees.
- Provisioning logic may need adjustment if the public base image changes what it preinstalls.
- Private package sources will fail until guest-local credentials are configured.
- Host-local package registries or services are more fragile than public internet access because they depend on Tart NAT assumptions and host network/privacy settings.
- Headless macOS hosts may fail to start Tart VMs until `login.keychain` is created and unlocked.

## Mitigations

- Allow base image overrides from the start.
- Keep provisioning idempotent and explicit.
- Redirect every high-churn build artifact location per worktree.
- Treat this version as the foundation for a later local project base image if startup time becomes the bottleneck.
- Document the difference between public, private, and host-local package sources.
- Keep guest credentials explicit and opt-in.
- Document the host-side keychain and Local Network troubleshooting steps called out by Tart.
