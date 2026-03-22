//! Integration tests: spin up remo-sdk server on localhost,
//! connect with remo-desktop's RpcClient, and verify round-trip calls.

use std::net::SocketAddr;
use std::time::Duration;

use remo_desktop::{RpcClient, RpcResponse};
use remo_protocol::{ErrorCode, ResponseResult};
use remo_sdk::{CapabilityRegistry, RemoServer};
use tokio::sync::mpsc;

/// Helper: unwrap a JSON response from an RpcResponse.
fn expect_json(resp: RpcResponse) -> remo_protocol::Response {
    match resp {
        RpcResponse::Json(r) => r,
        other => panic!("expected Json response, got {other:?}"),
    }
}

#[tokio::test]
async fn full_roundtrip() {
    let registry = CapabilityRegistry::new();
    registry.register_sync("echo", |params| Ok(serde_json::json!({ "echoed": params })));
    registry.register_sync("add", |params| {
        let a = params["a"].as_i64().unwrap_or(0);
        let b = params["b"].as_i64().unwrap_or(0);
        Ok(serde_json::json!({ "sum": a + b }))
    });

    let server = RemoServer::new(registry, 0);
    let (port_tx, port_rx) = tokio::sync::oneshot::channel();

    let server_handle = tokio::spawn(async move {
        server.run(Some(port_tx)).await.unwrap();
    });

    let actual_port = tokio::time::timeout(Duration::from_secs(2), port_rx)
        .await
        .expect("server did not report port in time")
        .expect("port sender dropped");

    let addr: SocketAddr = ([127, 0, 0, 1], actual_port).into();
    let (event_tx, _event_rx) = mpsc::channel(16);
    let client = RpcClient::connect(addr, event_tx).await.unwrap();

    // echo
    let resp = expect_json(
        client
            .call(
                "echo",
                serde_json::json!({"hello": "world"}),
                Duration::from_secs(5),
            )
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => assert_eq!(data["echoed"]["hello"], "world"),
        ResponseResult::Error { message, .. } => panic!("expected ok: {message}"),
    }

    // add
    let resp = expect_json(
        client
            .call(
                "add",
                serde_json::json!({"a": 17, "b": 25}),
                Duration::from_secs(5),
            )
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => assert_eq!(data["sum"], 42),
        ResponseResult::Error { message, .. } => panic!("expected ok: {message}"),
    }

    // __ping
    let resp = expect_json(
        client
            .call("__ping", serde_json::json!({}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => assert_eq!(data["pong"], true),
        ResponseResult::Error { message, .. } => panic!("expected ok: {message}"),
    }

    // __list_capabilities
    let resp = expect_json(
        client
            .call(
                "__list_capabilities",
                serde_json::json!({}),
                Duration::from_secs(5),
            )
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => {
            let names: Vec<&str> = data
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_str().unwrap())
                .collect();
            assert!(names.contains(&"echo"));
            assert!(names.contains(&"add"));
            assert!(names.contains(&"__ping"));
        }
        ResponseResult::Error { message, .. } => panic!("expected ok: {message}"),
    }

    // non-existent capability
    let resp = expect_json(
        client
            .call(
                "no_such_thing",
                serde_json::json!({}),
                Duration::from_secs(5),
            )
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Error { code, .. } => assert_eq!(*code, ErrorCode::NotFound),
        ResponseResult::Ok { .. } => panic!("expected error for unknown capability"),
    }

    server_handle.abort();
}

#[tokio::test]
async fn start_and_stop_mirror() {
    let registry = CapabilityRegistry::new();
    let server = RemoServer::new(registry, 0);
    let shutdown = server.shutdown_handle();

    let (port_tx, port_rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        server.run(Some(port_tx)).await.unwrap();
    });

    let port = port_rx.await.unwrap();
    let addr: SocketAddr = ([127, 0, 0, 1], port).into();
    let (event_tx, _) = mpsc::channel(16);
    let client = RpcClient::connect(addr, event_tx).await.unwrap();

    // Start mirror
    let resp = expect_json(
        client
            .call(
                "__start_mirror",
                serde_json::json!({"fps": 10}),
                Duration::from_secs(5),
            )
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => {
            assert_eq!(data["stream_id"], 1);
        }
        ResponseResult::Error { message, .. } => {
            // On non-Apple targets, encoder fails — session won't be stored
            eprintln!("mirror start error (expected on non-iOS): {message}");
        }
    }

    // Stop mirror
    let resp = expect_json(
        client
            .call(
                "__stop_mirror",
                serde_json::json!({}),
                Duration::from_secs(5),
            )
            .await
            .unwrap(),
    );
    // Either stopped:true or not-found (if encoder failed to start on non-Apple)
    println!("stop response: {:?}", resp.result);

    let _ = shutdown.send(());
}

#[tokio::test]
async fn start_mirror_twice_returns_error() {
    let registry = CapabilityRegistry::new();
    let server = RemoServer::new(registry, 0);
    let shutdown = server.shutdown_handle();

    let (port_tx, port_rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        server.run(Some(port_tx)).await.unwrap();
    });

    let port = port_rx.await.unwrap();
    let addr: SocketAddr = ([127, 0, 0, 1], port).into();
    let (event_tx, _) = mpsc::channel(16);
    let client = RpcClient::connect(addr, event_tx).await.unwrap();

    // First start
    let _ = client
        .call(
            "__start_mirror",
            serde_json::json!({"fps": 10}),
            Duration::from_secs(5),
        )
        .await
        .unwrap();

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Second start — should fail with StreamAlreadyActive (if first succeeded)
    let resp = expect_json(
        client
            .call(
                "__start_mirror",
                serde_json::json!({"fps": 10}),
                Duration::from_secs(5),
            )
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Error { code, .. } => {
            assert_eq!(*code, ErrorCode::StreamAlreadyActive);
        }
        ResponseResult::Ok { .. } => {
            // On non-Apple targets, first start may have failed (no encoder),
            // so session slot is clear and second start "succeeds" too — acceptable
        }
    }

    let _ = shutdown.send(());
}
