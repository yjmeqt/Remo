# Remo Network Trace PRD

## Summary

Remo Network Trace is an agent-first network inspection product for Remo-enabled iOS apps. The current PRD scope is intentionally limited to SDK-side network capture.

Product docs in `/prd` stay high-level. Technical design details live in `/spec`.

## Current Scope

- Capture most app HTTP/HTTPS traffic that flows through `URLSession`.
- Work without app-specific knowledge of higher-level wrappers like Alamofire.
- Produce structured request lifecycle signals for later agent and UI use.
- Keep capture debug-only and read-only.

## Current Non-Goals

- Device-wide traffic capture
- MITM proxying
- Replay, blocking, or throttling requests
- Daemon trace storage, agent APIs, and UI in this phase

## Functional Breakdown

| Area | Product Goal | PRD | Spec |
|---|---|---|
| SDK Network Capture | Observe app network activity inside Remo-enabled apps | [sdk-network-capture/README.md](./sdk-network-capture/README.md) | [../spec/sdk-network-capture/README.md](../spec/sdk-network-capture/README.md) |

## Target Users

- AI agents using Remo to build, test, and debug iOS apps
- iOS developers debugging Remo-enabled apps

## Product Principles

- Agent-first: capture should be structured so later agent APIs are possible
- App-aware: capture should fit Remo-enabled apps, not generic proxy workflows
- Honest coverage: optimize for most app HTTP traffic, not all device traffic
- Debug-safe: debug-only and low-friction for development
- Reusable foundation: later daemon and UI work should build on this capture model

## Next Likely Expansion

- Define the normalized network event schema
- Decide how the daemon should ingest and retain request records
- Add agent workflows for trace retrieval and comparison
- Add a thin human inspection UI once the underlying model is stable
