use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use dashmap::DashMap;
use remo_protocol::Event;
use serde_json::Value;
use tokio::sync::broadcast;
use tracing::debug;

/// Output from a capability handler — either JSON or binary.
#[derive(Debug, Clone)]
pub enum HandlerOutput {
    Json(Value),
    Binary { metadata: Value, data: Vec<u8> },
}

impl From<Value> for HandlerOutput {
    fn from(v: Value) -> Self {
        HandlerOutput::Json(v)
    }
}

/// Result of a capability handler invocation.
pub type HandlerResult = Result<HandlerOutput, HandlerError>;

/// A boxed async handler function.
pub type BoxedHandler =
    Arc<dyn Fn(Value) -> Pin<Box<dyn Future<Output = HandlerResult> + Send>> + Send + Sync>;

#[derive(Debug, thiserror::Error)]
pub enum HandlerError {
    #[error("invalid params: {0}")]
    InvalidParams(String),

    #[error("internal error: {0}")]
    Internal(String),
}

/// Registry of named capabilities that can be invoked remotely.
#[derive(Clone)]
pub struct CapabilityRegistry {
    handlers: Arc<DashMap<String, BoxedHandler>>,
    /// Optional broadcast sender for capability change events.
    /// Set by the server when it starts accepting connections.
    event_tx: Arc<std::sync::Mutex<Option<broadcast::Sender<Event>>>>,
}

impl Default for CapabilityRegistry {
    fn default() -> Self {
        Self {
            handlers: Arc::new(DashMap::new()),
            event_tx: Arc::new(std::sync::Mutex::new(None)),
        }
    }
}

impl CapabilityRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the broadcast sender used to emit capability change events.
    ///
    /// Called by the server when it starts, so that register/unregister
    /// can push `capabilities_changed` events to all connected clients.
    pub fn set_event_sender(&self, tx: broadcast::Sender<Event>) {
        let mut guard = self.event_tx.lock().unwrap();
        *guard = Some(tx);
    }

    /// Subscribe to capability change events.
    pub fn subscribe_events(&self) -> Option<broadcast::Receiver<Event>> {
        let guard = self.event_tx.lock().unwrap();
        guard.as_ref().map(broadcast::Sender::subscribe)
    }

    /// Register an async capability handler.
    pub fn register<F, Fut>(&self, name: impl Into<String>, handler: F)
    where
        F: Fn(Value) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = HandlerResult> + Send + 'static,
    {
        let name = name.into();
        debug!(capability = %name, "registered");
        let handler: BoxedHandler = Arc::new(move |params| Box::pin(handler(params)));
        self.handlers.insert(name.clone(), handler);
        self.emit_capabilities_changed("registered", &name);
    }

    /// Register a synchronous capability handler (returns JSON).
    pub fn register_sync<F>(&self, name: impl Into<String>, handler: F)
    where
        F: Fn(Value) -> Result<Value, HandlerError> + Send + Sync + 'static,
    {
        let name = name.into();
        debug!(capability = %name, "registered (sync)");
        let handler: BoxedHandler = Arc::new(move |params| {
            Box::pin(std::future::ready(match handler(params) {
                Ok(v) => Ok(HandlerOutput::Json(v)),
                Err(e) => Err(e),
            }))
        });
        self.handlers.insert(name.clone(), handler);
        self.emit_capabilities_changed("registered", &name);
    }

    /// Register a synchronous handler returning raw HandlerOutput (JSON or binary).
    pub fn register_sync_raw<F>(&self, name: impl Into<String>, handler: F)
    where
        F: Fn(Value) -> HandlerResult + Send + Sync + 'static,
    {
        let name = name.into();
        debug!(capability = %name, "registered (sync raw)");
        let handler: BoxedHandler =
            Arc::new(move |params| Box::pin(std::future::ready(handler(params))));
        self.handlers.insert(name.clone(), handler);
        self.emit_capabilities_changed("registered", &name);
    }

    /// Invoke a capability by name.
    pub async fn invoke(&self, name: &str, params: Value) -> Option<HandlerResult> {
        let handler = self.handlers.get(name)?;
        let handler = Arc::clone(handler.value());
        Some(handler(params).await)
    }

    /// Check if a capability is registered.
    pub fn has(&self, name: &str) -> bool {
        self.handlers.contains_key(name)
    }

    /// List all registered capability names.
    pub fn list(&self) -> Vec<String> {
        self.handlers.iter().map(|e| e.key().clone()).collect()
    }

    /// Remove a capability.
    pub fn unregister(&self, name: &str) -> bool {
        let removed = self.handlers.remove(name).is_some();
        if removed {
            self.emit_capabilities_changed("unregistered", name);
        }
        removed
    }

    /// Emit a `capabilities_changed` event if an event sender is configured.
    fn emit_capabilities_changed(&self, action: &str, name: &str) {
        let guard = self.event_tx.lock().unwrap();
        if let Some(tx) = guard.as_ref() {
            let capabilities = self.list();
            let event = Event::new(
                "capabilities_changed",
                serde_json::json!({
                    "action": action,
                    "name": name,
                    "capabilities": capabilities,
                }),
            );
            // Ignore send errors — no receivers is fine (no clients connected).
            let _ = tx.send(event);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn register_and_invoke() {
        let reg = CapabilityRegistry::new();
        reg.register_sync("ping", |_| Ok(serde_json::json!({"pong": true})));

        let output = reg.invoke("ping", Value::Null).await.unwrap().unwrap();
        match output {
            HandlerOutput::Json(v) => assert_eq!(v["pong"], true),
            _ => panic!("expected Json output"),
        }
    }

    #[tokio::test]
    async fn invoke_missing_returns_none() {
        let reg = CapabilityRegistry::new();
        assert!(reg.invoke("nope", Value::Null).await.is_none());
    }

    #[tokio::test]
    async fn list_capabilities() {
        let reg = CapabilityRegistry::new();
        reg.register_sync("a", |_| Ok(Value::Null));
        reg.register_sync("b", |_| Ok(Value::Null));

        let mut names = reg.list();
        names.sort();
        assert_eq!(names, vec!["a", "b"]);
    }
}
