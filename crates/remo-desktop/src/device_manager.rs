use std::net::SocketAddr;
use std::sync::Arc;

use dashmap::DashMap;
use remo_transport::Connection;
use remo_usbmuxd::{Device, DeviceEvent, UsbmuxClient};
use tokio::sync::mpsc;
use tracing::info;

use crate::rpc_client::RpcClient;

/// Target port on the iOS device where remo-sdk listens.
const DEFAULT_DEVICE_PORT: u16 = remo_protocol::DEFAULT_PORT;

/// Manages discovered iOS devices and their RPC connections.
pub struct DeviceManager {
    /// Known devices by device_id.
    devices: Arc<DashMap<u32, DeviceHandle>>,
    /// Channel for device events.
    event_tx: mpsc::Sender<DeviceManagerEvent>,
}

#[derive(Debug)]
pub struct DeviceHandle {
    pub device: Device,
    pub addr: Option<SocketAddr>,
}

#[derive(Debug)]
pub enum DeviceManagerEvent {
    DeviceAdded(Device),
    DeviceRemoved { device_id: u32 },
}

impl DeviceManager {
    pub fn new() -> (Self, mpsc::Receiver<DeviceManagerEvent>) {
        let (event_tx, event_rx) = mpsc::channel(32);
        (
            Self {
                devices: Arc::new(DashMap::new()),
                event_tx,
            },
            event_rx,
        )
    }

    /// Start listening for USB device events from usbmuxd.
    /// This spawns a background task.
    pub async fn start_usb_discovery(&self) -> Result<(), remo_usbmuxd::UsbmuxError> {
        let client = UsbmuxClient::connect().await?;
        let (mut rx, _handle) = client.listen().await?;

        let devices = Arc::clone(&self.devices);
        let event_tx = self.event_tx.clone();

        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                match event {
                    DeviceEvent::Attached(dev) => {
                        info!(id = dev.device_id, serial = %dev.serial, "device attached");
                        let device_id = dev.device_id;
                        devices.insert(
                            device_id,
                            DeviceHandle {
                                device: dev.clone(),
                                addr: None,
                            },
                        );
                        let _ = event_tx.send(DeviceManagerEvent::DeviceAdded(dev)).await;
                    }
                    DeviceEvent::Detached { device_id } => {
                        info!(device_id, "device detached");
                        devices.remove(&device_id);
                        let _ = event_tx
                            .send(DeviceManagerEvent::DeviceRemoved { device_id })
                            .await;
                    }
                    DeviceEvent::Unknown(_) => {}
                }
            }
        });

        Ok(())
    }

    /// Connect to a device via usbmuxd tunnel and return an RPC client.
    pub async fn connect_to_device(
        &self,
        device_id: u32,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<RpcClient, Box<dyn std::error::Error>> {
        let client = UsbmuxClient::connect().await?;
        let tunnel = client
            .connect_to_device(device_id, DEFAULT_DEVICE_PORT)
            .await?;

        // After a successful usbmuxd Connect, the UnixStream IS a raw TCP
        // tunnel to the device port. Frame it directly with our codec.
        let label: SocketAddr = ([0, 0, 0, 0], DEFAULT_DEVICE_PORT).into();
        let conn = Connection::from_unix_stream(tunnel, label);
        let rpc = RpcClient::from_connection(conn, event_tx)?;

        Ok(rpc)
    }

    /// Connect directly to a simulator or network device.
    pub async fn connect_direct(
        &self,
        addr: SocketAddr,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<RpcClient, Box<dyn std::error::Error>> {
        let rpc = RpcClient::connect(addr, event_tx).await?;
        Ok(rpc)
    }

    /// List all currently known devices.
    pub fn list_devices(&self) -> Vec<Device> {
        self.devices
            .iter()
            .map(|entry| entry.device.clone())
            .collect()
    }
}
