use std::sync::Arc;
use std::time::Duration;

use axum::extract::ws::Message;
use axum::extract::{Path, Query, State, WebSocketUpgrade};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use remo_desktop::{DeviceId, RpcResponse};
use remo_protocol::ResponseResult;
use serde::Deserialize;
use serde_json::{json, Value};
use tracing::{debug, warn};
use uuid::Uuid;

use crate::connection_pool::ConnectionPool;
use crate::event_bus::EventBus;
use crate::types::{
    device_id_to_string, parse_device_id, CallMode, DaemonEvent, DeviceState, Webhook,
};

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------

pub struct ApiState {
    pub pool: Arc<ConnectionPool>,
    pub event_bus: Arc<EventBus>,
    pub webhooks: Arc<std::sync::Mutex<Vec<Webhook>>>,
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router(state: Arc<ApiState>) -> Router {
    Router::new()
        .route("/status", get(get_status))
        .route("/devices", get(list_devices))
        .route("/devices/{id}/connect", post(connect_device))
        .route("/devices/{id}/disconnect", post(disconnect_device))
        .route("/call", post(call_capability))
        .route("/capabilities", get(list_capabilities))
        .route("/screenshot", post(take_screenshot))
        .route("/events", get(poll_events))
        .route("/webhooks", post(register_webhook))
        .route("/webhooks/{id}", delete(delete_webhook))
        .route("/ws/events", get(ws_events))
        .with_state(state)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Resolve a device id from an optional string. If `None`, auto-resolve to the
/// single connected device, erroring when zero or more than one are connected.
fn resolve_device(
    pool: &ConnectionPool,
    device: Option<&str>,
) -> Result<DeviceId, (StatusCode, Json<Value>)> {
    if let Some(s) = device {
        parse_device_id(s).ok_or_else(|| {
            (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": format!("invalid device id: {s}")})),
            )
        })
    } else {
        let connected: Vec<DeviceId> = pool
            .list()
            .into_iter()
            .filter(|(_, state)| *state == DeviceState::Connected)
            .map(|(id, _)| id)
            .collect();

        match connected.len() {
            0 => Err((
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "no device connected"})),
            )),
            1 => Ok(connected.into_iter().next().unwrap()),
            _ => Err((
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "multiple devices connected — specify device id"})),
            )),
        }
    }
}

fn rpc_error_response(err: &str) -> (StatusCode, Json<Value>) {
    (
        StatusCode::BAD_GATEWAY,
        Json(json!({"error": format!("RPC error: {err}")})),
    )
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// GET /status
async fn get_status(State(state): State<Arc<ApiState>>) -> Json<Value> {
    let entries = state.pool.list();
    let total = entries.len();
    let connected = entries
        .iter()
        .filter(|(_, s)| *s == DeviceState::Connected)
        .count();

    Json(json!({
        "status": "running",
        "devices": total,
        "connected": connected,
    }))
}

/// GET /devices
async fn list_devices(State(state): State<Arc<ApiState>>) -> Json<Value> {
    let entries = state.pool.list();
    let devices: Vec<Value> = entries
        .into_iter()
        .map(|(id, s)| {
            json!({
                "id": device_id_to_string(&id),
                "state": s,
            })
        })
        .collect();

    Json(json!(devices))
}

/// POST /devices/{id}/connect
async fn connect_device(
    State(_state): State<Arc<ApiState>>,
    Path(id): Path<String>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let device_id = parse_device_id(&id).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": format!("invalid device id: {id}")})),
        )
    })?;

    // Placeholder — actual connection logic is driven by the daemon lifecycle.
    Ok(Json(json!({
        "status": "accepted",
        "device": device_id_to_string(&device_id),
    })))
}

/// POST /devices/{id}/disconnect
async fn disconnect_device(
    State(state): State<Arc<ApiState>>,
    Path(id): Path<String>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let device_id = parse_device_id(&id).ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": format!("invalid device id: {id}")})),
        )
    })?;

    state.pool.remove(&device_id);

    let device_str = device_id_to_string(&device_id);
    state.event_bus.emit(
        "connection_lost",
        Some(device_str.clone()),
        json!({"reason": "disconnected via API"}),
    );

    Ok(Json(json!({
        "status": "ok",
        "device": device_str,
    })))
}

// -- /call request body -----------------------------------------------------

#[derive(Deserialize)]
struct CallRequest {
    device: Option<String>,
    capability: String,
    #[serde(default = "default_params")]
    params: Value,
    #[serde(default)]
    mode: CallMode,
    timeout_ms: Option<u64>,
}

fn default_params() -> Value {
    json!({})
}

/// POST /call
async fn call_capability(
    State(state): State<Arc<ApiState>>,
    Json(body): Json<CallRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let device_id = resolve_device(&state.pool, body.device.as_deref())?;
    let timeout = Duration::from_millis(body.timeout_ms.unwrap_or(10_000));

    match body.mode {
        CallMode::Await => {
            let resp = state
                .pool
                .call(&device_id, &body.capability, body.params, timeout)
                .await
                .map_err(|e| rpc_error_response(&e))?;

            match resp {
                RpcResponse::Json(r) => match r.result {
                    ResponseResult::Ok { data } => {
                        Ok(Json(json!({"status": "ok", "data": data})).into_response())
                    }
                    ResponseResult::Error { code, message } => Ok((
                        StatusCode::BAD_GATEWAY,
                        Json(json!({
                            "status": "error",
                            "code": format!("{code:?}"),
                            "error": message,
                        })),
                    )
                        .into_response()),
                },
                RpcResponse::Binary(br) => Ok(Json(json!({
                    "status": "ok",
                    "data": br.metadata,
                    "binary_size": br.data.len(),
                }))
                .into_response()),
            }
        }
        CallMode::Fire => {
            let call_id = Uuid::new_v4().to_string();
            let call_id_clone = call_id.clone();
            let capability = body.capability.clone();
            let device_str = device_id_to_string(&device_id);
            let pool = Arc::clone(&state.pool);
            let event_bus = Arc::clone(&state.event_bus);
            let params = body.params;

            tokio::spawn(async move {
                let result = pool.call(&device_id, &capability, params, timeout).await;

                match result {
                    Ok(resp) => {
                        let data = match resp {
                            RpcResponse::Json(r) => match r.result {
                                ResponseResult::Ok { data } => data,
                                ResponseResult::Error { code, message } => {
                                    event_bus.emit(
                                        "call_failed",
                                        Some(device_str),
                                        json!({
                                            "call_id": call_id_clone,
                                            "capability": capability,
                                            "code": format!("{code:?}"),
                                            "error": message,
                                        }),
                                    );
                                    return;
                                }
                            },
                            RpcResponse::Binary(br) => {
                                json!({
                                    "metadata": br.metadata,
                                    "binary_size": br.data.len(),
                                })
                            }
                        };

                        event_bus.emit(
                            "call_completed",
                            Some(device_str),
                            json!({
                                "call_id": call_id_clone,
                                "capability": capability,
                                "data": data,
                            }),
                        );
                    }
                    Err(err) => {
                        event_bus.emit(
                            "call_failed",
                            Some(device_str),
                            json!({
                                "call_id": call_id_clone,
                                "capability": capability,
                                "error": err,
                            }),
                        );
                    }
                }
            });

            Ok(Json(json!({
                "call_id": call_id,
                "status": "accepted",
            }))
            .into_response())
        }
    }
}

/// GET /capabilities
async fn list_capabilities(
    State(state): State<Arc<ApiState>>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let device_id = resolve_device(&state.pool, None)?;

    let resp = state
        .pool
        .call(
            &device_id,
            "__list_capabilities",
            json!({}),
            Duration::from_secs(5),
        )
        .await
        .map_err(|e| rpc_error_response(&e))?;

    match resp {
        RpcResponse::Json(r) => match r.result {
            ResponseResult::Ok { data } => Ok(Json(data)),
            ResponseResult::Error { message, .. } => Err((
                StatusCode::BAD_GATEWAY,
                Json(json!({"error": format!("device error: {message}")})),
            )),
        },
        RpcResponse::Binary(_) => Err((
            StatusCode::BAD_GATEWAY,
            Json(json!({"error": "unexpected binary response"})),
        )),
    }
}

/// POST /screenshot
async fn take_screenshot(
    State(state): State<Arc<ApiState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let device_id = resolve_device(&state.pool, None)?;

    let resp = state
        .pool
        .call(
            &device_id,
            "__screenshot",
            json!({"format": "jpeg", "quality": 0.8}),
            Duration::from_secs(15),
        )
        .await
        .map_err(|e| rpc_error_response(&e))?;

    match resp {
        RpcResponse::Binary(br) => {
            let content_type = br.metadata["format"]
                .as_str()
                .map(|f| format!("image/{f}"))
                .unwrap_or_else(|| "image/jpeg".to_string());

            Ok((
                [
                    (axum::http::header::CONTENT_TYPE, content_type),
                    (
                        axum::http::header::HeaderName::from_static("x-width"),
                        br.metadata["width"].as_u64().unwrap_or(0).to_string(),
                    ),
                    (
                        axum::http::header::HeaderName::from_static("x-height"),
                        br.metadata["height"].as_u64().unwrap_or(0).to_string(),
                    ),
                ],
                br.data,
            )
                .into_response())
        }
        RpcResponse::Json(r) => match r.result {
            ResponseResult::Error { message, .. } => Err((
                StatusCode::BAD_GATEWAY,
                Json(json!({"error": format!("device error: {message}")})),
            )),
            _ => Err((
                StatusCode::BAD_GATEWAY,
                Json(json!({"error": "expected binary response for screenshot"})),
            )),
        },
    }
}

// -- /events query params ---------------------------------------------------

#[derive(Deserialize)]
struct EventsQuery {
    #[serde(default)]
    since: u64,
    #[serde(default = "default_limit")]
    limit: usize,
}

fn default_limit() -> usize {
    50
}

/// GET /events
async fn poll_events(
    State(state): State<Arc<ApiState>>,
    Query(q): Query<EventsQuery>,
) -> Json<Value> {
    let events = state.event_bus.poll(q.since, q.limit);
    let next_cursor = events.last().map(|e| e.seq).unwrap_or(q.since);

    Json(json!({
        "events": events,
        "next_cursor": next_cursor,
    }))
}

// -- /webhooks --------------------------------------------------------------

#[derive(Deserialize)]
struct WebhookRegister {
    url: String,
    #[serde(default)]
    filter: Vec<String>,
}

/// POST /webhooks
async fn register_webhook(
    State(state): State<Arc<ApiState>>,
    Json(body): Json<WebhookRegister>,
) -> Json<Value> {
    let webhook_id = Uuid::new_v4().to_string();

    let webhook = Webhook {
        id: webhook_id.clone(),
        url: body.url,
        filter: body.filter,
    };

    state
        .webhooks
        .lock()
        .expect("webhooks lock poisoned")
        .push(webhook);

    Json(json!({"webhook_id": webhook_id}))
}

/// DELETE /webhooks/{id}
async fn delete_webhook(
    State(state): State<Arc<ApiState>>,
    Path(id): Path<String>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let mut hooks = state.webhooks.lock().expect("webhooks lock poisoned");
    let len_before = hooks.len();
    hooks.retain(|w| w.id != id);

    if hooks.len() < len_before {
        Ok(Json(json!({"status": "ok", "deleted": id})))
    } else {
        Err((
            StatusCode::NOT_FOUND,
            Json(json!({"error": format!("webhook not found: {id}")})),
        ))
    }
}

// ---------------------------------------------------------------------------
// WebSocket handler
// ---------------------------------------------------------------------------

/// GET /ws/events — WebSocket upgrade for real-time event streaming.
async fn ws_events(ws: WebSocketUpgrade, State(state): State<Arc<ApiState>>) -> impl IntoResponse {
    let rx = state.event_bus.subscribe();
    ws.on_upgrade(move |socket| handle_ws_events(socket, rx))
}

async fn handle_ws_events(
    mut socket: axum::extract::ws::WebSocket,
    mut rx: tokio::sync::broadcast::Receiver<DaemonEvent>,
) {
    debug!("daemon ws/events client connected");
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
            Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                warn!(n, "ws/events client lagged, skipped events");
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
        }
    }
    debug!("daemon ws/events client disconnected");
}
