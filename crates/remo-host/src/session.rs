use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;

use futures::{SinkExt, StreamExt};
use remo_core::protocol::{read_handshake, write_handshake, RemoCodec};
use remo_core::{CapabilityInfo, Message, RemoError, Response};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::task::JoinHandle;
use tokio_util::codec::Framed;

/// An active session with a Remo agent on a device.
///
/// Supports concurrent requests via message-ID correlation.
pub struct DeviceSession {
    tx: mpsc::Sender<Message>,
    pending: Arc<Mutex<HashMap<u32, oneshot::Sender<Response>>>>,
    next_id: AtomicU32,
    _writer_handle: JoinHandle<()>,
    _reader_handle: JoinHandle<()>,
    #[allow(dead_code)]
    pub initial_capabilities: Vec<CapabilityInfo>,
    pub peer_version: u32,
}

impl DeviceSession {
    /// Connect to a Remo agent at the given address.
    pub async fn connect(addr: SocketAddr) -> Result<Self, RemoError> {
        let mut stream = TcpStream::connect(addr).await?;

        // Handshake: read server's greeting, then send ours
        let peer_version = read_handshake(&mut stream).await?;
        write_handshake(&mut stream).await?;

        let framed = Framed::new(stream, RemoCodec);
        let (sink, mut reader_stream) = framed.split();

        let pending: Arc<Mutex<HashMap<u32, oneshot::Sender<Response>>>> =
            Arc::new(Mutex::new(HashMap::new()));

        // Writer task
        let (tx, mut rx) = mpsc::channel::<Message>(64);
        let writer_handle = tokio::spawn(async move {
            let mut sink = sink;
            while let Some(msg) = rx.recv().await {
                if sink.send(msg).await.is_err() {
                    break;
                }
            }
        });

        // Read the initial capabilities event
        let mut initial_capabilities = Vec::new();
        if let Some(Ok(Message::Event { body, .. })) = reader_stream.next().await.as_ref() {
            if body.name == "capabilities" {
                if let Ok(caps) =
                    serde_json::from_value::<Vec<CapabilityInfo>>(body.data.clone())
                {
                    initial_capabilities = caps;
                }
            }
        }

        // Reader task: routes responses to pending callers
        let pending_clone = pending.clone();
        let reader_handle = tokio::spawn(async move {
            while let Some(Ok(msg)) = reader_stream.next().await {
                match msg {
                    Message::Response { id, body } => {
                        let mut map = pending_clone.lock().await;
                        if let Some(sender) = map.remove(&id) {
                            let _ = sender.send(body);
                        }
                    }
                    Message::Event { body, .. } => {
                        tracing::info!("event: {} = {}", body.name, body.data);
                    }
                    _ => {}
                }
            }
        });

        Ok(Self {
            tx,
            pending,
            next_id: AtomicU32::new(1),
            _writer_handle: writer_handle,
            _reader_handle: reader_handle,
            initial_capabilities,
            peer_version,
        })
    }

    /// Call a remote capability and await the response.
    pub async fn call(
        &self,
        capability: &str,
        params: serde_json::Value,
    ) -> Result<serde_json::Value, RemoError> {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let (resp_tx, resp_rx) = oneshot::channel();

        self.pending.lock().await.insert(id, resp_tx);

        self.tx
            .send(Message::request(id, capability, params))
            .await
            .map_err(|_| RemoError::ChannelClosed)?;

        let response = resp_rx
            .await
            .map_err(|_| RemoError::ChannelClosed)?;

        if response.success {
            Ok(response.data)
        } else {
            Err(RemoError::Protocol(
                response.error.unwrap_or_else(|| "unknown error".into()),
            ))
        }
    }

    /// List capabilities (uses the built-in `_list_capabilities` request).
    pub async fn list_capabilities(&self) -> Result<Vec<CapabilityInfo>, RemoError> {
        let data = self.call("_list_capabilities", serde_json::json!(null)).await?;
        serde_json::from_value(data)
            .map_err(|e| RemoError::Serialization(e.to_string()))
    }
}
