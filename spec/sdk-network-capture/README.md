# SDK Network Capture Spec

## Goal

Capture most app HTTP traffic inside Remo-enabled iOS apps in debug builds, without needing to know the app's higher-level networking wrapper.

## Recommended Approach

Use a hybrid model:

- `URLProtocol` for broad interception of `URLSession`-based traffic
- `URLSessionTaskMetrics` for timing fidelity

This is the closest Remo analogue to how Chrome DevTools observes browser traffic from inside the browser stack rather than through an external proxy.

## Capture Model

### Request Observation

- Intercept most `URLSession` requests made by the app in debug builds.
- Support wrappers built on top of `URLSession`, including common cases like Alamofire.
- Assign a stable `request_id` for every observed request.
- Emit lifecycle events for start, redirect, response, finish, and failure.

### Request And Response Data

- Capture method, URL, host, path, query, and headers.
- Capture request and response body metadata.
- Capture bounded body previews when content type and size are safe.
- Capture response status, response headers, MIME type, and content length when available.

### Timing

- Attach timing metrics to the same `request_id`.
- Support total duration and timing breakdowns when provided by `URLSessionTaskMetrics`.
- Preserve redirect timing and retry visibility when possible.

### Context

- Attach device ID, app session ID, and trace markers when available.
- Allow later correlation with Remo capability invocations or action markers.

## Constraints

- Debug builds only
- Read-only inspection only
- Best-effort coverage outside `URLSession` is not guaranteed
- Streaming and very large bodies are not first-class in v1

## Design Risks

- Some third-party SDKs may bypass the interception path.
- Redirects and retries can be misinterpreted if request identity is not modeled carefully.
- Body capture can become expensive or unsafe without strict limits.

## Engineering Guardrails

- Keep body capture size-limited.
- Redact obvious secrets before data leaves the app.
- Prefer partial but correct records over blocking or breaking app traffic.
- If capture or metrics fail, app networking should continue normally.

## Deferred Design

The following are intentionally out of scope for this spec:

- daemon-side storage and indexing
- agent query APIs
- human inspection UI
- device-wide capture or MITM proxy behavior
