use std::sync::Arc;

use remo_objc::ObjcBridge;
use serde_json::json;

use crate::registry::CapabilityRegistry;

/// Register the built-in system capabilities and ObjC-bridge capabilities.
pub fn register_builtins(registry: &mut CapabilityRegistry, bridge: Arc<dyn ObjcBridge>) {
    // --- System ---

    registry.register("_ping", "Health check", |_| async move {
        Ok(json!({ "pong": true }))
    });

    // --- UI Navigation ---

    let bridge_nav = bridge.clone();
    registry.register("ui.navigate", "Navigate to a page", move |params| {
        let b = bridge_nav.clone();
        async move {
            let page = params
                .get("page")
                .and_then(|v| v.as_str())
                .ok_or("missing 'page' param")?;
            b.navigate_to(page)?;
            let current = b.current_page()?;
            Ok(json!({ "navigated_to": current }))
        }
    });

    let bridge_page = bridge.clone();
    registry.register("ui.current_page", "Get current page", move |_| {
        let b = bridge_page.clone();
        async move {
            let page = b.current_page()?;
            Ok(json!({ "page": page }))
        }
    });

    // --- UI Inspection ---

    let bridge_inspect = bridge.clone();
    registry.register(
        "ui.inspect",
        "Get view hierarchy tree",
        move |_| {
            let b = bridge_inspect.clone();
            async move {
                let tree = b.view_hierarchy()?;
                serde_json::to_value(tree).map_err(|e| e.to_string())
            }
        },
    );

    let bridge_classes = bridge.clone();
    registry.register(
        "runtime.classes",
        "List ObjC runtime classes",
        move |_| {
            let b = bridge_classes.clone();
            async move {
                let classes = b.list_classes()?;
                Ok(json!({ "classes": classes }))
            }
        },
    );

    let bridge_msg = bridge.clone();
    registry.register(
        "runtime.send_message",
        "Send ObjC message to an object",
        move |params| {
            let b = bridge_msg.clone();
            async move {
                let target = params
                    .get("target")
                    .and_then(|v| v.as_str())
                    .ok_or("missing 'target'")?
                    .to_string();
                let selector = params
                    .get("selector")
                    .and_then(|v| v.as_str())
                    .ok_or("missing 'selector'")?
                    .to_string();
                let args: Vec<serde_json::Value> = params
                    .get("args")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                b.send_message(&target, &selector, args)
            }
        },
    );

    // --- Store ---

    let bridge_get = bridge.clone();
    registry.register("store.get", "Get a value from the store", move |params| {
        let b = bridge_get.clone();
        async move {
            let key = params
                .get("key")
                .and_then(|v| v.as_str())
                .ok_or("missing 'key'")?;
            let value = b.get_store_value(key)?;
            Ok(json!({ "key": key, "value": value }))
        }
    });

    let bridge_set = bridge.clone();
    registry.register("store.set", "Set a value in the store", move |params| {
        let b = bridge_set.clone();
        async move {
            let key = params
                .get("key")
                .and_then(|v| v.as_str())
                .ok_or("missing 'key'")?
                .to_string();
            let value = params
                .get("value")
                .cloned()
                .ok_or("missing 'value'")?;
            b.set_store_value(&key, value)?;
            Ok(json!({ "success": true, "key": key }))
        }
    });

    let bridge_list = bridge.clone();
    registry.register("store.list", "List all store entries", move |_| {
        let b = bridge_list.clone();
        async move {
            let entries = b.list_store()?;
            serde_json::to_value(entries).map_err(|e| e.to_string())
        }
    });
}
