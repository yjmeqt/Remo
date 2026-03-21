use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;

use remo_core::types::DeviceInfo;
use tokio::sync::RwLock;

/// Tracks discovered devices and their Remo agent endpoints.
#[derive(Clone)]
pub struct DeviceManager {
    devices: Arc<RwLock<HashMap<u32, DeviceRecord>>>,
}

#[derive(Debug, Clone)]
pub struct DeviceRecord {
    pub info: DeviceInfo,
    pub agent_addr: Option<SocketAddr>,
}

impl DeviceManager {
    pub fn new() -> Self {
        Self {
            devices: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn add_device(&self, info: DeviceInfo, agent_addr: Option<SocketAddr>) {
        let id = info.device_id;
        self.devices.write().await.insert(
            id,
            DeviceRecord { info, agent_addr },
        );
    }

    pub async fn remove_device(&self, device_id: u32) {
        self.devices.write().await.remove(&device_id);
    }

    pub async fn list_devices(&self) -> Vec<DeviceRecord> {
        self.devices.read().await.values().cloned().collect()
    }

    pub async fn get_device(&self, device_id: u32) -> Option<DeviceRecord> {
        self.devices.read().await.get(&device_id).cloned()
    }

    pub async fn set_agent_addr(&self, device_id: u32, addr: SocketAddr) {
        if let Some(record) = self.devices.write().await.get_mut(&device_id) {
            record.agent_addr = Some(addr);
        }
    }
}

impl Default for DeviceManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use remo_core::types::ConnectionType;

    #[tokio::test]
    async fn test_device_manager() {
        let mgr = DeviceManager::new();

        let dev = DeviceInfo {
            device_id: 1,
            serial_number: "ABC123".into(),
            product_id: 0x1234,
            connection_type: ConnectionType::Usb,
        };

        mgr.add_device(dev.clone(), None).await;
        assert_eq!(mgr.list_devices().await.len(), 1);

        let record = mgr.get_device(1).await.unwrap();
        assert_eq!(record.info.serial_number, "ABC123");
        assert!(record.agent_addr.is_none());

        let addr: SocketAddr = "127.0.0.1:9876".parse().unwrap();
        mgr.set_agent_addr(1, addr).await;
        let record = mgr.get_device(1).await.unwrap();
        assert_eq!(record.agent_addr, Some(addr));

        mgr.remove_device(1).await;
        assert!(mgr.list_devices().await.is_empty());
    }
}
