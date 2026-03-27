use std::sync::Arc;
use std::time::Duration;

use dashmap::DashMap;
use remo_desktop::{DeviceId, DeviceInfo, RpcClient, RpcResponse};
use serde_json::Value;
use tokio::task::JoinHandle;
use tracing::warn;

use crate::event_bus::EventBus;
use crate::types::{device_id_to_string, DeviceState};

const PING_INTERVAL: Duration = Duration::from_secs(5);
const PING_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_PING_FAILURES: u32 = 3;

/// Internal entry for a tracked device.
struct PoolEntry {
    state: DeviceState,
    client: Option<Arc<RpcClient>>,
    device_info: Option<DeviceInfo>,
}

/// Manages persistent RpcClient connections per device.
pub struct ConnectionPool {
    entries: Arc<DashMap<DeviceId, PoolEntry>>,
}

impl Default for ConnectionPool {
    fn default() -> Self {
        Self::new()
    }
}

impl ConnectionPool {
    /// Create a new, empty connection pool.
    pub fn new() -> Self {
        Self {
            entries: Arc::new(DashMap::new()),
        }
    }

    /// Upsert the state for a device. If the device has no entry yet, one is
    /// created with no client and no device info.
    pub fn set_state(&self, id: DeviceId, state: DeviceState) {
        self.entries
            .entry(id)
            .and_modify(|e| e.state = state)
            .or_insert(PoolEntry {
                state,
                client: None,
                device_info: None,
            });
    }

    /// Return the current state of a device, or `None` if the device is not
    /// tracked.
    pub fn get_state(&self, id: &DeviceId) -> Option<DeviceState> {
        self.entries.get(id).map(|e| e.state)
    }

    /// Remove a device entry entirely.
    pub fn remove(&self, id: &DeviceId) {
        self.entries.remove(id);
    }

    /// Disconnect a device: set state to `Disconnected` and drop the client,
    /// but keep the entry in the pool so the device remains visible.
    pub fn disconnect(&self, id: &DeviceId) {
        if let Some(mut entry) = self.entries.get_mut(id) {
            entry.state = DeviceState::Disconnected;
            entry.client = None;
        }
    }

    /// Attach an RPC client to a device and mark it as Connected.
    pub fn set_client(&self, id: &DeviceId, client: RpcClient) {
        if let Some(mut entry) = self.entries.get_mut(id) {
            entry.client = Some(Arc::new(client));
            entry.state = DeviceState::Connected;
        }
    }

    /// Store device info for a tracked device.
    pub fn set_device_info(&self, id: &DeviceId, info: DeviceInfo) {
        if let Some(mut entry) = self.entries.get_mut(id) {
            entry.device_info = Some(info);
        }
    }

    /// Call a capability on a device. The RPC client is cloned (via Arc) out of
    /// the DashMap so that the map guard is NOT held across the await point.
    pub async fn call(
        &self,
        id: &DeviceId,
        capability: &str,
        params: Value,
        timeout: Duration,
    ) -> Result<RpcResponse, String> {
        let client = self
            .entries
            .get(id)
            .and_then(|e| e.client.clone())
            .ok_or_else(|| "no client for device".to_string())?;

        // Guard is dropped here -- safe to await.
        client
            .call(capability, params, timeout)
            .await
            .map_err(|e| e.to_string())
    }

    /// Return a snapshot of all tracked devices and their states.
    pub fn list(&self) -> Vec<(DeviceId, DeviceState)> {
        self.entries
            .iter()
            .map(|entry| (entry.key().clone(), entry.value().state))
            .collect()
    }

    /// Spawn a background keepalive task that pings the device every
    /// `PING_INTERVAL`. After `MAX_PING_FAILURES` consecutive failures (each
    /// with a `PING_TIMEOUT`), the device is marked Disconnected and a
    /// `connection_lost` event is emitted on the EventBus.
    pub fn spawn_keepalive(&self, id: DeviceId, event_bus: Arc<EventBus>) -> JoinHandle<()> {
        let entries = Arc::clone(&self.entries);

        tokio::spawn(async move {
            let mut failures: u32 = 0;

            loop {
                tokio::time::sleep(PING_INTERVAL).await;

                // Clone the client out of the map (don't hold the guard across await).
                let client = {
                    match entries.get(&id) {
                        Some(entry) => match entry.client.clone() {
                            Some(c) => c,
                            None => break, // no client -- stop keepalive
                        },
                        None => break, // device removed -- stop keepalive
                    }
                };

                let result = client
                    .call("__ping", serde_json::json!({}), PING_TIMEOUT)
                    .await;

                if result.is_ok() {
                    failures = 0;
                } else {
                    failures += 1;
                    warn!(
                        device = %id,
                        failures,
                        "keepalive ping failed"
                    );

                    if failures >= MAX_PING_FAILURES {
                        // Mark disconnected.
                        if let Some(mut entry) = entries.get_mut(&id) {
                            entry.state = DeviceState::Disconnected;
                            entry.client = None;
                        }

                        let device_str = device_id_to_string(&id);
                        event_bus.emit(
                            "connection_lost",
                            Some(device_str),
                            serde_json::json!({"reason": "keepalive timeout"}),
                        );
                        break;
                    }
                }
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_state_transitions() {
        let pool = ConnectionPool::new();
        let id = DeviceId::Usb(1);

        // Initially not tracked.
        assert_eq!(pool.get_state(&id), None);

        // Set to Discovered.
        pool.set_state(id.clone(), DeviceState::Discovered);
        assert_eq!(pool.get_state(&id), Some(DeviceState::Discovered));

        // Transition to Connected.
        pool.set_state(id.clone(), DeviceState::Connected);
        assert_eq!(pool.get_state(&id), Some(DeviceState::Connected));

        // Remove the device.
        pool.remove(&id);
        assert_eq!(pool.get_state(&id), None);
    }

    #[test]
    fn list_entries() {
        let pool = ConnectionPool::new();
        pool.set_state(DeviceId::Usb(1), DeviceState::Discovered);
        pool.set_state(
            DeviceId::Bonjour("myphone".to_string()),
            DeviceState::Connected,
        );

        let list = pool.list();
        assert_eq!(list.len(), 2);
    }
}
