# Remo Skills

AI agent skills that give coding agents eyes and hands for iOS development.

## Skills

| Skill | Type | Purpose | When to use |
|-------|------|---------|-------------|
| [`remo-setup`](remo-setup/SKILL.md) | Rigid, one-time | Integrate Remo SDK | First time adding Remo to a project |
| [`remo-capabilities`](remo-capabilities/SKILL.md) | Rigid, periodic | Map features → register capabilities → document | After setup, or when features change |
| [`remo`](remo/SKILL.md) | Flexible, ongoing | Verified development workflow with timeline reports | Every task — verify, debug, test, explore |
| [`remo-design-review`](remo-design-review/SKILL.md) | Rigid, periodic | Compare app against Figma designs | Before release, after UI changes, design QA |

## How They Fit Together

```
remo-setup              One-time: add SDK, wire Remo.start(), verify connection
    ↓
remo-capabilities       Periodic: explore app → register capabilities → write capabilities.md
    ↓
remo                    Ongoing: baseline → [code → build → checkpoint] → report
    ↓
remo-design-review      Periodic: Figma → state setup → screenshot → compare → compliance report
    ↑                            ↑
    └── feeds back ──────────────┘  (missing capabilities → TODO → implement → re-review)
```

## Artifacts

```
.remo/
├── bin/                               # Project-local CLI binary (remo-setup)
│   └── remo
├── capabilities.md                    # Capabilities reference (remo-capabilities)
├── verifications/                     # Verification reports (remo)
│   └── <task-id>/
│       ├── report.md
│       └── assets/
└── design-reviews/                    # Design compliance reports (remo-design-review)
    └── <review-id>/
        ├── report.md
        └── assets/
            ├── figma/                 # Design screenshots from Figma
            └── app/                   # App screenshots from Remo
```

## Installation

Skills are installed **per-repo** — each iOS project gets its own copy in `.claude/skills/`.

```bash
# From your iOS project root
mkdir -p .claude/skills
cp -R /path/to/Remo/skills/remo-setup .claude/skills/
cp -R /path/to/Remo/skills/remo-capabilities .claude/skills/
cp -R /path/to/Remo/skills/remo .claude/skills/
cp -R /path/to/Remo/skills/remo-design-review .claude/skills/
```

<!-- TODO: Automate skill installation — options: `remo init` CLI command, or dedicated install script that copies skills to `.claude/skills/` -->

## CLI Reference

Each skill folder is self-contained and ships its own `references/cli.md`.

- Start with [`remo-setup/references/cli.md`](remo-setup/references/cli.md) for the broadest onboarding guide
- Use the `references/cli.md` inside the specific skill you are running for command syntax and caveats that matter to that workflow

## Requirements

- **Remo CLI** — installed project-locally to `.remo/bin/remo` by `remo-setup`, or globally via `brew install yjmeqt/tap/remo`
- **iOS project** that builds and runs on a simulator
- **Remo SDK** integrated into the app (use `remo-setup` skill if not yet done)
- **Figma MCP server** configured (for `remo-design-review` only)
