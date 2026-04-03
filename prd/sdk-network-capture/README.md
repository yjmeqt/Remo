# SDK Network Capture

## Purpose

Capture most app HTTP traffic inside Remo-enabled iOS apps without requiring app-specific knowledge of higher-level networking wrappers.

## Why It Matters

Today Remo can observe UI state, screenshots, and capability calls, but it cannot tell an agent what network activity happened after an action. That makes it hard to distinguish:

- UI rendering bugs
- backend failures
- auth issues
- response contract drift
- performance bottlenecks

## Product Scope

- Debug-only
- App-scoped
- Read-only
- Optimized for most `URLSession` traffic
- Not a device-wide proxy

## Requirements

- Intercept most `URLSession` requests made by the app in debug builds.
- Work regardless of whether the app uses raw `URLSession`, Alamofire, or other wrappers built on top of `URLSession`.
- Capture enough request, response, and timing data to support debugging.
- Preserve a stable request identity so later systems can query and correlate network activity.
- Keep runtime overhead low enough for normal development use.

## Success Criteria

- Most app HTTP traffic appears without app-specific instrumentation.
- Agents and developers can tell which request failed or became slow after an action.
- Capture overhead is low enough for routine development use.

## Out Of Scope

- Device-wide traffic capture
- MITM proxying
- Replay, blocking, or throttling requests
- Full daemon/query/UI design

## Related Technical Design

- [SDK Network Capture Spec](../../spec/sdk-network-capture/README.md)
