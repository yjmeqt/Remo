# Website pnpm Migration Design

## Goal

Migrate the `website/` package from `npm` to `pnpm`, while establishing a lightweight repository-level package manager convention that can scale to future JavaScript/TypeScript packages without turning the repository into a heavy JS monorepo.

## Context

The repository is primarily Rust and Swift, with a single frontend package at `website/`. Today the website uses `npm` with a local `package-lock.json`, and the deploy workflow also assumes `npm`.

The migration should improve package-management ergonomics and make future JS/TS expansion straightforward, but it should not introduce unnecessary tooling such as a task runner or root-level monorepo orchestration.

## Options Considered

### 1. Minimal website-only migration

Replace `npm` with `pnpm` only inside `website/`, update the website docs and CI, and stop there.

Pros:
- Lowest migration cost.
- Smallest change surface.

Cons:
- Does not establish a repository-wide convention.
- Future JS/TS packages would reopen the same package-manager decision.

### 2. Recommended: lightweight repository standard

Migrate `website/` to `pnpm` and add the minimum repository-level pnpm conventions:
- root `pnpm-workspace.yaml`
- root `packageManager` declaration
- workspace currently containing only `website`

Pros:
- Solves the current migration.
- Establishes a clear future default for JS/TS packages.
- Keeps the repository lightweight.

Cons:
- Slightly more change than a website-only migration.

### 3. Full JS monorepo standardization

Add root `package.json`, workspace scripts, and broader monorepo structure around pnpm.

Pros:
- Maximum future flexibility.

Cons:
- Over-designed for a repo whose core is not JS.
- Adds maintenance and conceptual overhead now without immediate benefit.

## Recommended Design

Adopt option 2.

The repository will treat `pnpm` as the standard package manager for JavaScript/TypeScript packages, but only introduce the smallest shared structure needed today. The `website/` package keeps its current scripts and Vite-based structure. The migration changes how dependencies are installed and cached, not how the website is architected.

## File and Tooling Changes

### Root-level conventions

Add `pnpm-workspace.yaml` at the repository root with `website` as the only workspace member for now.

Add a root-level package-manager declaration so local development and CI use a consistent pnpm version. This should be lightweight and should not require introducing root JS scripts unless they provide clear value.

### Website package

Delete `website/package-lock.json` and generate `pnpm-lock.yaml`.

Keep `website/package.json` scripts unchanged (`dev`, `build`, `lint`, `preview`) so existing developer workflows map directly to pnpm equivalents.

### Documentation

Update all user-facing website instructions from `npm` to `pnpm`, including:
- `website/README.md`
- any relevant root README sections

Commands should reflect the new standard clearly:
- `pnpm install`
- `pnpm dev`
- `pnpm build`

Where commands are run from the repository root, use explicit workspace-aware pnpm forms.

### CI

Update `.github/workflows/deploy-website.yml` to use pnpm instead of npm:
- install pnpm
- enable dependency caching for pnpm
- install dependencies with a frozen lockfile
- run the website build with pnpm

The CI change should be aligned with the lockfile migration so the workflow remains deterministic.

## Non-Goals

- No Turborepo, Nx, or similar orchestration layer.
- No root-level JS task runner unless needed later.
- No migration of non-JS parts of the repository.
- No restructuring of the website source layout.

## Risks

- CI may silently keep npm assumptions if the workflow is only partially updated.
- A root-level pnpm convention without clear docs may confuse contributors if commands are split between root and `website/`.
- Adding too much root JS structure now would create maintenance overhead with little benefit.

## Validation

The migration is complete when:

1. Dependency install works with pnpm.
2. The website builds successfully using pnpm commands.
3. The website deploy workflow is updated to use pnpm and the new lockfile.
4. Repository docs consistently point contributors to pnpm rather than npm for website development.
