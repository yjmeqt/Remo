use std::collections::HashMap;
use std::path::Path;

use bytes::{Buf, BufMut, BytesMut};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tokio::sync::mpsc;
use tracing::{debug, info, warn};

use crate::types::*;

const USBMUXD_SOCKET: &str = "/var/run/usbmuxd";
const HEADER_SIZE: usize = 16;

#[derive(Debug, thiserror::Error)]
pub enum UsbmuxError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    #[error("plist: {0}")]
    Plist(#[from] plist::Error),

    #[error("connection refused by usbmuxd: code {0}")]
    Refused(i64),

    #[error("unexpected response: {0}")]
    Unexpected(String),

    #[error("device not found: {0}")]
    DeviceNotFound(u32),
}

/// Client for communicating with the usbmuxd daemon.
pub struct UsbmuxClient {
    stream: UnixStream,
    tag: u32,
}

impl UsbmuxClient {
    /// Connect to the usbmuxd Unix socket.
    pub async fn connect() -> Result<Self, UsbmuxError> {
        Self::connect_to(USBMUXD_SOCKET).await
    }

    /// Connect to a custom socket path (useful for testing).
    pub async fn connect_to(path: impl AsRef<Path>) -> Result<Self, UsbmuxError> {
        let stream = UnixStream::connect(path).await?;
        Ok(Self { stream, tag: 0 })
    }

    /// Send a Listen command and return a channel that receives device events.
    /// The returned stream yields `DeviceEvent`s as devices are attached/detached.
    pub async fn listen(
        mut self,
    ) -> Result<(mpsc::Receiver<DeviceEvent>, tokio::task::JoinHandle<()>), UsbmuxError> {
        self.send_plist(&UsbmuxRequest {
            message_type: "Listen".into(),
            prog_name: "Remo".into(),
            client_version: "0.1.0".into(),
            device_id: None,
            port_number: None,
        })
        .await?;

        // Read the initial Result response.
        let resp = self.recv_plist::<UsbmuxResponse>().await?;
        if let Some(code) = resp.number {
            if code != 0 {
                return Err(UsbmuxError::Refused(code));
            }
        }

        let (tx, rx) = mpsc::channel(32);

        let handle = tokio::spawn(async move {
            loop {
                match self.recv_plist_raw().await {
                    Ok(value) => {
                        let event = parse_device_event(value);
                        if tx.send(event).await.is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        warn!("usbmuxd listen error: {e}");
                        break;
                    }
                }
            }
        });

        Ok((rx, handle))
    }

    /// Open a TCP tunnel to a device port.
    /// After success, the returned `UnixStream` is a raw TCP pipe to the device.
    pub async fn connect_to_device(
        mut self,
        device_id: u32,
        port: u16,
    ) -> Result<UnixStream, UsbmuxError> {
        // usbmuxd expects port in network byte order (big-endian).
        let port_be = port.to_be();

        self.send_plist(&UsbmuxRequest {
            message_type: "Connect".into(),
            prog_name: "Remo".into(),
            client_version: "0.1.0".into(),
            device_id: Some(device_id),
            port_number: Some(port_be),
        })
        .await?;

        let resp = self.recv_plist::<UsbmuxResponse>().await?;
        match resp.number {
            Some(0) => {
                info!(device_id, port, "tunnel established");
                Ok(self.stream)
            }
            Some(code) => Err(UsbmuxError::Refused(code)),
            None => Err(UsbmuxError::Unexpected(format!("{resp:?}"))),
        }
    }

    // -- internal helpers --

    async fn send_plist(&mut self, request: &UsbmuxRequest) -> Result<(), UsbmuxError> {
        self.tag += 1;

        let mut payload = Vec::new();
        plist::to_writer_xml(&mut payload, request)?;

        let total_len = (HEADER_SIZE + payload.len()) as u32;

        let mut buf = BytesMut::with_capacity(total_len as usize);
        buf.put_u32_le(total_len);
        buf.put_u32_le(USBMUX_VERSION);
        buf.put_u32_le(MSG_TYPE_PLIST);
        buf.put_u32_le(self.tag);
        buf.extend_from_slice(&payload);

        self.stream.write_all(&buf).await?;
        debug!(tag = self.tag, "sent plist message");
        Ok(())
    }

    async fn recv_plist<T: serde::de::DeserializeOwned>(&mut self) -> Result<T, UsbmuxError> {
        let value = self.recv_plist_raw().await?;
        let parsed: T = plist::from_value(&value)?;
        Ok(parsed)
    }

    async fn recv_plist_raw(&mut self) -> Result<plist::Value, UsbmuxError> {
        // Read 16-byte header.
        let mut header_buf = [0u8; HEADER_SIZE];
        self.stream.read_exact(&mut header_buf).await?;

        let mut cursor = &header_buf[..];
        let length = cursor.get_u32_le();
        let _version = cursor.get_u32_le();
        let _msg_type = cursor.get_u32_le();
        let _tag = cursor.get_u32_le();

        let payload_len = length as usize - HEADER_SIZE;
        let mut payload = vec![0u8; payload_len];
        self.stream.read_exact(&mut payload).await?;

        let value: plist::Value = plist::from_bytes(&payload)?;
        Ok(value)
    }
}

/// Events emitted by the usbmuxd listen loop.
#[derive(Debug)]
pub enum DeviceEvent {
    Attached(Device),
    Detached { device_id: u32 },
    Unknown(plist::Value),
}

fn parse_device_event(value: plist::Value) -> DeviceEvent {
    let Some(dict) = value.as_dictionary() else {
        return DeviceEvent::Unknown(value);
    };

    let msg_type = dict
        .get("MessageType")
        .and_then(|v| v.as_string())
        .unwrap_or("");

    match msg_type {
        "Attached" => match plist::from_value::<DeviceAttached>(&value) {
            Ok(attached) => DeviceEvent::Attached(attached.into()),
            Err(_) => DeviceEvent::Unknown(value),
        },
        "Detached" => {
            let device_id = dict
                .get("DeviceID")
                .and_then(plist::Value::as_unsigned_integer)
                .unwrap_or(0) as u32;
            DeviceEvent::Detached { device_id }
        }
        _ => DeviceEvent::Unknown(value),
    }
}

/// Convenience: discover all currently attached devices.
pub async fn list_devices() -> Result<HashMap<u32, Device>, UsbmuxError> {
    let client = UsbmuxClient::connect().await?;
    let (mut rx, handle) = client.listen().await?;

    let mut devices = HashMap::new();

    // usbmuxd sends all currently-attached devices immediately after Listen,
    // then blocks. We use a short timeout to collect the initial burst.
    let deadline = tokio::time::sleep(std::time::Duration::from_millis(500));
    tokio::pin!(deadline);

    loop {
        tokio::select! {
            Some(event) = rx.recv() => {
                if let DeviceEvent::Attached(dev) = event {
                    info!(device_id = dev.device_id, serial = %dev.serial, "found device");
                    devices.insert(dev.device_id, dev);
                }
            }
            _ = &mut deadline => break,
        }
    }

    handle.abort();
    Ok(devices)
}
