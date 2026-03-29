# Remo CLI Docs

This file is the repository-maintainer guide for Remo CLI documentation.

## Source of Truth

The distributed, user-facing CLI guidance lives in the per-skill references:

- [`../skills/remo-setup/references/cli.md`](../skills/remo-setup/references/cli.md)
- [`../skills/remo/references/cli.md`](../skills/remo/references/cli.md)
- [`../skills/remo-capabilities/references/cli.md`](../skills/remo-capabilities/references/cli.md)
- [`../skills/remo-design-review/references/cli.md`](../skills/remo-design-review/references/cli.md)

There is no longer a single shared `skills/cli-reference.md`. This is intentional so every distributed skill folder stays self-contained.

## What This File Covers

Use this file when maintaining the repository to keep the CLI docs surface aligned across:

- [`../skills/remo-setup/references/cli.md`](../skills/remo-setup/references/cli.md)
- [`../skills/remo/references/cli.md`](../skills/remo/references/cli.md)
- [`../skills/remo-capabilities/references/cli.md`](../skills/remo-capabilities/references/cli.md)
- [`../skills/remo-design-review/references/cli.md`](../skills/remo-design-review/references/cli.md)
- [`../skills/README.md`](../skills/README.md)
- [`../skills/remo-setup/SKILL.md`](../skills/remo-setup/SKILL.md)
- [`../skills/remo/SKILL.md`](../skills/remo/SKILL.md)
- [`../skills/remo-capabilities/SKILL.md`](../skills/remo-capabilities/SKILL.md)
- [`../skills/remo-design-review/SKILL.md`](../skills/remo-design-review/SKILL.md)
- [`../README.md`](../README.md)
- [`../AGENTS.md`](../AGENTS.md)

## Update Checklist

Whenever the CLI changes, update all of the following as needed:

1. Command list and examples for any newly added, removed, or renamed command
2. Option names, defaults, and flag spellings
3. Connection semantics for `--addr` and `--device`
4. Output behavior for `screenshot`, `tree`, `watch`, and `mirror`
5. Daemon-related behavior for `dashboard`, `start`, `stop`, and `status`
6. Known caveats, especially user-visible ones such as `mirror --save` timing limitations

## Current Known Caveat Worth Preserving

`remo mirror --save` currently writes fixed per-frame sample durations in the MP4 muxer, which compresses idle periods and can make the saved video shorter than wall-clock time. Keep this caveat documented in the distributed CLI reference and any skill that recommends `mirror --save`.
