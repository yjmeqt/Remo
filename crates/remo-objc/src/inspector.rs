use remo_core::types::{StoreEntry, ViewNode};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::runtime::ObjcRuntime;

/// High-level bridge between Remo protocol and ObjC runtime.
///
/// Implementors provide UI inspection, navigation, and store manipulation.
pub trait ObjcBridge: Send + Sync {
    fn view_hierarchy(&self) -> Result<ViewNode, String>;
    fn navigate_to(&self, page: &str) -> Result<(), String>;
    fn current_page(&self) -> Result<String, String>;
    fn get_store_value(&self, key: &str) -> Result<serde_json::Value, String>;
    fn set_store_value(&self, key: &str, value: serde_json::Value) -> Result<(), String>;
    fn list_store(&self) -> Result<Vec<StoreEntry>, String>;
    fn list_classes(&self) -> Result<Vec<String>, String>;
    fn send_message(
        &self,
        target: &str,
        selector: &str,
        args: Vec<serde_json::Value>,
    ) -> Result<serde_json::Value, String>;
}

/// Mock bridge that simulates an iOS app with in-memory state.
pub struct MockBridge {
    runtime: ObjcRuntime,
    current_page: Arc<Mutex<String>>,
    store: Arc<Mutex<HashMap<String, serde_json::Value>>>,
}

impl MockBridge {
    pub fn new() -> Self {
        let mut store = HashMap::new();
        store.insert("user_name".into(), serde_json::json!("Alice"));
        store.insert("theme".into(), serde_json::json!("light"));
        store.insert("notifications_enabled".into(), serde_json::json!(true));
        store.insert("item_count".into(), serde_json::json!(3));

        Self {
            runtime: ObjcRuntime::new(),
            current_page: Arc::new(Mutex::new("home".to_string())),
            store: Arc::new(Mutex::new(store)),
        }
    }
}

impl Default for MockBridge {
    fn default() -> Self {
        Self::new()
    }
}

impl ObjcBridge for MockBridge {
    fn view_hierarchy(&self) -> Result<ViewNode, String> {
        self.runtime.capture_view_hierarchy()
    }

    fn navigate_to(&self, page: &str) -> Result<(), String> {
        let valid_pages = ["home", "detail", "settings", "profile"];
        if !valid_pages.contains(&page) {
            return Err(format!("unknown page: {page}. valid: {valid_pages:?}"));
        }
        let mut current = self.current_page.lock().map_err(|e| e.to_string())?;
        tracing::info!("navigating: {} -> {}", *current, page);
        *current = page.to_string();
        Ok(())
    }

    fn current_page(&self) -> Result<String, String> {
        let current = self.current_page.lock().map_err(|e| e.to_string())?;
        Ok(current.clone())
    }

    fn get_store_value(&self, key: &str) -> Result<serde_json::Value, String> {
        let store = self.store.lock().map_err(|e| e.to_string())?;
        Ok(store
            .get(key)
            .cloned()
            .unwrap_or(serde_json::Value::Null))
    }

    fn set_store_value(&self, key: &str, value: serde_json::Value) -> Result<(), String> {
        let mut store = self.store.lock().map_err(|e| e.to_string())?;
        tracing::info!("store set: {} = {}", key, value);
        store.insert(key.to_string(), value);
        Ok(())
    }

    fn list_store(&self) -> Result<Vec<StoreEntry>, String> {
        let store = self.store.lock().map_err(|e| e.to_string())?;
        Ok(store
            .iter()
            .map(|(k, v)| StoreEntry {
                key: k.clone(),
                value: v.clone(),
                value_type: match v {
                    serde_json::Value::String(_) => "String",
                    serde_json::Value::Number(_) => "Number",
                    serde_json::Value::Bool(_) => "Bool",
                    serde_json::Value::Array(_) => "Array",
                    serde_json::Value::Object(_) => "Object",
                    serde_json::Value::Null => "Null",
                }
                .to_string(),
            })
            .collect())
    }

    fn list_classes(&self) -> Result<Vec<String>, String> {
        Ok(self.runtime.list_classes())
    }

    fn send_message(
        &self,
        target: &str,
        selector: &str,
        args: Vec<serde_json::Value>,
    ) -> Result<serde_json::Value, String> {
        let addr =
            usize::from_str_radix(target.trim_start_matches("0x"), 16).map_err(|e| e.to_string())?;
        self.runtime.send_message(addr, selector, &args)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mock_navigate() {
        let bridge = MockBridge::new();
        assert_eq!(bridge.current_page().unwrap(), "home");
        bridge.navigate_to("settings").unwrap();
        assert_eq!(bridge.current_page().unwrap(), "settings");
    }

    #[test]
    fn test_mock_navigate_invalid() {
        let bridge = MockBridge::new();
        assert!(bridge.navigate_to("nonexistent").is_err());
    }

    #[test]
    fn test_mock_store() {
        let bridge = MockBridge::new();
        assert_eq!(
            bridge.get_store_value("user_name").unwrap(),
            serde_json::json!("Alice")
        );
        bridge
            .set_store_value("user_name", serde_json::json!("Bob"))
            .unwrap();
        assert_eq!(
            bridge.get_store_value("user_name").unwrap(),
            serde_json::json!("Bob")
        );
    }

    #[test]
    fn test_mock_store_list() {
        let bridge = MockBridge::new();
        let entries = bridge.list_store().unwrap();
        assert!(entries.len() >= 4);
    }

    #[test]
    fn test_mock_view_hierarchy() {
        let bridge = MockBridge::new();
        let root = bridge.view_hierarchy().unwrap();
        assert_eq!(root.class_name, "UIWindow");
        assert!(!root.children.is_empty());
    }

    #[test]
    fn test_mock_list_classes() {
        let bridge = MockBridge::new();
        let classes = bridge.list_classes().unwrap();
        assert!(classes.contains(&"UIView".to_string()));
    }
}
