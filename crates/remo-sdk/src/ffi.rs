//! C ABI layer for embedding remo-sdk in iOS apps.
//!
//! Swift calls these functions through the generated C header.
//! The Rust tokio runtime runs on a background thread; FFI callbacks
//! are dispatched back to the caller's context via function pointers.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;

use serde_json::Value;
use tokio::runtime::Runtime;
use tokio::sync::broadcast;
use tracing::info;

use crate::registry::CapabilityRegistry;
use crate::server::RemoServer;

/// Global state shared across FFI calls.
struct RemoGlobal {
    runtime: Runtime,
    registry: CapabilityRegistry,
    shutdown_tx: Option<broadcast::Sender<()>>,
    actual_port: Option<u16>,
    _bonjour_reg: Option<remo_bonjour::ServiceRegistration>,
}

static GLOBAL: OnceLock<std::sync::Mutex<RemoGlobal>> = OnceLock::new();

fn global() -> &'static std::sync::Mutex<RemoGlobal> {
    GLOBAL.get_or_init(|| {
        let runtime = Runtime::new().expect("failed to create tokio runtime");
        std::sync::Mutex::new(RemoGlobal {
            runtime,
            registry: CapabilityRegistry::new(),
            shutdown_tx: None,
            actual_port: None,
            _bonjour_reg: None,
        })
    })
}

/// Start the Remo TCP server on the given port.
///
/// # Safety
/// Must be called once before any other remo function.
#[no_mangle]
pub unsafe extern "C" fn remo_start(port: u16) {
    let _ = tracing_subscriber::fmt()
        .with_env_filter("remo=debug")
        .try_init();

    let g = global();
    let mut lock = g.lock().unwrap();

    let registry = lock.registry.clone();
    let server = RemoServer::new(registry, port);
    lock.shutdown_tx = Some(server.shutdown_handle());

    let (port_tx, port_rx) = tokio::sync::oneshot::channel();

    lock.runtime.spawn(async move {
        if let Err(e) = server.run(Some(port_tx)).await {
            tracing::error!("remo server error: {e}");
        }
    });

    // Wait for the server to bind and report the actual port.
    let actual_port = lock.runtime.block_on(async {
        tokio::time::timeout(std::time::Duration::from_secs(2), port_rx)
            .await
            .ok()
            .and_then(Result::ok)
    });

    if let Some(p) = actual_port {
        lock.actual_port = Some(p);

        let _rt_guard = lock.runtime.enter();
        match remo_bonjour::ServiceRegistration::register(
            remo_bonjour::SERVICE_TYPE,
            p,
            None,
            None,
        ) {
            Ok(reg) => {
                lock._bonjour_reg = Some(reg);
                info!(port = p, "bonjour advertisement started");
            }
            Err(e) => {
                tracing::warn!("bonjour registration failed (non-fatal): {e}");
            }
        }
    }

    info!(port = actual_port.unwrap_or(port), "remo started via FFI");
}

/// Stop the Remo server gracefully.
#[no_mangle]
pub extern "C" fn remo_stop() {
    info!("remo stop requested");
    let g = global();
    let mut lock = g.lock().unwrap();
    // Drop Bonjour registration first (de-advertises the service).
    lock._bonjour_reg.take();
    if let Some(tx) = lock.shutdown_tx.take() {
        let _ = tx.send(());
    }
    lock.actual_port = None;
}

/// Return the actual port the server is listening on.
/// Returns 0 if the server has not started yet.
#[no_mangle]
pub extern "C" fn remo_get_port() -> u16 {
    let g = global();
    let lock = g.lock().unwrap();
    lock.actual_port.unwrap_or(0)
}

/// Callback type for capability handlers invoked from Swift.
///
/// - `context`: opaque pointer (e.g. `Unmanaged<HandlerBox>.toOpaque()`).
/// - `params_json`: null-terminated JSON string with request parameters.
///
/// Must return a null-terminated JSON string allocated with `strdup`.
pub type CapabilityCallback =
    unsafe extern "C" fn(context: *mut std::ffi::c_void, params_json: *const c_char) -> *mut c_char;

/// Register a capability handler from Swift.
///
/// # Safety
/// - `name` must be a valid null-terminated C string.
/// - `context` must remain valid for the lifetime of the registration.
/// - `callback` must be a valid, thread-safe function pointer.
#[no_mangle]
pub unsafe extern "C" fn remo_register_capability(
    name: *const c_char,
    context: *mut std::ffi::c_void,
    callback: CapabilityCallback,
) {
    let name = CStr::from_ptr(name).to_string_lossy().into_owned();

    // Safety: Swift side guarantees context + callback are Send + Sync.
    let handle = CallbackHandle {
        ctx: SendPtr(context),
        cb: callback,
    };
    // Prevent raw pointer parameters from being captured by the closure below.
    let _ = context;

    let g = global();
    let lock = g.lock().unwrap();

    lock.registry.register_sync(name, move |params: Value| {
        let params_str = CString::new(params.to_string())
            .map_err(|e| crate::registry::HandlerError::Internal(e.to_string()))?;

        // SAFETY: params_str is a valid CString; handle outlives this closure.
        let result_ptr = unsafe { handle.invoke(params_str.as_ptr()) };

        if result_ptr.is_null() {
            return Err(crate::registry::HandlerError::Internal(
                "handler returned null".into(),
            ));
        }

        // SAFETY: result_ptr is non-null (checked above) and points to a strdup'd C string.
        let result_cstr = unsafe { CStr::from_ptr(result_ptr) };
        let result_str = result_cstr.to_string_lossy();
        let value: Value = serde_json::from_str(&result_str)
            .map_err(|e| crate::registry::HandlerError::Internal(e.to_string()))?;

        // SAFETY: result_ptr was allocated by strdup on the Swift side; freeing it here.
        unsafe {
            libc_free(result_ptr as *mut std::ffi::c_void);
        }

        Ok(value)
    });
}

/// Free a Rust-allocated C string.
///
/// # Safety
/// `ptr` must be a pointer returned by a previous Remo FFI call, or null.
#[no_mangle]
pub unsafe extern "C" fn remo_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// List registered capabilities as a JSON array C string.
/// Caller must free with `remo_free_string`.
#[no_mangle]
pub extern "C" fn remo_list_capabilities() -> *mut c_char {
    let g = global();
    let lock = g.lock().unwrap();
    let names = lock.registry.list();
    let json = serde_json::to_string(&names).unwrap_or_else(|_| "[]".into());
    CString::new(json).unwrap().into_raw()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wrapper to make a raw pointer Send + Sync.
#[derive(Clone, Copy)]
struct SendPtr(*mut std::ffi::c_void);
// SAFETY: The Swift caller guarantees the context pointer is thread-safe.
unsafe impl Send for SendPtr {}
// SAFETY: The Swift caller guarantees the context pointer is thread-safe.
unsafe impl Sync for SendPtr {}

/// Wraps the FFI callback context so the closure is Send + Sync.
struct CallbackHandle {
    ctx: SendPtr,
    cb: CapabilityCallback,
}
// SAFETY: CallbackHandle's fields (SendPtr + extern "C" fn) are thread-safe per Swift contract.
unsafe impl Send for CallbackHandle {}
// SAFETY: CallbackHandle's fields (SendPtr + extern "C" fn) are thread-safe per Swift contract.
unsafe impl Sync for CallbackHandle {}

impl CallbackHandle {
    /// Invoke the Swift callback. Returns a pointer to a `strdup`'d result string.
    ///
    /// # Safety
    /// `params_json` must be a valid null-terminated C string.
    unsafe fn invoke(&self, params_json: *const c_char) -> *mut c_char {
        (self.cb)(self.ctx.0, params_json)
    }
}

extern "C" {
    #[link_name = "free"]
    fn libc_free(ptr: *mut std::ffi::c_void);
}
