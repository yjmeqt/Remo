//! Integration tests for the remo-daemon HTTP API using axum's tower::ServiceExt::oneshot.
//! No actual TCP binding is needed — requests are dispatched directly through the router.

use std::sync::Arc;

use axum::body::Body;
use http::Request;
use remo_daemon::api::{self, ApiState};
use remo_daemon::connection_pool::ConnectionPool;
use remo_daemon::event_bus::EventBus;
use remo_daemon::types::DeviceState;
use remo_desktop::DeviceId;
use serde_json::{json, Value};
use tower::ServiceExt;

/// Build a fresh `ApiState` with an empty pool, a 100-slot event bus, and no
/// webhooks.
fn test_state() -> Arc<ApiState> {
    Arc::new(ApiState {
        pool: Arc::new(ConnectionPool::new()),
        event_bus: Arc::new(EventBus::new(100)),
        webhooks: Arc::new(std::sync::Mutex::new(Vec::new())),
    })
}

/// Helper: read a response body into a `serde_json::Value`.
async fn body_json(resp: http::Response<Body>) -> Value {
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .expect("failed to read response body");
    serde_json::from_slice(&bytes).expect("response body is not valid JSON")
}

#[tokio::test]
async fn status_endpoint_returns_running() {
    let state = test_state();
    let app = api::router(state);

    let req = Request::builder()
        .uri("/status")
        .body(Body::empty())
        .unwrap();

    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), 200);

    let json = body_json(resp).await;
    assert_eq!(json["status"], "running");
    assert_eq!(json["devices"], 0);
    assert_eq!(json["connected"], 0);
}

#[tokio::test]
async fn poll_events_returns_emitted_events() {
    let state = test_state();

    // Emit two events before making the request.
    state.event_bus.emit(
        "device_connected",
        Some("usb:1".into()),
        json!({"port": 1234}),
    );
    state
        .event_bus
        .emit("capability_called", None, json!({"name": "screenshot"}));

    let app = api::router(state);

    let req = Request::builder()
        .uri("/events?since=0&limit=10")
        .body(Body::empty())
        .unwrap();

    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), 200);

    let json = body_json(resp).await;
    let events = json["events"]
        .as_array()
        .expect("events should be an array");
    assert_eq!(events.len(), 2);
    assert_eq!(events[0]["kind"], "device_connected");
    assert_eq!(events[1]["kind"], "capability_called");
    // next_cursor should equal the seq of the last event (2).
    assert_eq!(json["next_cursor"], 2);
}

#[tokio::test]
async fn call_without_connected_device_returns_503() {
    let state = test_state();
    let app = api::router(state);

    let req = Request::builder()
        .method("POST")
        .uri("/call")
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&json!({
                "capability": "test",
                "params": {}
            }))
            .unwrap(),
        ))
        .unwrap();

    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), 503);

    let json = body_json(resp).await;
    assert!(
        json["error"].as_str().unwrap().contains("no device"),
        "error message should mention no device: {:?}",
        json["error"]
    );
}

#[tokio::test]
async fn devices_endpoint_lists_pool_entries() {
    let state = test_state();

    // Add a device to the pool.
    state.pool.set_state(
        DeviceId::Bonjour("TestDevice".to_string()),
        DeviceState::Connected,
    );

    let app = api::router(state);

    let req = Request::builder()
        .uri("/devices")
        .body(Body::empty())
        .unwrap();

    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), 200);

    let json = body_json(resp).await;
    let devices = json.as_array().expect("response should be an array");
    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0]["id"], "bonjour:TestDevice");
    assert_eq!(devices[0]["state"], "connected");
}
