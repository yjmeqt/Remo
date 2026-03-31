# Website Single-Package pnpm Migration Design

## Goal

Migrate the `website/` package from `npm` to `pnpm` as a single-package setup, keeping all JavaScript package-management files inside `website/` and avoiding repository-root pnpm workspace metadata.

## Context

The repository is primarily Rust and Swift, with a single frontend package at `website/`. Today the website uses `npm` with a local `package-lock.json`, and the deploy workflow also assumes `npm`.

The migration should improve package-management ergonomics, but it should also respect the current repository boundary: JavaScript code exists only under `website/`. The migration should therefore avoid introducing root pnpm workspace files or a repository-wide JS package-management layer.

## Options Considered

### 1. Recommended: single-package pnpm migration

Replace `npm` with `pnpm` only inside `website/`, keep the lockfile inside `website/`, and update website docs and CI accordingly.

Pros:
- Matches the repository boundary cleanly.
- Keeps all JS package-management files with the only JS package.
- Lowest long-term confusion for contributors.

Cons:
- If another JS package is added later, a workspace migration may be needed then.

### 2. Lightweight repository workspace standard

Migrate `website/` to `pnpm` and add the minimum repository-level pnpm conventions:
- root `pnpm-workspace.yaml`
- root lockfile
- `website/package.json` package-manager declaration

Pros:
- Makes future multi-package expansion easier.

Cons:
- Introduces root-level pnpm files even though JS only exists under `website/`.
- Blurs the boundary between the Rust/Swift repository root and the website package.

### 3. Full JS monorepo standardization

Add root JS manifests, workspace scripts, and broader monorepo structure around pnpm.

Pros:
- Maximum future flexibility.

Cons:
- Over-designed for a repo whose core is not JS.
- Adds maintenance and conceptual overhead now without immediate benefit.

## Recommended Design

Adopt option 1.

The migration should be package-local. `website/` keeps its current scripts and Vite-based structure, but switches to `pnpm` with a lockfile stored inside `website/`. The repository root should not gain pnpm workspace metadata. The migration changes dependency installation and CI commands, not the website architecture.

## File and Tooling Changes

### Root-level conventions

Do not add `pnpm-workspace.yaml`, a root lockfile, or a root JS manifest. Keep pnpm metadata out of the repository root.

### Website package

Delete `website/package-lock.json` and generate `website/pnpm-lock.yaml`.

Keep `website/package.json` scripts unchanged (`dev`, `build`, `lint`, `preview`) so existing developer workflows map directly to pnpm equivalents. Add the `packageManager` declaration there if version pinning is needed.

### Documentation

Update all user-facing website instructions from `npm` to `pnpm`, including:
- `website/README.md`
- any relevant root README sections

Commands should reflect the new standard clearly:
- `cd website && pnpm install`
- `cd website && pnpm dev`
- `cd website && pnpm build`

### CI

Update `.github/workflows/deploy-website.yml` to use pnpm instead of npm:
- install pnpm
- enable dependency caching for pnpm
- install dependencies in `website/` with a frozen lockfile
- run the website build in `website/`

The CI change should be aligned with the lockfile migration so the workflow remains deterministic.

## Non-Goals

- No Turborepo, Nx, or similar orchestration layer.
- No root-level JS task runner unless needed later.
- No migration of non-JS parts of the repository.
- No restructuring of the website source layout.

## Risks

- CI may silently keep npm assumptions if the workflow is only partially updated.
- Mixing root-level pnpm files with a single-package layout would confuse contributors about where JS package management actually lives.
- If CI still assumes a root lockfile, installs will become nondeterministic or fail.

## Validation

The migration is complete when:

1. `cd website && pnpm install` works.
2. The website builds successfully with `cd website && pnpm build`.
3. The website deploy workflow uses pnpm inside `website/` and points at `website/pnpm-lock.yaml`.
4. Repository docs consistently point contributors to pnpm rather than npm for website development.
