use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use remo_protocol::{Message, MessageId, Request, Response, StreamFrame};
use remo_transport::Connection;
use tokio::sync::{broadcast, mpsc, oneshot, Mutex};
use tracing::{debug, warn};

use crate::stream_receiver::StreamReceiver;

#[derive(Debug, thiserror::Error)]
pub enum RpcError {
    #[error("transport: {0}")]
    Transport(#[from] remo_transport::TransportError),

    #[error("timeout waiting for response")]
    Timeout,

    #[error("connection closed")]
    Closed,

    #[error("remote: {0}")]
    Remote(String),
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
    stream_tx: broadcast::Sender<StreamFrame>,
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
        let (stream_tx, _) = broadcast::channel(64);

        // Background read loop — only holds the reader, never blocks the writer.
        {
            let pending_r = Arc::clone(&pending);
            let evt_tx = event_tx.clone();
            let stream_tx_r = stream_tx.clone();

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
                        Ok(Some(Message::StreamFrame(frame))) => {
                            let _ = stream_tx_r.send(frame);
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
            stream_tx,
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

    /// Subscribe to the stream of incoming `StreamFrame`s.
    pub fn subscribe_stream(&self) -> StreamReceiver {
        StreamReceiver::new(self.stream_tx.subscribe())
    }

    /// Get a clone of the broadcast sender for stream frames.
    pub fn stream_sender(&self) -> broadcast::Sender<StreamFrame> {
        self.stream_tx.clone()
    }

    /// Start a screen-mirror session and return the stream ID + a receiver.
    pub async fn start_mirror(&self, fps: u32) -> Result<(u32, StreamReceiver), RpcError> {
        let resp = self
            .call(
                "__start_mirror",
                serde_json::json!({"fps": fps, "codec": "h264"}),
                Duration::from_secs(10),
            )
            .await?;
        let response = match resp {
            RpcResponse::Json(r) => r,
            RpcResponse::Binary(_) => return Err(RpcError::Closed),
        };
        match response.result {
            remo_protocol::ResponseResult::Ok { data } => {
                let stream_id = data["stream_id"].as_u64().unwrap_or(1) as u32;
                let receiver = self.subscribe_stream();
                Ok((stream_id, receiver))
            }
            remo_protocol::ResponseResult::Error { message, .. } => Err(RpcError::Remote(message)),
        }
    }

    /// Stop a screen-mirror session.
    pub async fn stop_mirror(&self, stream_id: u32) -> Result<(), RpcError> {
        self.call(
            "__stop_mirror",
            serde_json::json!({"stream_id": stream_id}),
            Duration::from_secs(10),
        )
        .await?;
        Ok(())
    }
}
