//! C ABI layer for embedding remo-sdk in iOS apps.
//!
//! Swift calls these functions through the generated C header.
//! The Rust tokio runtime runs on a background thread; FFI callbacks
//! are dispatched back to the caller's context via function pointers.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

use serde_json::Value;
use tokio::runtime::Runtime;
use tokio::sync::broadcast;
use tracing::info;

use crate::registry::CapabilityRegistry;
use crate::server::RemoServer;

static STARTED: AtomicBool = AtomicBool::new(false);

/// Global state shared across FFI calls.
struct RemoGlobal {
    runtime: Runtime,
    registry: CapabilityRegistry,
    shutdown_tx: Option<broadcast::Sender<()>>,
    actual_port: Option<u16>,
    bonjour_reg: Option<remo_bonjour::ServiceRegistration>,
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
            bonjour_reg: None,
        })
    })
}

fn bonjour_txt_record() -> remo_bonjour::TxtRecord {
    let mut txt = remo_bonjour::TxtRecord::new();

    let device_info = remo_objc::run_on_main_sync(|| {
        // SAFETY: run_on_main_sync ensures main-thread execution.
        unsafe { remo_objc::get_device_info() }
    });
    let app_info = remo_objc::run_on_main_sync(|| {
        // SAFETY: run_on_main_sync ensures main-thread execution.
        unsafe { remo_objc::get_app_info() }
    });

    let entries = [
        ("device_name", device_info.name),
        ("device_model", device_info.model),
        ("app_name", app_info.display_name),
        ("bundle_id", app_info.bundle_id),
        (
            "platform",
            if cfg!(target_os = "ios") {
                if cfg!(target_env = "sim") {
                    "simulator".to_string()
                } else {
                    "device".to_string()
                }
            } else {
                "unknown".to_string()
            },
        ),
    ];

    for (key, value) in entries {
        if !value.is_empty() {
            let _ = txt.set(key, &value);
        }
    }

    txt
}

fn start_server(port: u16) {
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }

    let _ = tracing_subscriber::fmt()
        .with_env_filter("remo=debug")
        .try_init();

    let g = global();

    let (port_rx, rt_handle) = {
        let mut lock = g.lock().unwrap();

        let registry = lock.registry.clone();
        let server = RemoServer::new(registry, port);
        lock.shutdown_tx = Some(server.shutdown_handle());

        let (port_tx, port_rx) = tokio::sync::oneshot::channel();
        let rt_handle = lock.runtime.handle().clone();

        lock.runtime.spawn(async move {
            if let Err(e) = server.run(Some(port_tx)).await {
                tracing::error!("remo server error: {e}");
            }
        });

        (port_rx, rt_handle)
    };

    let actual_port = rt_handle.block_on(async {
        tokio::time::timeout(std::time::Duration::from_secs(2), port_rx)
            .await
            .ok()
            .and_then(Result::ok)
    });

    let mut lock = g.lock().unwrap();

    if let Some(p) = actual_port {
        lock.actual_port = Some(p);

        let _rt_guard = lock.runtime.enter();
        let txt = bonjour_txt_record();
        match remo_bonjour::ServiceRegistration::register(
            remo_bonjour::SERVICE_TYPE,
            p,
            None,
            Some(&txt),
        ) {
            Ok(reg) => {
                lock.bonjour_reg = Some(reg);
                info!(port = p, "bonjour advertisement started");
            }
            Err(e) => {
                tracing::warn!("bonjour registration failed (non-fatal): {e}");
            }
        }
    }

    info!(port = actual_port.unwrap_or(port), "remo started");
}

/// Start the Remo TCP server on the given port.
///
/// With zero-config auto-start, calling this is optional. The Swift wrapper
/// calls it lazily on first API access (port 0 on simulator, 9930 on device).
/// Subsequent calls are no-ops; the server only starts once.
///
/// # Safety
/// Must be called from a single thread (the Swift wrapper guarantees this
/// via `static let` initialization).
#[no_mangle]
pub unsafe extern "C" fn remo_start(port: u16) {
    start_server(port);
}

/// Stop the Remo server gracefully.
#[no_mangle]
pub extern "C" fn remo_stop() {
    info!("remo stop requested");
    let g = global();
    let mut lock = g.lock().unwrap();
    // Drop Bonjour registration first (de-advertises the service).
    lock.bonjour_reg.take();
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

/// Optional destroy callback invoked when the registration ends.
///
/// Called exactly once per `remo_register_capability` call: when the
/// capability is unregistered, replaced by another registration of the same
/// name, or the registry entry is otherwise dropped. Use this to balance any
/// retain performed on `context` at registration time (e.g.
/// `Unmanaged.passRetained`).
///
/// May be `NULL` if the context does not require cleanup.
pub type CapabilityDestroy = unsafe extern "C" fn(context: *mut std::ffi::c_void);

/// Register a capability handler from Swift.
///
/// `destroy` (if non-null) is invoked exactly once when the registration ends —
/// on unregister, on replacement by another registration of the same name, or
/// when the handler is otherwise dropped from the registry. After that call the
/// caller may release any resources owned by `context`.
///
/// # Safety
/// - `name` must be a valid null-terminated C string.
/// - `context` must remain valid until `destroy` is invoked (or, if `destroy`
///   is null, for the lifetime of the process).
/// - `callback` must be a valid, thread-safe function pointer.
/// - `destroy`, if non-null, must be a valid, thread-safe function pointer.
#[no_mangle]
pub unsafe extern "C" fn remo_register_capability(
    name: *const c_char,
    context: *mut std::ffi::c_void,
    callback: CapabilityCallback,
    destroy: Option<CapabilityDestroy>,
) {
    let name = CStr::from_ptr(name).to_string_lossy().into_owned();

    // Safety: Swift side guarantees context + callback are Send + Sync.
    let handle = CallbackHandle {
        ctx: SendPtr(context),
        cb: callback,
        destroy,
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

/// Unregister a capability by name.
///
/// Returns `true` if the capability was found and removed, `false` otherwise.
///
/// # Safety
/// `name` must be a valid null-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn remo_unregister_capability(name: *const c_char) -> bool {
    let name = CStr::from_ptr(name).to_string_lossy();
    let g = global();
    let lock = g.lock().unwrap();
    lock.registry.unregister(&name)
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
///
/// The optional `destroy` callback is invoked from `Drop` so the context is
/// released exactly when the registry entry is removed — whether by an
/// explicit unregister, by replacement, or by dropping the registry itself.
struct CallbackHandle {
    ctx: SendPtr,
    cb: CapabilityCallback,
    destroy: Option<CapabilityDestroy>,
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

impl Drop for CallbackHandle {
    fn drop(&mut self) {
        if let Some(destroy) = self.destroy {
            // SAFETY: `destroy` was supplied by the FFI caller alongside `ctx`
            // and is contracted to be safe to call exactly once with that ctx.
            unsafe { destroy(self.ctx.0) };
        }
    }
}

extern "C" {
    #[link_name = "free"]
    fn libc_free(ptr: *mut std::ffi::c_void);
}

#[cfg(test)]
mod tests {
    //! Tests for the FFI capability lifecycle — specifically that the
    //! `destroy` callback supplied alongside the context pointer is invoked
    //! exactly once per registration, regardless of how the registration ends
    //! (explicit unregister or replacement by another registration of the
    //! same name).
    //!
    //! These tests exercise `CallbackHandle` through `CapabilityRegistry`
    //! directly rather than the global FFI entry points, since the latter
    //! share process-wide state.
    use super::*;
    use crate::registry::CapabilityRegistry;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    /// `context` argument is the pointer to a leaked `Arc<AtomicUsize>` —
    /// reclaim it and bump the destroy count.
    unsafe extern "C" fn destroy_counter(context: *mut std::ffi::c_void) {
        let counter = Arc::from_raw(context as *const AtomicUsize);
        counter.fetch_add(1, Ordering::SeqCst);
    }

    unsafe extern "C" fn noop_callback(
        _context: *mut std::ffi::c_void,
        _params_json: *const c_char,
    ) -> *mut c_char {
        std::ptr::null_mut()
    }

    /// Register a capability whose `destroy` increments `counter` when fired.
    /// Mirrors the bookkeeping `remo_register_capability` does internally so
    /// these tests don't depend on the global FFI registry.
    fn register_with_destroy(reg: &CapabilityRegistry, name: &str, counter: Arc<AtomicUsize>) {
        let context = Arc::into_raw(counter) as *mut std::ffi::c_void;
        let handle = CallbackHandle {
            ctx: SendPtr(context),
            cb: noop_callback,
            destroy: Some(destroy_counter),
        };
        reg.register_sync(name.to_string(), move |_params| {
            let _ = &handle;
            Ok(Value::Null)
        });
    }

    #[tokio::test]
    async fn destroy_fires_on_unregister() {
        let reg = CapabilityRegistry::new();
        let counter = Arc::new(AtomicUsize::new(0));

        register_with_destroy(&reg, "cap", Arc::clone(&counter));
        assert_eq!(
            counter.load(Ordering::SeqCst),
            0,
            "destroy must not fire on register"
        );

        assert!(reg.unregister("cap"));
        assert_eq!(
            counter.load(Ordering::SeqCst),
            1,
            "destroy must fire exactly once on unregister"
        );
    }

    #[tokio::test]
    async fn destroy_fires_on_replacement() {
        let reg = CapabilityRegistry::new();
        let first = Arc::new(AtomicUsize::new(0));
        let second = Arc::new(AtomicUsize::new(0));

        register_with_destroy(&reg, "cap", Arc::clone(&first));
        register_with_destroy(&reg, "cap", Arc::clone(&second));

        assert_eq!(
            first.load(Ordering::SeqCst),
            1,
            "old context must be destroyed when replaced"
        );
        assert_eq!(
            second.load(Ordering::SeqCst),
            0,
            "new context must still be alive"
        );

        assert!(reg.unregister("cap"));
        assert_eq!(
            second.load(Ordering::SeqCst),
            1,
            "new context must be destroyed on unregister"
        );
    }

    #[tokio::test]
    async fn destroy_fires_on_registry_drop() {
        let counter = Arc::new(AtomicUsize::new(0));
        {
            let reg = CapabilityRegistry::new();
            register_with_destroy(&reg, "cap", Arc::clone(&counter));
            assert_eq!(counter.load(Ordering::SeqCst), 0);
        }
        assert_eq!(
            counter.load(Ordering::SeqCst),
            1,
            "destroy must fire when registry is dropped"
        );
    }

    #[tokio::test]
    async fn null_destroy_is_safe() {
        let handle = CallbackHandle {
            ctx: SendPtr(std::ptr::null_mut()),
            cb: noop_callback,
            destroy: None,
        };
        drop(handle);
    }
}
