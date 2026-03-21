use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use remo_core::CapabilityInfo;

pub type BoxFuture<T> = Pin<Box<dyn Future<Output = T> + Send>>;
pub type HandlerResult = Result<serde_json::Value, String>;
pub type HandlerFn = Arc<dyn Fn(serde_json::Value) -> BoxFuture<HandlerResult> + Send + Sync>;

struct CapEntry {
    description: String,
    handler: HandlerFn,
}

/// Registry of capabilities that the agent exposes to the host.
pub struct CapabilityRegistry {
    entries: HashMap<String, CapEntry>,
}

impl CapabilityRegistry {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    /// Register a capability with an async handler.
    pub fn register<F, Fut>(&mut self, name: &str, description: &str, handler: F)
    where
        F: Fn(serde_json::Value) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = HandlerResult> + Send + 'static,
    {
        let handler_fn: HandlerFn = Arc::new(move |params| Box::pin(handler(params)));
        self.entries.insert(
            name.to_string(),
            CapEntry {
                description: description.to_string(),
                handler: handler_fn,
            },
        );
    }

    /// Invoke a registered capability by name.
    pub async fn invoke(
        &self,
        name: &str,
        params: serde_json::Value,
    ) -> Result<serde_json::Value, String> {
        let entry = self
            .entries
            .get(name)
            .ok_or_else(|| format!("capability not found: {name}"))?;
        (entry.handler)(params).await
    }

    /// List all registered capabilities.
    pub fn list(&self) -> Vec<CapabilityInfo> {
        self.entries
            .iter()
            .map(|(name, entry)| CapabilityInfo {
                name: name.clone(),
                description: entry.description.clone(),
            })
            .collect()
    }

    pub fn contains(&self, name: &str) -> bool {
        self.entries.contains_key(name)
    }
}

impl Default for CapabilityRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_register_and_invoke() {
        let mut reg = CapabilityRegistry::new();
        reg.register("echo", "Echo params back", |params| async move {
            Ok(params)
        });

        let result = reg
            .invoke("echo", serde_json::json!({"hello": "world"}))
            .await
            .unwrap();
        assert_eq!(result, serde_json::json!({"hello": "world"}));
    }

    #[tokio::test]
    async fn test_invoke_not_found() {
        let reg = CapabilityRegistry::new();
        let result = reg.invoke("missing", serde_json::json!(null)).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_list_capabilities() {
        let mut reg = CapabilityRegistry::new();
        reg.register("a", "cap a", |_| async { Ok(serde_json::json!(null)) });
        reg.register("b", "cap b", |_| async { Ok(serde_json::json!(null)) });

        let list = reg.list();
        assert_eq!(list.len(), 2);
        assert!(list.iter().any(|c| c.name == "a"));
        assert!(list.iter().any(|c| c.name == "b"));
    }

    #[tokio::test]
    async fn test_handler_with_shared_state() {
        use std::sync::{Arc, Mutex};

        let counter = Arc::new(Mutex::new(0u64));
        let counter_clone = counter.clone();

        let mut reg = CapabilityRegistry::new();
        reg.register("inc", "Increment counter", move |_| {
            let c = counter_clone.clone();
            async move {
                let mut val = c.lock().unwrap();
                *val += 1;
                Ok(serde_json::json!({ "count": *val }))
            }
        });

        reg.invoke("inc", serde_json::json!(null)).await.unwrap();
        reg.invoke("inc", serde_json::json!(null)).await.unwrap();
        let result = reg.invoke("inc", serde_json::json!(null)).await.unwrap();
        assert_eq!(result, serde_json::json!({"count": 3}));
    }
}
