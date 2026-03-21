use std::sync::Arc;

use remo_agent::handler::register_builtins;
use remo_agent::registry::CapabilityRegistry;
use remo_agent::server::AgentServer;
use remo_objc::MockBridge;
use serde_json::json;

mod session {
    // Re-include session module for testing
    include!("../src/session.rs");
}
use session::DeviceSession;

async fn start_agent() -> (std::net::SocketAddr, tokio::task::JoinHandle<()>) {
    let bridge = Arc::new(MockBridge::new());
    let mut registry = CapabilityRegistry::new();
    register_builtins(&mut registry, bridge);
    registry.register("echo", "Echo back", |p| async move { Ok(p) });

    let server = AgentServer::bind("127.0.0.1:0", registry)
        .await
        .unwrap();
    let addr = server.local_addr();
    let handle = tokio::spawn(async move {
        let _ = server.run().await;
    });
    (addr, handle)
}

#[tokio::test]
async fn test_full_roundtrip() {
    let (addr, handle) = start_agent().await;

    let session = DeviceSession::connect(addr).await.unwrap();
    assert_eq!(session.peer_version, remo_core::PROTOCOL_VERSION);

    // Capabilities from initial event
    assert!(!session.initial_capabilities.is_empty());

    // List capabilities via request
    let caps = session.list_capabilities().await.unwrap();
    let names: Vec<_> = caps.iter().map(|c| c.name.as_str()).collect();
    assert!(names.contains(&"_ping"));
    assert!(names.contains(&"echo"));
    assert!(names.contains(&"ui.navigate"));
    assert!(names.contains(&"store.get"));

    // Ping
    let pong = session.call("_ping", json!(null)).await.unwrap();
    assert_eq!(pong, json!({"pong": true}));

    // Echo
    let echo = session.call("echo", json!({"x": 42})).await.unwrap();
    assert_eq!(echo, json!({"x": 42}));

    // Navigate
    let nav = session
        .call("ui.navigate", json!({"page": "settings"}))
        .await
        .unwrap();
    assert_eq!(nav["navigated_to"], "settings");

    // Current page
    let page = session.call("ui.current_page", json!(null)).await.unwrap();
    assert_eq!(page["page"], "settings");

    // Store get
    let val = session
        .call("store.get", json!({"key": "user_name"}))
        .await
        .unwrap();
    assert_eq!(val["value"], "Alice");

    // Store set
    let _ = session
        .call("store.set", json!({"key": "user_name", "value": "Charlie"}))
        .await
        .unwrap();

    // Verify set
    let val2 = session
        .call("store.get", json!({"key": "user_name"}))
        .await
        .unwrap();
    assert_eq!(val2["value"], "Charlie");

    // Store list
    let store = session.call("store.list", json!(null)).await.unwrap();
    assert!(store.as_array().unwrap().len() >= 4);

    // View hierarchy
    let tree = session.call("ui.inspect", json!(null)).await.unwrap();
    assert_eq!(tree["class_name"], "UIWindow");

    // Runtime classes
    let classes = session
        .call("runtime.classes", json!(null))
        .await
        .unwrap();
    let class_list = classes["classes"].as_array().unwrap();
    assert!(class_list.iter().any(|c| c == "UIView"));

    // Error case: invalid page
    let err = session
        .call("ui.navigate", json!({"page": "nonexistent"}))
        .await;
    assert!(err.is_err());

    handle.abort();
}

#[tokio::test]
async fn test_concurrent_requests() {
    let (addr, handle) = start_agent().await;
    let session = Arc::new(DeviceSession::connect(addr).await.unwrap());

    let mut tasks = Vec::new();
    for i in 0..10 {
        let s = session.clone();
        tasks.push(tokio::spawn(async move {
            let result = s.call("echo", json!({"i": i})).await.unwrap();
            assert_eq!(result["i"], i);
        }));
    }

    for t in tasks {
        t.await.unwrap();
    }

    handle.abort();
}
