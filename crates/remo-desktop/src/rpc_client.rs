use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use remo_protocol::{Message, MessageId, Request, Response};
use remo_transport::Connection;
use tokio::sync::{mpsc, oneshot, Mutex};
use tracing::{debug, warn};

#[derive(Debug, thiserror::Error)]
pub enum RpcError {
    #[error("transport: {0}")]
    Transport(#[from] remo_transport::TransportError),

    #[error("timeout waiting for response")]
    Timeout,

    #[error("connection closed")]
    Closed,
}

/// Result of an RPC call — either a JSON response or a binary response.
#[derive(Debug)]
pub enum RpcResponse {
    Json(Response),
    Binary(remo_protocol::BinaryResponse),
}

/// An RPC client connected to a single iOS device.
pub struct RpcClient {
    writer: Arc<Mutex<remo_transport::WriteHalf>>,
    pending: Arc<Mutex<HashMap<MessageId, oneshot::Sender<RpcResponse>>>>,
    _event_tx: mpsc::Sender<remo_protocol::Event>,
}

impl RpcClient {
    /// Connect to an iOS device via TCP and start the background read loop.
    pub async fn connect(
        addr: SocketAddr,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<Self, RpcError> {
        let conn = Connection::connect(addr).await?;
        Self::from_connection(conn, event_tx)
    }

    /// Create an RPC client from an already-established connection.
    pub fn from_connection(
        conn: Connection,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<Self, RpcError> {
        let (reader, writer) = conn.split();
        let writer = Arc::new(Mutex::new(writer));
        let pending: Arc<Mutex<HashMap<MessageId, oneshot::Sender<RpcResponse>>>> =
            Arc::new(Mutex::new(HashMap::new()));

        // Background read loop — only holds the reader, never blocks the writer.
        {
            let pending_r = Arc::clone(&pending);
            let evt_tx = event_tx.clone();

            tokio::spawn(async move {
                let mut reader = reader;
                loop {
                    match reader.recv().await {
                        Ok(Some(Message::Response(resp))) => {
                            let mut p = pending_r.lock().await;
                            if let Some(tx) = p.remove(&resp.id) {
                                let _ = tx.send(RpcResponse::Json(resp));
                            } else {
                                warn!(id = %resp.id, "orphan response");
                            }
                        }
                        Ok(Some(Message::BinaryResponse(br))) => {
                            let mut p = pending_r.lock().await;
                            if let Some(tx) = p.remove(&br.id) {
                                let _ = tx.send(RpcResponse::Binary(br));
                            } else {
                                warn!(id = %br.id, "orphan binary response");
                            }
                        }
                        Ok(Some(Message::Event(evt))) => {
                            let _ = evt_tx.send(evt).await;
                        }
                        Ok(Some(_)) => {
                            debug!("unexpected message from device");
                        }
                        Ok(None) | Err(_) => break,
                    }
                }
            });
        }

        Ok(Self {
            writer,
            pending,
            _event_tx: event_tx,
        })
    }

    /// Call a remote capability and wait for the response.
    pub async fn call(
        &self,
        capability: impl Into<String>,
        params: serde_json::Value,
        timeout: Duration,
    ) -> Result<RpcResponse, RpcError> {
        let req = Request::new(capability, params);
        let id = req.id;

        let (tx, rx) = oneshot::channel();
        self.pending.lock().await.insert(id, tx);

        self.writer.lock().await.send(Message::Request(req)).await?;

        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(resp)) => Ok(resp),
            Ok(Err(_)) => Err(RpcError::Closed),
            Err(_) => {
                self.pending.lock().await.remove(&id);
                Err(RpcError::Timeout)
            }
        }
    }
}
