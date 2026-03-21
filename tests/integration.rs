//! Integration test: spin up an remo-sdk server on localhost,
//! connect with remo-desktop's RpcClient, and verify round-trip calls.

use std::net::SocketAddr;
use std::time::Duration;

use remo_protocol::ResponseResult;
use remo_sdk::{CapabilityRegistry, RemoServer};
use remo_desktop::RpcClient;
use tokio::sync::mpsc;

#[tokio::test]
async fn full_roundtrip() {
    // 1. Set up the registry with test capabilities.
    let registry = CapabilityRegistry::new();
    registry.register_sync("echo", |params| {
        Ok(serde_json::json!({ "echoed": params }))
    });
    registry.register_sync("add", |params| {
        let a = params["a"].as_i64().unwrap_or(0);
        let b = params["b"].as_i64().unwrap_or(0);
        Ok(serde_json::json!({ "sum": a + b }))
    });

    // 2. Start the server on port 0 (OS picks) and get the actual port via oneshot.
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

    // 3. Connect with RPC client.
    let (event_tx, _event_rx) = mpsc::channel(16);
    let client = RpcClient::connect(addr, event_tx).await.unwrap();

    // 4. Test: call "echo"
    let resp = client
        .call("echo", serde_json::json!({"hello": "world"}), Duration::from_secs(5))
        .await
        .unwrap();

    match &resp.result {
        ResponseResult::Ok { data } => {
            assert_eq!(data["echoed"]["hello"], "world");
        }
        ResponseResult::Error { message, .. } => {
            panic!("expected ok, got error: {message}");
        }
    }

    // 5. Test: call "add"
    let resp = client
        .call("add", serde_json::json!({"a": 17, "b": 25}), Duration::from_secs(5))
        .await
        .unwrap();

    match &resp.result {
        ResponseResult::Ok { data } => {
            assert_eq!(data["sum"], 42);
        }
        ResponseResult::Error { message, .. } => {
            panic!("expected ok, got error: {message}");
        }
    }

    // 6. Test: call built-in "__ping"
    let resp = client
        .call("__ping", serde_json::json!({}), Duration::from_secs(5))
        .await
        .unwrap();

    match &resp.result {
        ResponseResult::Ok { data } => {
            assert_eq!(data["pong"], true);
        }
        ResponseResult::Error { message, .. } => {
            panic!("expected ok, got error: {message}");
        }
    }

    // 7. Test: call built-in "__list_capabilities"
    let resp = client
        .call("__list_capabilities", serde_json::json!({}), Duration::from_secs(5))
        .await
        .unwrap();

    match &resp.result {
        ResponseResult::Ok { data } => {
            let names = data.as_array().unwrap();
            let name_strs: Vec<&str> = names.iter().map(|v| v.as_str().unwrap()).collect();
            assert!(name_strs.contains(&"echo"));
            assert!(name_strs.contains(&"add"));
            assert!(name_strs.contains(&"__ping"));
            assert!(name_strs.contains(&"__list_capabilities"));
        }
        ResponseResult::Error { message, .. } => {
            panic!("expected ok, got error: {message}");
        }
    }

    // 8. Test: call non-existent capability
    let resp = client
        .call("no_such_thing", serde_json::json!({}), Duration::from_secs(5))
        .await
        .unwrap();

    match &resp.result {
        ResponseResult::Error { code, .. } => {
            assert_eq!(*code, remo_protocol::ErrorCode::NotFound);
        }
        ResponseResult::Ok { .. } => {
            panic!("expected error for unknown capability");
        }
    }

    server_handle.abort();
}
