//! Web dashboard for controlling iOS devices.
//!
//! Provides REST endpoints for device discovery, connection management,
//! device info, capabilities, RPC calls, screenshots, and mirror control,
//! plus WebSocket endpoints for streaming video frames and push events.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::ws::{Message, WebSocket};
use axum::extract::{State, WebSocketUpgrade};
use axum::http::StatusCode;
use axum::response::{Html, IntoResponse};
use axum::routing::{get, post};
use axum::{Json, Router};
use remo_protocol::{stream_flags, StreamFrame};
use serde::Deserialize;
use tokio::sync::{broadcast, Mutex};
use tracing::{debug, info, warn};

use crate::device_manager::{
    DeviceId, DeviceInfo, DeviceManager, DeviceManagerEvent, DeviceTransport,
};
use crate::rpc_client::{RpcClient, RpcError, RpcResponse};
use remo_protocol::ResponseResult;

// ---------------------------------------------------------------------------
// Connection — bundles an RpcClient with its plumbing
// ---------------------------------------------------------------------------

struct ActiveConnection {
    client: RpcClient,
    device_id: DeviceId,
    device_name: String,
    /// Abort handle for the event fan-out task.
    _event_task: tokio::task::JoinHandle<()>,
}

/// Shared state for the dashboard server.
pub struct DashboardState {
    pub device_manager: DeviceManager,
    pub dm_event_rx: Mutex<tokio::sync::mpsc::Receiver<DeviceManagerEvent>>,
    pub stream_tx: broadcast::Sender<StreamFrame>,
    pub mirror_stream_id: Mutex<Option<u32>>,
    pub event_tx: broadcast::Sender<serde_json::Value>,
    connection: Mutex<Option<ActiveConnection>>,
}

impl DashboardState {
    pub fn new(
        device_manager: DeviceManager,
        dm_event_rx: tokio::sync::mpsc::Receiver<DeviceManagerEvent>,
    ) -> Self {
        let (stream_tx, _) = broadcast::channel(64);
        let (event_tx, _) = broadcast::channel(256);
        Self {
            device_manager,
            dm_event_rx: Mutex::new(dm_event_rx),
            stream_tx,
            mirror_stream_id: Mutex::new(None),
            event_tx,
            connection: Mutex::new(None),
        }
    }

    /// Get a reference to the connected RpcClient, or 503.
    async fn client(
        &self,
    ) -> Result<impl std::ops::Deref<Target = ActiveConnection> + '_, (StatusCode, String)> {
        use tokio::sync::MutexGuard;
        let guard = self.connection.lock().await;
        if guard.is_none() {
            return Err((
                StatusCode::SERVICE_UNAVAILABLE,
                "no device connected".into(),
            ));
        }
        // Re-map the guard so the caller gets a deref to ActiveConnection.
        Ok(MutexGuard::map(guard, |opt| opt.as_mut().unwrap()))
    }
}

/// Start the dashboard HTTP/WS server. Returns the bound address.
pub async fn start_server(
    state: Arc<DashboardState>,
    bind_addr: SocketAddr,
    shutdown: impl std::future::Future<Output = ()> + Send + 'static,
) -> std::io::Result<SocketAddr> {
    // Spawn device-manager event forwarding to the event_tx broadcast.
    {
        let st = Arc::clone(&state);
        tokio::spawn(async move {
            let mut rx = st.dm_event_rx.lock().await;
            while let Some(evt) = rx.recv().await {
                let value = match &evt {
                    DeviceManagerEvent::DeviceAdded(info) => {
                        serde_json::json!({
                            "kind": "device.added",
                            "payload": device_info_json(info),
                        })
                    }
                    DeviceManagerEvent::DeviceRemoved(id) => {
                        // If the removed device is the one we're connected to, clear connection.
                        let mut conn = st.connection.lock().await;
                        if let Some(active) = conn.as_ref() {
                            if active.device_id == *id {
                                // Clear mirror state
                                *st.mirror_stream_id.lock().await = None;
                                conn.take();
                                info!(device = %id, "connected device lost — connection cleared");
                            }
                        }
                        serde_json::json!({
                            "kind": "device.removed",
                            "payload": { "id": id.to_string() },
                        })
                    }
                };
                let _ = st.event_tx.send(value);
            }
        });
    }

    let app = Router::new()
        .route("/", get(serve_dashboard))
        // Device discovery & connection
        .route("/api/devices", get(api_devices))
        .route("/api/connect", post(api_connect))
        .route("/api/disconnect", post(api_disconnect))
        .route("/api/connection", get(api_connection_status))
        // Existing device-control routes
        .route("/api/info", get(api_info))
        .route("/api/capabilities", get(api_capabilities))
        .route("/api/call", post(api_call))
        .route("/api/screenshot", post(api_screenshot))
        .route("/api/mirror/start", post(api_mirror_start))
        .route("/api/mirror/stop", post(api_mirror_stop))
        .route("/ws/stream", get(ws_stream))
        .route("/ws/events", get(ws_events))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(bind_addr).await?;
    let addr = listener.local_addr()?;
    info!(%addr, "dashboard server started");

    tokio::spawn(async move {
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown)
            .await
            .ok();
    });

    Ok(addr)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn rpc_error_response(err: RpcError) -> (StatusCode, String) {
    let msg = format!("RPC error: {err}");
    drop(err);
    (StatusCode::BAD_GATEWAY, msg)
}

fn extract_json_data(resp: RpcResponse) -> Result<serde_json::Value, (StatusCode, String)> {
    let response = match resp {
        RpcResponse::Json(r) => r,
        RpcResponse::Binary(_) => {
            return Err((StatusCode::BAD_GATEWAY, "unexpected binary response".into()));
        }
    };
    match response.result {
        ResponseResult::Ok { data } => Ok(data),
        ResponseResult::Error { message, .. } => {
            Err((StatusCode::BAD_GATEWAY, format!("device error: {message}")))
        }
    }
}

fn device_info_json(info: &DeviceInfo) -> serde_json::Value {
    let (transport, addr) = match &info.transport {
        DeviceTransport::Usb { .. } => ("usb", None),
        DeviceTransport::Bonjour { .. } => ("bonjour", info.addr().map(|addr| addr.to_string())),
        DeviceTransport::Manual { addr } => ("manual", Some(addr.to_string())),
    };
    serde_json::json!({
        "id": info.id.to_string(),
        "name": info.display_name,
        "transport": transport,
        "addr": addr,
    })
}

// ---------------------------------------------------------------------------
// Device discovery & connection routes
// ---------------------------------------------------------------------------

async fn serve_dashboard() -> Html<&'static str> {
    Html(include_str!("dashboard.html"))
}

/// List all discovered devices.
async fn api_devices(State(state): State<Arc<DashboardState>>) -> Json<serde_json::Value> {
    let devices: Vec<_> = state
        .device_manager
        .list_devices()
        .into_iter()
        .map(|d| device_info_json(&d))
        .collect();
    Json(serde_json::json!(devices))
}

#[derive(Deserialize)]
struct ConnectRequest {
    id: String,
}

/// Connect to a specific device by ID string (e.g. "bonjour:RemoExample").
async fn api_connect(
    State(state): State<Arc<DashboardState>>,
    Json(body): Json<ConnectRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let id_str = &body.id;
    // Parse the device id
    let device_id = parse_device_id(id_str).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            format!("invalid device id: {id_str}"),
        )
    })?;

    // Check device exists
    let devices = state.device_manager.list_devices();
    let info = devices
        .iter()
        .find(|d| d.id == device_id)
        .ok_or_else(|| (StatusCode::NOT_FOUND, format!("device not found: {id_str}")))?;
    let device_name = info.display_name.clone();

    // Disconnect existing connection first
    {
        let mut conn = state.connection.lock().await;
        if let Some(active) = conn.take() {
            // Stop mirror if active
            let mut mirror = state.mirror_stream_id.lock().await;
            if let Some(sid) = mirror.take() {
                let _ = active.client.stop_mirror(sid).await;
            }
        }
    }

    // Create event channel for this connection
    let (rpc_event_tx, mut rpc_event_rx) = tokio::sync::mpsc::channel(64);

    let client = state
        .device_manager
        .connect(&device_id, rpc_event_tx)
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, format!("connection failed: {e}")))?;

    // Wire up stream_tx from the new client
    // The client's internal stream_tx is separate; we need to subscribe and forward.
    let client_stream_tx = client.stream_sender();
    {
        let dashboard_stream_tx = state.stream_tx.clone();
        let mut stream_rx = client_stream_tx.subscribe();
        tokio::spawn(async move {
            loop {
                match stream_rx.recv().await {
                    Ok(frame) => {
                        let _ = dashboard_stream_tx.send(frame);
                    }
                    Err(broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(broadcast::error::RecvError::Closed) => break,
                }
            }
        });
    }

    // Fan-out RPC events to the dashboard broadcast
    let event_broadcast_tx = state.event_tx.clone();
    let event_task = tokio::spawn(async move {
        while let Some(event) = rpc_event_rx.recv().await {
            let value = serde_json::json!({
                "kind": event.kind,
                "payload": event.payload,
            });
            let _ = event_broadcast_tx.send(value);
        }
    });

    let active = ActiveConnection {
        client,
        device_id: device_id.clone(),
        device_name: device_name.clone(),
        _event_task: event_task,
    };

    *state.connection.lock().await = Some(active);

    // Notify via events
    let _ = state.event_tx.send(serde_json::json!({
        "kind": "connection.established",
        "payload": { "id": device_id.to_string(), "name": device_name },
    }));

    info!(device = %device_id, "dashboard connected to device");

    Ok(Json(serde_json::json!({
        "status": "ok",
        "device_id": device_id.to_string(),
        "device_name": device_name,
    })))
}

/// Disconnect from the current device.
async fn api_disconnect(State(state): State<Arc<DashboardState>>) -> Json<serde_json::Value> {
    let mut conn = state.connection.lock().await;
    if let Some(active) = conn.take() {
        // Stop mirror if active
        let mut mirror = state.mirror_stream_id.lock().await;
        if let Some(sid) = mirror.take() {
            let _ = active.client.stop_mirror(sid).await;
        }
        let _ = state.event_tx.send(serde_json::json!({
            "kind": "connection.lost",
            "payload": { "id": active.device_id.to_string(), "reason": "user disconnected" },
        }));
        info!(device = %active.device_id, "dashboard disconnected from device");
        Json(serde_json::json!({"status": "ok", "disconnected": active.device_id.to_string()}))
    } else {
        Json(serde_json::json!({"status": "ok", "disconnected": null}))
    }
}

/// Check current connection status (also acts as health check).
async fn api_connection_status(
    State(state): State<Arc<DashboardState>>,
) -> Json<serde_json::Value> {
    let conn = state.connection.lock().await;
    match conn.as_ref() {
        Some(active) => {
            // Try a lightweight ping to verify the connection is alive
            let alive = active
                .client
                .call("__app_info", serde_json::json!({}), Duration::from_secs(3))
                .await
                .is_ok();
            Json(serde_json::json!({
                "connected": alive,
                "device_id": active.device_id.to_string(),
                "device_name": active.device_name,
            }))
        }
        None => Json(serde_json::json!({
            "connected": false,
            "device_id": null,
            "device_name": null,
        })),
    }
}

fn parse_device_id(s: &str) -> Option<DeviceId> {
    if let Some(rest) = s.strip_prefix("usb:") {
        rest.parse::<u32>().ok().map(DeviceId::Usb)
    } else if let Some(rest) = s.strip_prefix("bonjour:") {
        Some(DeviceId::Bonjour(rest.to_string()))
    } else {
        // Try as plain number (USB device ID)
        s.parse::<u32>().ok().map(DeviceId::Usb)
    }
}

// ---------------------------------------------------------------------------
// Device-control route handlers (require active connection)
// ---------------------------------------------------------------------------

async fn api_info(
    State(state): State<Arc<DashboardState>>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let conn = state.client().await?;
    let dev_resp = conn
        .client
        .call(
            "__device_info",
            serde_json::json!({}),
            Duration::from_secs(5),
        )
        .await
        .map_err(rpc_error_response)?;
    let device_data = extract_json_data(dev_resp)?;

    let app_resp = conn
        .client
        .call("__app_info", serde_json::json!({}), Duration::from_secs(5))
        .await
        .map_err(rpc_error_response)?;
    let app_data = extract_json_data(app_resp)?;

    Ok(Json(serde_json::json!({
        "device": device_data,
        "app": app_data,
    })))
}

async fn api_capabilities(
    State(state): State<Arc<DashboardState>>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let conn = state.client().await?;
    let resp = conn
        .client
        .call(
            "__list_capabilities",
            serde_json::json!({}),
            Duration::from_secs(5),
        )
        .await
        .map_err(rpc_error_response)?;
    let data = extract_json_data(resp)?;
    Ok(Json(data))
}

#[derive(Deserialize)]
struct CallRequest {
    name: String,
    #[serde(default = "default_params")]
    params: serde_json::Value,
}

fn default_params() -> serde_json::Value {
    serde_json::json!({})
}

async fn api_call(
    State(state): State<Arc<DashboardState>>,
    Json(body): Json<CallRequest>,
) -> Json<serde_json::Value> {
    let conn = match state.client().await {
        Ok(c) => c,
        Err((_, msg)) => {
            return Json(
                serde_json::json!({"status": "error", "code": "no_connection", "error": msg}),
            );
        }
    };

    let resp = match conn
        .client
        .call(&body.name, body.params, Duration::from_secs(10))
        .await
    {
        Ok(r) => r,
        Err(e) => {
            return Json(serde_json::json!({
                "status": "error",
                "code": "rpc_error",
                "error": e.to_string()
            }));
        }
    };

    match resp {
        RpcResponse::Json(r) => match r.result {
            ResponseResult::Ok { data } => Json(serde_json::json!({
                "status": "ok",
                "data": data
            })),
            ResponseResult::Error { code, message } => Json(serde_json::json!({
                "status": "error",
                "code": format!("{code:?}"),
                "error": message
            })),
        },
        RpcResponse::Binary(br) => Json(serde_json::json!({
            "status": "ok",
            "data": br.metadata,
            "binary_size": br.data.len()
        })),
    }
}

async fn api_screenshot(
    State(state): State<Arc<DashboardState>>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    let conn = state.client().await?;
    let resp = conn
        .client
        .call(
            "__screenshot",
            serde_json::json!({"format": "jpeg", "quality": 0.8}),
            Duration::from_secs(15),
        )
        .await
        .map_err(rpc_error_response)?;

    match resp {
        RpcResponse::Binary(br) => {
            let width = br.metadata["width"].as_u64().unwrap_or(0).to_string();
            let height = br.metadata["height"].as_u64().unwrap_or(0).to_string();
            Ok((
                [
                    (axum::http::header::CONTENT_TYPE, "image/jpeg".to_string()),
                    (
                        axum::http::header::HeaderName::from_static("x-width"),
                        width,
                    ),
                    (
                        axum::http::header::HeaderName::from_static("x-height"),
                        height,
                    ),
                ],
                br.data,
            ))
        }
        RpcResponse::Json(r) => match r.result {
            ResponseResult::Error { message, .. } => {
                Err((StatusCode::BAD_GATEWAY, format!("device error: {message}")))
            }
            _ => Err((
                StatusCode::BAD_GATEWAY,
                "expected binary response for screenshot".into(),
            )),
        },
    }
}

#[derive(Deserialize)]
struct MirrorStartRequest {
    #[serde(default = "default_fps")]
    fps: u32,
}

fn default_fps() -> u32 {
    30
}

async fn api_mirror_start(
    State(state): State<Arc<DashboardState>>,
    Json(body): Json<MirrorStartRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let conn = state.client().await?;
    let mut guard = state.mirror_stream_id.lock().await;
    if guard.is_some() {
        return Err((StatusCode::CONFLICT, "mirror already active".into()));
    }

    let (stream_id, _receiver) = conn
        .client
        .start_mirror(body.fps)
        .await
        .map_err(rpc_error_response)?;

    *guard = Some(stream_id);

    Ok(Json(serde_json::json!({
        "stream_id": stream_id,
        "fps": body.fps,
    })))
}

async fn api_mirror_stop(
    State(state): State<Arc<DashboardState>>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let conn = state.client().await?;
    let mut guard = state.mirror_stream_id.lock().await;
    let stream_id = guard
        .take()
        .ok_or_else(|| (StatusCode::NOT_FOUND, "no active mirror".into()))?;

    conn.client
        .stop_mirror(stream_id)
        .await
        .map_err(rpc_error_response)?;

    Ok(Json(serde_json::json!({"stopped": stream_id})))
}

// ---------------------------------------------------------------------------
// WebSocket handlers
// ---------------------------------------------------------------------------

async fn ws_stream(
    ws: WebSocketUpgrade,
    State(state): State<Arc<DashboardState>>,
) -> impl IntoResponse {
    let rx = state.stream_tx.subscribe();
    ws.on_upgrade(move |socket| handle_ws_stream(socket, rx))
}

async fn handle_ws_stream(mut socket: WebSocket, mut rx: broadcast::Receiver<StreamFrame>) {
    debug!("stream WebSocket client connected");
    loop {
        match rx.recv().await {
            Ok(frame) => {
                if frame.flags & stream_flags::STREAM_END != 0 {
                    break;
                }
                let mut buf = Vec::with_capacity(1 + 8 + frame.data.len());
                buf.push(frame.flags);
                buf.extend_from_slice(&frame.timestamp_us.to_be_bytes());
                buf.extend_from_slice(&frame.data);
                if socket.send(Message::Binary(buf.into())).await.is_err() {
                    break;
                }
            }
            Err(broadcast::error::RecvError::Lagged(n)) => {
                warn!(n, "stream WebSocket client lagged, skipped frames");
            }
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }
    debug!("stream WebSocket client disconnected");
}

async fn ws_events(
    ws: WebSocketUpgrade,
    State(state): State<Arc<DashboardState>>,
) -> impl IntoResponse {
    let rx = state.event_tx.subscribe();
    ws.on_upgrade(move |socket| handle_ws_events(socket, rx))
}

async fn handle_ws_events(mut socket: WebSocket, mut rx: broadcast::Receiver<serde_json::Value>) {
    debug!("events WebSocket client connected");
    loop {
        match rx.recv().await {
            Ok(event) => {
                let Ok(text) = serde_json::to_string(&event) else {
                    break;
                };
                if socket.send(Message::Text(text.into())).await.is_err() {
                    break;
                }
            }
            Err(broadcast::error::RecvError::Lagged(n)) => {
                warn!(n, "events WebSocket client lagged, skipped events");
            }
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }
    debug!("events WebSocket client disconnected");
}
