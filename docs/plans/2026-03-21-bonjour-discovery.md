# Bonjour Auto-Discovery & Multi-Simulator Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable automatic discovery of iOS simulators via Bonjour/mDNS and support simultaneous connections to multiple simulators from the macOS desktop tool.

**Architecture:** A new `remo-bonjour` crate provides async-safe Rust bindings over Apple's `dns_sd.h` C API. On iOS, `remo-sdk` advertises itself as a `_remo._tcp` Bonjour service after binding to an OS-assigned port. On macOS, `remo-desktop` browses for `_remo._tcp` services, automatically discovering all running simulators. The `DeviceManager` is extended with a unified device model that tracks USB, Bonjour, and manual devices, enabling simultaneous multi-device connections.

**Tech Stack:** Rust, `dns_sd.h` (Apple system C API), tokio `AsyncFd` for event loop integration, serde for TXT record metadata.

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `crates/remo-bonjour/Cargo.toml` | Crate manifest; depends on tokio, tracing |
| `crates/remo-bonjour/src/lib.rs` | Re-exports + service type constant `_remo._tcp` |
| `crates/remo-bonjour/src/sys.rs` | Raw `extern "C"` FFI bindings to `dns_sd.h` |
| `crates/remo-bonjour/src/error.rs` | `BonjourError` type wrapping `DNSServiceErrorType` codes |
| `crates/remo-bonjour/src/register.rs` | `ServiceRegistration` — advertise a Bonjour service |
| `crates/remo-bonjour/src/browser.rs` | `ServiceBrowser` — discover services on the network |
| `crates/remo-bonjour/src/txt.rs` | TXT record builder/parser (wraps `TXTRecordCreate` etc.) |

### Modified files

| File | Changes |
|---|---|
| `Cargo.toml` (workspace root) | Add `remo-bonjour` to `members` |
| `crates/remo-sdk/Cargo.toml` | Add `remo-bonjour` dependency |
| `crates/remo-sdk/src/server.rs` | Support port 0, return actual bound port from `run()`, advertise via Bonjour |
| `crates/remo-sdk/src/ffi.rs` | `remo_start()` stores actual port; add `remo_get_port()` FFI |
| `crates/remo-desktop/Cargo.toml` | Add `remo-bonjour` dependency |
| `crates/remo-desktop/src/device_manager.rs` | Add `start_bonjour_discovery()`, unified `DeviceInfo` enum, multi-device connection pool |
| `crates/remo-cli/src/main.rs` | `remo devices` also lists Bonjour-discovered devices |

---

## Chunk 1: remo-bonjour crate — FFI bindings + error types

### Task 1: Scaffold remo-bonjour crate

**Files:**
- Create: `crates/remo-bonjour/Cargo.toml`
- Create: `crates/remo-bonjour/src/lib.rs`
- Modify: `Cargo.toml` (workspace root, line 3–8)

- [ ] **Step 1: Create `crates/remo-bonjour/Cargo.toml`**

```toml
[package]
name = "remo-bonjour"
version.workspace = true
edition.workspace = true

[lints]
workspace = true

[dependencies]
tokio.workspace = true
tracing.workspace = true
thiserror.workspace = true
```

- [ ] **Step 2: Create `crates/remo-bonjour/src/lib.rs`**

```rust
pub mod browser;
pub mod error;
pub mod register;
pub mod sys;
pub mod txt;

pub use browser::ServiceBrowser;
pub use error::BonjourError;
pub use register::ServiceRegistration;
pub use txt::TxtRecord;

/// Bonjour service type for Remo.
pub const SERVICE_TYPE: &str = "_remo._tcp";
```

- [ ] **Step 3: Add `remo-bonjour` to workspace `Cargo.toml`**

In workspace root `Cargo.toml`, add `"crates/remo-bonjour"` to the `members` list.

- [ ] **Step 4: Verify the crate compiles**

Run: `cargo check -p remo-bonjour`
Expected: compiles (modules are empty stubs for now)

- [ ] **Step 5: Commit**

```bash
git add crates/remo-bonjour/ Cargo.toml
git commit -m "feat(bonjour): scaffold remo-bonjour crate"
```

---

### Task 2: Write `dns_sd.h` FFI bindings (`sys.rs`)

**Files:**
- Create: `crates/remo-bonjour/src/sys.rs`

The `dns_sd.h` API is part of Apple's libSystem, which is always linked on macOS/iOS. No extra linker flags are needed.

- [ ] **Step 1: Write the raw FFI bindings**

```rust
#![allow(non_camel_case_types, clippy::upper_case_acronyms)]

use std::os::raw::{c_char, c_int, c_uchar, c_void};

pub type DNSServiceRef = *mut c_void;
pub type DNSServiceFlags = u32;
pub type DNSServiceErrorType = i32;

pub const K_DNS_SERVICE_FLAGS_ADD: DNSServiceFlags = 0x2;
pub const K_DNS_SERVICE_ERR_NO_ERROR: DNSServiceErrorType = 0;

// Callback types
pub type DNSServiceRegisterReply = unsafe extern "C" fn(
    sd_ref: DNSServiceRef,
    flags: DNSServiceFlags,
    error_code: DNSServiceErrorType,
    name: *const c_char,
    reg_type: *const c_char,
    domain: *const c_char,
    context: *mut c_void,
);

pub type DNSServiceBrowseReply = unsafe extern "C" fn(
    sd_ref: DNSServiceRef,
    flags: DNSServiceFlags,
    interface_index: u32,
    error_code: DNSServiceErrorType,
    service_name: *const c_char,
    reg_type: *const c_char,
    reply_domain: *const c_char,
    context: *mut c_void,
);

pub type DNSServiceResolveReply = unsafe extern "C" fn(
    sd_ref: DNSServiceRef,
    flags: DNSServiceFlags,
    interface_index: u32,
    error_code: DNSServiceErrorType,
    fullname: *const c_char,
    hosttarget: *const c_char,
    port: u16, // network byte order
    txt_len: u16,
    txt_record: *const c_uchar,
    context: *mut c_void,
);

// TXT record opaque struct (16 bytes on Apple platforms)
#[repr(C)]
pub struct TXTRecordRef {
    _opaque: [u8; 16],
}

extern "C" {
    // Service registration
    pub fn DNSServiceRegister(
        sd_ref: *mut DNSServiceRef,
        flags: DNSServiceFlags,
        interface_index: u32,
        name: *const c_char,
        reg_type: *const c_char,
        domain: *const c_char,
        host: *const c_char,
        port: u16, // network byte order
        txt_len: u16,
        txt_record: *const c_void,
        callback: DNSServiceRegisterReply,
        context: *mut c_void,
    ) -> DNSServiceErrorType;

    // Service browsing
    pub fn DNSServiceBrowse(
        sd_ref: *mut DNSServiceRef,
        flags: DNSServiceFlags,
        interface_index: u32,
        reg_type: *const c_char,
        domain: *const c_char,
        callback: DNSServiceBrowseReply,
        context: *mut c_void,
    ) -> DNSServiceErrorType;

    // Service resolution
    pub fn DNSServiceResolve(
        sd_ref: *mut DNSServiceRef,
        flags: DNSServiceFlags,
        interface_index: u32,
        name: *const c_char,
        reg_type: *const c_char,
        domain: *const c_char,
        callback: DNSServiceResolveReply,
        context: *mut c_void,
    ) -> DNSServiceErrorType;

    // Socket FD for async I/O integration
    pub fn DNSServiceRefSockFD(sd_ref: DNSServiceRef) -> c_int;

    // Process results when socket is readable
    pub fn DNSServiceProcessResult(sd_ref: DNSServiceRef) -> DNSServiceErrorType;

    // Deallocate
    pub fn DNSServiceRefDeallocate(sd_ref: DNSServiceRef);

    // TXT record helpers
    pub fn TXTRecordCreate(
        txt_record: *mut TXTRecordRef,
        buffer_len: u16,
        buffer: *mut c_void,
    );

    pub fn TXTRecordSetValue(
        txt_record: *mut TXTRecordRef,
        key: *const c_char,
        value_len: u8,
        value: *const c_void,
    ) -> DNSServiceErrorType;

    pub fn TXTRecordGetLength(txt_record: *const TXTRecordRef) -> u16;

    pub fn TXTRecordGetBytesPtr(txt_record: *const TXTRecordRef) -> *const c_void;

    pub fn TXTRecordDeallocate(txt_record: *mut TXTRecordRef);
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo check -p remo-bonjour`
Expected: compiles (linker won't complain until we actually use the symbols in a binary)

- [ ] **Step 3: Commit**

```bash
git add crates/remo-bonjour/src/sys.rs
git commit -m "feat(bonjour): add dns_sd.h raw FFI bindings"
```

---

### Task 3: Error type (`error.rs`)

**Files:**
- Create: `crates/remo-bonjour/src/error.rs`

- [ ] **Step 1: Write the error type**

```rust
use crate::sys::DNSServiceErrorType;

#[derive(Debug, thiserror::Error)]
pub enum BonjourError {
    #[error("dns_sd error: code {0}")]
    DnsService(DNSServiceErrorType),

    #[error("service name contained interior null byte")]
    NullByte(#[from] std::ffi::NulError),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}

impl BonjourError {
    pub fn from_code(code: DNSServiceErrorType) -> Result<(), Self> {
        if code == crate::sys::K_DNS_SERVICE_ERR_NO_ERROR {
            Ok(())
        } else {
            Err(Self::DnsService(code))
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo check -p remo-bonjour`

- [ ] **Step 3: Commit**

```bash
git add crates/remo-bonjour/src/error.rs
git commit -m "feat(bonjour): add BonjourError type"
```

---

### Task 4: TXT record builder (`txt.rs`)

**Files:**
- Create: `crates/remo-bonjour/src/txt.rs`

- [ ] **Step 1: Write the TXT record wrapper**

```rust
use std::ffi::CString;

use crate::error::BonjourError;
use crate::sys;

/// Builder for DNS-SD TXT records.
///
/// TXT records carry key-value metadata alongside a Bonjour service
/// (e.g. `app_id=com.example.app`, `sdk_version=0.1.0`).
pub struct TxtRecord {
    inner: sys::TXTRecordRef,
}

impl TxtRecord {
    pub fn new() -> Self {
        let mut inner = sys::TXTRecordRef { _opaque: [0; 16] };
        // SAFETY: TXTRecordCreate initialises the opaque struct; buffer=NULL
        // means the implementation allocates internally.
        unsafe { sys::TXTRecordCreate(&mut inner, 0, std::ptr::null_mut()) };
        Self { inner }
    }

    /// Insert a key-value pair. Value must be <= 255 bytes.
    pub fn set(&mut self, key: &str, value: &str) -> Result<(), BonjourError> {
        let key_c = CString::new(key)?;
        let value_bytes = value.as_bytes();
        let len = u8::try_from(value_bytes.len()).unwrap_or(255);
        // SAFETY: key_c is a valid C string; value_bytes is valid for len bytes.
        let err = unsafe {
            sys::TXTRecordSetValue(
                &mut self.inner,
                key_c.as_ptr(),
                len,
                value_bytes.as_ptr().cast(),
            )
        };
        BonjourError::from_code(err)
    }

    pub fn len(&self) -> u16 {
        // SAFETY: inner is a valid TXTRecordRef.
        unsafe { sys::TXTRecordGetLength(&self.inner) }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn as_ptr(&self) -> *const std::ffi::c_void {
        // SAFETY: inner is a valid TXTRecordRef.
        unsafe { sys::TXTRecordGetBytesPtr(&self.inner) }
    }
}

impl Default for TxtRecord {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for TxtRecord {
    fn drop(&mut self) {
        // SAFETY: inner is a valid TXTRecordRef that we own.
        unsafe { sys::TXTRecordDeallocate(&mut self.inner) };
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo check -p remo-bonjour`

- [ ] **Step 3: Commit**

```bash
git add crates/remo-bonjour/src/txt.rs
git commit -m "feat(bonjour): add TxtRecord builder wrapping dns_sd TXT API"
```

---

## Chunk 2: Service registration (iOS side) + service browsing (macOS side)

### Task 5: Implement `ServiceRegistration` (`register.rs`)

**Files:**
- Create: `crates/remo-bonjour/src/register.rs`

This is used on the iOS side (inside simulators) to advertise the Remo server via Bonjour. It uses `tokio::io::unix::AsyncFd` to integrate the dns_sd socket into the tokio event loop.

- [ ] **Step 1: Write the registration module**

```rust
use std::ffi::CString;
use std::os::fd::BorrowedFd;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use tokio::io::unix::AsyncFd;
use tokio::io::Interest;
use tracing::{debug, error, info};

use crate::error::BonjourError;
use crate::sys;
use crate::txt::TxtRecord;

/// A registered Bonjour service. Dropping this de-registers the service.
pub struct ServiceRegistration {
    sd_ref: sys::DNSServiceRef,
    _registered: Arc<AtomicBool>,
}

// SAFETY: DNSServiceRef is thread-safe per Apple documentation —
// a single ref can be used from one thread at a time, but we only
// access it from the tokio task or on drop.
unsafe impl Send for ServiceRegistration {}
unsafe impl Sync for ServiceRegistration {}

impl ServiceRegistration {
    /// Advertise a Bonjour service.
    ///
    /// - `service_type`: e.g. `"_remo._tcp"`
    /// - `port`: the TCP port to advertise (host byte order)
    /// - `name`: instance name, or `None` for the system default
    /// - `txt`: optional TXT record with metadata
    pub fn register(
        service_type: &str,
        port: u16,
        name: Option<&str>,
        txt: Option<&TxtRecord>,
    ) -> Result<Self, BonjourError> {
        let reg_type = CString::new(service_type)?;
        let name_c = name.map(CString::new).transpose()?;

        let registered = Arc::new(AtomicBool::new(false));
        let ctx = Arc::into_raw(Arc::clone(&registered)) as *mut std::ffi::c_void;

        let mut sd_ref: sys::DNSServiceRef = std::ptr::null_mut();

        let (txt_len, txt_ptr) = match txt {
            Some(t) => (t.len(), t.as_ptr()),
            None => (0, std::ptr::null()),
        };

        // SAFETY: All C strings are valid; sd_ref is written by dns_sd.
        // The context pointer is an Arc we leak; reclaimed in the callback.
        let err = unsafe {
            sys::DNSServiceRegister(
                &mut sd_ref,
                0, // no flags
                0, // all interfaces
                name_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
                reg_type.as_ptr(),
                std::ptr::null(), // default domain
                std::ptr::null(), // default host
                port.to_be(),     // dns_sd wants network byte order
                txt_len,
                txt_ptr,
                register_callback,
                ctx,
            )
        };
        BonjourError::from_code(err)?;

        info!(service_type, port, "bonjour service registration initiated");

        let reg = Self {
            sd_ref,
            _registered: registered,
        };

        reg.spawn_event_loop();

        Ok(reg)
    }

    /// Spawn a tokio task that processes dns_sd events.
    fn spawn_event_loop(&self) {
        let sd_ref = self.sd_ref;

        // SAFETY: DNSServiceRefSockFD returns a valid fd for the lifetime of sd_ref.
        let fd = unsafe { sys::DNSServiceRefSockFD(sd_ref) };

        tokio::spawn(async move {
            // SAFETY: fd is valid for the lifetime of sd_ref; we borrow it.
            let async_fd = match unsafe {
                AsyncFd::with_interest(BorrowedFd::borrow_raw(fd), Interest::READABLE)
            } {
                Ok(afd) => afd,
                Err(e) => {
                    error!("failed to create AsyncFd for bonjour: {e}");
                    return;
                }
            };

            loop {
                match async_fd.readable().await {
                    Ok(mut guard) => {
                        // SAFETY: sd_ref is valid; socket is readable.
                        let err = unsafe { sys::DNSServiceProcessResult(sd_ref) };
                        if err != sys::K_DNS_SERVICE_ERR_NO_ERROR {
                            error!(err, "DNSServiceProcessResult failed");
                            break;
                        }
                        guard.clear_ready();
                    }
                    Err(e) => {
                        debug!("bonjour fd error: {e}");
                        break;
                    }
                }
            }
        });
    }
}

impl Drop for ServiceRegistration {
    fn drop(&mut self) {
        if !self.sd_ref.is_null() {
            // SAFETY: sd_ref is valid and we own it.
            unsafe { sys::DNSServiceRefDeallocate(self.sd_ref) };
        }
    }
}

/// C callback invoked by dns_sd when registration completes.
unsafe extern "C" fn register_callback(
    _sd_ref: sys::DNSServiceRef,
    _flags: sys::DNSServiceFlags,
    error_code: sys::DNSServiceErrorType,
    name: *const std::os::raw::c_char,
    _reg_type: *const std::os::raw::c_char,
    _domain: *const std::os::raw::c_char,
    context: *mut std::ffi::c_void,
) {
    // Reconstruct the Arc without taking ownership (we peek).
    let registered = unsafe { Arc::from_raw(context as *const AtomicBool) };

    if error_code == sys::K_DNS_SERVICE_ERR_NO_ERROR {
        let name_str = if name.is_null() {
            "<unknown>"
        } else {
            unsafe { std::ffi::CStr::from_ptr(name) }
                .to_str()
                .unwrap_or("<invalid>")
        };
        info!(name = name_str, "bonjour service registered");
        registered.store(true, Ordering::SeqCst);
    } else {
        error!(error_code, "bonjour registration failed");
    }

    // Leak back so the Arc isn't dropped (ServiceRegistration owns it).
    std::mem::forget(registered);
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo check -p remo-bonjour`

- [ ] **Step 3: Commit**

```bash
git add crates/remo-bonjour/src/register.rs
git commit -m "feat(bonjour): implement ServiceRegistration with async event loop"
```

---

### Task 6: Implement `ServiceBrowser` (`browser.rs`)

**Files:**
- Create: `crates/remo-bonjour/src/browser.rs`

This is used on the macOS side to discover all `_remo._tcp` services. It discovers services, resolves their host:port, and sends events through a channel.

- [ ] **Step 1: Write the browser module**

```rust
use std::ffi::CString;
use std::net::SocketAddr;
use std::os::fd::BorrowedFd;
use std::sync::Arc;

use tokio::io::unix::AsyncFd;
use tokio::io::Interest;
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

use crate::error::BonjourError;
use crate::sys;

/// Event emitted when a Bonjour service is found or lost.
#[derive(Debug, Clone)]
pub enum BrowseEvent {
    Found(ServiceInfo),
    Lost { name: String },
}

/// Resolved information about a discovered Bonjour service.
#[derive(Debug, Clone)]
pub struct ServiceInfo {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub interface_index: u32,
}

impl ServiceInfo {
    /// For simulators on localhost, resolve to a `SocketAddr`.
    pub fn socket_addr(&self) -> Option<SocketAddr> {
        use std::net::ToSocketAddrs;
        format!("{}:{}", self.host.trim_end_matches('.'), self.port)
            .to_socket_addrs()
            .ok()?
            .next()
    }
}

/// Browses the local network for Bonjour services of a given type.
pub struct ServiceBrowser {
    sd_ref: sys::DNSServiceRef,
}

unsafe impl Send for ServiceBrowser {}
unsafe impl Sync for ServiceBrowser {}

struct BrowseContext {
    event_tx: mpsc::Sender<BrowseEvent>,
    service_type: CString,
}

impl ServiceBrowser {
    /// Start browsing for services of the given type.
    /// Returns a receiver that emits `BrowseEvent`s.
    pub fn browse(service_type: &str) -> Result<(Self, mpsc::Receiver<BrowseEvent>), BonjourError> {
        let reg_type = CString::new(service_type)?;
        let (event_tx, event_rx) = mpsc::channel(64);

        let ctx = Box::new(BrowseContext {
            event_tx,
            service_type: reg_type.clone(),
        });
        let ctx_ptr = Box::into_raw(ctx) as *mut std::ffi::c_void;

        let mut sd_ref: sys::DNSServiceRef = std::ptr::null_mut();

        // SAFETY: reg_type is a valid C string; sd_ref is written by dns_sd.
        let err = unsafe {
            sys::DNSServiceBrowse(
                &mut sd_ref,
                0, // no flags
                0, // all interfaces
                reg_type.as_ptr(),
                std::ptr::null(), // default domain
                browse_callback,
                ctx_ptr,
            )
        };
        BonjourError::from_code(err)?;

        info!(service_type, "bonjour browse started");

        let browser = Self { sd_ref };
        browser.spawn_event_loop();

        Ok((browser, event_rx))
    }

    fn spawn_event_loop(&self) {
        let sd_ref = self.sd_ref;
        // SAFETY: DNSServiceRefSockFD returns a valid fd.
        let fd = unsafe { sys::DNSServiceRefSockFD(sd_ref) };

        tokio::spawn(async move {
            // SAFETY: fd is valid for the lifetime of sd_ref.
            let async_fd = match unsafe {
                AsyncFd::with_interest(BorrowedFd::borrow_raw(fd), Interest::READABLE)
            } {
                Ok(afd) => afd,
                Err(e) => {
                    error!("failed to create AsyncFd for bonjour browser: {e}");
                    return;
                }
            };

            loop {
                match async_fd.readable().await {
                    Ok(mut guard) => {
                        // SAFETY: sd_ref is valid; socket is readable.
                        let err = unsafe { sys::DNSServiceProcessResult(sd_ref) };
                        if err != sys::K_DNS_SERVICE_ERR_NO_ERROR {
                            error!(err, "browser DNSServiceProcessResult failed");
                            break;
                        }
                        guard.clear_ready();
                    }
                    Err(e) => {
                        debug!("bonjour browser fd error: {e}");
                        break;
                    }
                }
            }
        });
    }
}

impl Drop for ServiceBrowser {
    fn drop(&mut self) {
        if !self.sd_ref.is_null() {
            // SAFETY: we own sd_ref.
            unsafe { sys::DNSServiceRefDeallocate(self.sd_ref) };
        }
    }
}

/// C callback for browse events.
unsafe extern "C" fn browse_callback(
    _sd_ref: sys::DNSServiceRef,
    flags: sys::DNSServiceFlags,
    interface_index: u32,
    error_code: sys::DNSServiceErrorType,
    service_name: *const std::os::raw::c_char,
    _reg_type: *const std::os::raw::c_char,
    reply_domain: *const std::os::raw::c_char,
    context: *mut std::ffi::c_void,
) {
    if error_code != sys::K_DNS_SERVICE_ERR_NO_ERROR {
        error!(error_code, "browse callback error");
        return;
    }

    // SAFETY: context is a valid BrowseContext pointer that outlives this callback.
    let ctx = unsafe { &*(context as *const BrowseContext) };

    let name = unsafe { std::ffi::CStr::from_ptr(service_name) }
        .to_string_lossy()
        .into_owned();

    let is_add = (flags & sys::K_DNS_SERVICE_FLAGS_ADD) != 0;

    if is_add {
        info!(name = %name, "bonjour service found, resolving...");

        let domain = unsafe { std::ffi::CStr::from_ptr(reply_domain) };
        let domain_owned = domain.to_owned();
        let name_c = match CString::new(name.clone()) {
            Ok(c) => c,
            Err(_) => return,
        };

        let tx = ctx.event_tx.clone();

        let resolve_ctx = Box::new(ResolveContext {
            name: name.clone(),
            event_tx: tx,
        });
        let resolve_ctx_ptr = Box::into_raw(resolve_ctx) as *mut std::ffi::c_void;

        let mut resolve_ref: sys::DNSServiceRef = std::ptr::null_mut();

        // SAFETY: All strings are valid C strings.
        let err = unsafe {
            sys::DNSServiceResolve(
                &mut resolve_ref,
                0,
                interface_index,
                name_c.as_ptr(),
                ctx.service_type.as_ptr(),
                domain_owned.as_ptr(),
                resolve_callback,
                resolve_ctx_ptr,
            )
        };

        if err != sys::K_DNS_SERVICE_ERR_NO_ERROR {
            error!(err, name = %name, "DNSServiceResolve failed");
            // Reclaim the leaked context.
            let _ = unsafe { Box::from_raw(resolve_ctx_ptr as *mut ResolveContext) };
            return;
        }

        // Process the resolve result synchronously (dns_sd will call the
        // callback once and we can deallocate).
        let resolve_err = unsafe { sys::DNSServiceProcessResult(resolve_ref) };
        if resolve_err != sys::K_DNS_SERVICE_ERR_NO_ERROR {
            warn!(resolve_err, "resolve process result failed");
        }
        unsafe { sys::DNSServiceRefDeallocate(resolve_ref) };
    } else {
        info!(name = %name, "bonjour service lost");
        let _ = ctx.event_tx.try_send(BrowseEvent::Lost { name });
    }
}

struct ResolveContext {
    name: String,
    event_tx: mpsc::Sender<BrowseEvent>,
}

/// C callback for resolve events.
unsafe extern "C" fn resolve_callback(
    _sd_ref: sys::DNSServiceRef,
    _flags: sys::DNSServiceFlags,
    interface_index: u32,
    error_code: sys::DNSServiceErrorType,
    _fullname: *const std::os::raw::c_char,
    hosttarget: *const std::os::raw::c_char,
    port: u16, // network byte order
    _txt_len: u16,
    _txt_record: *const std::os::raw::c_uchar,
    context: *mut std::ffi::c_void,
) {
    // Take ownership of the context (one-shot resolve).
    let ctx = unsafe { Box::from_raw(context as *mut ResolveContext) };

    if error_code != sys::K_DNS_SERVICE_ERR_NO_ERROR {
        error!(error_code, name = %ctx.name, "resolve callback error");
        return;
    }

    let host = unsafe { std::ffi::CStr::from_ptr(hosttarget) }
        .to_string_lossy()
        .into_owned();
    let port = u16::from_be(port);

    info!(name = %ctx.name, host = %host, port, "service resolved");

    let info = ServiceInfo {
        name: ctx.name.clone(),
        host,
        port,
        interface_index,
    };

    let _ = ctx.event_tx.try_send(BrowseEvent::Found(info));
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cargo check -p remo-bonjour`

- [ ] **Step 3: Commit**

```bash
git add crates/remo-bonjour/src/browser.rs
git commit -m "feat(bonjour): implement ServiceBrowser with resolve"
```

---

### Task 7: Integration test — register + browse on localhost

**Files:**
- Create: `crates/remo-bonjour/tests/roundtrip.rs`

This test verifies the register → browse → resolve cycle works.

- [ ] **Step 1: Write the roundtrip test**

```rust
//! Integration test: register a service, browse for it, verify it resolves.
//!
//! Requires macOS or iOS (dns_sd is an Apple-only API).

use remo_bonjour::{BrowseEvent, ServiceBrowser, ServiceRegistration, TxtRecord, SERVICE_TYPE};
use tokio::time::{timeout, Duration};

#[tokio::test]
async fn register_and_discover() {
    let port = 19930_u16; // test port

    let mut txt = TxtRecord::new();
    txt.set("test_key", "test_value").unwrap();

    let _reg =
        ServiceRegistration::register(SERVICE_TYPE, port, Some("RemoTest"), Some(&txt)).unwrap();

    // Give dns_sd a moment to propagate.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let (_browser, mut rx) = ServiceBrowser::browse(SERVICE_TYPE).unwrap();

    let event = timeout(Duration::from_secs(5), rx.recv())
        .await
        .expect("timed out waiting for browse event")
        .expect("channel closed");

    match event {
        BrowseEvent::Found(info) => {
            assert_eq!(info.name, "RemoTest");
            assert_eq!(info.port, port);
            assert!(!info.host.is_empty());
        }
        BrowseEvent::Lost { .. } => panic!("expected Found event, got Lost"),
    }
}
```

- [ ] **Step 2: Run the test**

Run: `cargo test -p remo-bonjour --test roundtrip -- --nocapture`
Expected: PASS (on macOS; this test requires Apple's dns_sd daemon)

- [ ] **Step 3: Commit**

```bash
git add crates/remo-bonjour/tests/roundtrip.rs
git commit -m "test(bonjour): add register-and-discover roundtrip test"
```

---

## Chunk 3: Integrate into remo-sdk (iOS side) — dynamic port + Bonjour advertisement

### Task 8: Make `RemoServer` support dynamic port and return actual port

**Files:**
- Modify: `crates/remo-sdk/src/server.rs`
- Modify: `crates/remo-transport/src/listener.rs`

Currently `Listener::bind()` binds to a fixed port. When `port=0`, the OS assigns a free port. We need to propagate the actual port back.

- [ ] **Step 1: Modify `Listener::bind()` to expose `local_addr()`**

`Listener` already exposes `local_addr()` — no changes needed there.

- [ ] **Step 2: Modify `RemoServer::run()` to return the actual port**

In `crates/remo-sdk/src/server.rs`, change `run()` to accept a `oneshot::Sender<u16>` for reporting the actual bound port:

```rust
use tokio::sync::{broadcast, oneshot};
// ... existing imports ...

impl RemoServer {
    // ... existing new() and shutdown_handle() ...

    /// Start accepting connections. Blocks until shutdown.
    /// If `port_tx` is provided, sends the actual bound port once listening.
    pub async fn run(
        &self,
        port_tx: Option<oneshot::Sender<u16>>,
    ) -> Result<(), remo_transport::TransportError> {
        let addr: SocketAddr = ([0, 0, 0, 0], self.port).into();
        let listener = Listener::bind(addr).await?;
        let actual_port = listener.local_addr().port();
        info!(port = actual_port, "remo server started");

        if let Some(tx) = port_tx {
            let _ = tx.send(actual_port);
        }

        loop {
            // ... rest unchanged ...
        }
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cargo check -p remo-sdk`
Expected: may need to fix callers that call `run()` without the new parameter.

- [ ] **Step 4: Update the integration test if it calls `server.run()` directly**

Check `tests/integration.rs` and update any `server.run()` calls to `server.run(None)`.

Run: `cargo test --workspace`

- [ ] **Step 5: Commit**

```bash
git add crates/remo-sdk/src/server.rs crates/remo-transport/src/listener.rs
git commit -m "feat(sdk): support dynamic port in RemoServer::run()"
```

---

### Task 9: Add Bonjour advertisement to `remo-sdk` FFI layer

**Files:**
- Modify: `crates/remo-sdk/Cargo.toml` (add `remo-bonjour` dep)
- Modify: `crates/remo-sdk/src/ffi.rs`

On `remo_start()`, after the server binds, register the service via Bonjour. Also add `remo_get_port()` so Swift can read the actual port.

- [ ] **Step 1: Add `remo-bonjour` dependency to `remo-sdk`**

In `crates/remo-sdk/Cargo.toml`:

```toml
remo-bonjour = { path = "../remo-bonjour" }
```

- [ ] **Step 2: Modify `ffi.rs` to advertise via Bonjour and expose port**

```rust
// Add to RemoGlobal:
struct RemoGlobal {
    runtime: Runtime,
    registry: CapabilityRegistry,
    shutdown_tx: Option<broadcast::Sender<()>>,
    actual_port: Option<u16>,
    _bonjour_reg: Option<remo_bonjour::ServiceRegistration>,
}

// Update remo_start():
#[no_mangle]
pub unsafe extern "C" fn remo_start(port: u16) {
    // ... existing tracing init ...
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

    // Wait briefly for the port to be assigned.
    let actual_port = lock.runtime.block_on(async {
        tokio::time::timeout(std::time::Duration::from_secs(2), port_rx)
            .await
            .ok()
            .and_then(|r| r.ok())
    });

    if let Some(p) = actual_port {
        lock.actual_port = Some(p);

        // Advertise via Bonjour.
        match remo_bonjour::ServiceRegistration::register(
            remo_bonjour::SERVICE_TYPE,
            p,
            None, // system default name
            None, // no TXT record for now
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

// Add new FFI function:
/// Return the actual port the server is listening on.
/// Returns 0 if the server has not started yet.
#[no_mangle]
pub extern "C" fn remo_get_port() -> u16 {
    let g = global();
    let lock = g.lock().unwrap();
    lock.actual_port.unwrap_or(0)
}
```

- [ ] **Step 3: Update `remo_stop()` to clean up Bonjour**

```rust
#[no_mangle]
pub extern "C" fn remo_stop() {
    info!("remo stop requested");
    let g = global();
    let mut lock = g.lock().unwrap();
    // Drop Bonjour registration first (de-advertises).
    lock._bonjour_reg.take();
    if let Some(tx) = lock.shutdown_tx.take() {
        let _ = tx.send(());
    }
    lock.actual_port = None;
}
```

- [ ] **Step 4: Verify it compiles**

Run: `cargo check -p remo-sdk`

- [ ] **Step 5: Commit**

```bash
git add crates/remo-sdk/
git commit -m "feat(sdk): advertise via Bonjour on start, add remo_get_port() FFI"
```

---

## Chunk 4: Integrate into remo-desktop (macOS side) — Bonjour browsing + multi-device

### Task 10: Add Bonjour discovery to `DeviceManager`

**Files:**
- Modify: `crates/remo-desktop/Cargo.toml` (add `remo-bonjour` dep)
- Modify: `crates/remo-desktop/src/device_manager.rs`

Extend `DeviceManager` with a unified device model and Bonjour browsing.

- [ ] **Step 1: Add `remo-bonjour` to `remo-desktop` dependencies**

In `crates/remo-desktop/Cargo.toml`, add:

```toml
remo-bonjour = { path = "../remo-bonjour" }
```

- [ ] **Step 2: Introduce unified `DeviceInfo` and refactor `DeviceManager`**

Replace the current USB-only `DeviceHandle` with a transport-agnostic device model:

```rust
use std::net::SocketAddr;
use std::sync::Arc;

use dashmap::DashMap;
use remo_transport::Connection;
use remo_usbmuxd::{Device, DeviceEvent, UsbmuxClient};
use remo_bonjour::{BrowseEvent, ServiceBrowser, ServiceInfo};
use tokio::sync::mpsc;
use tracing::{info, warn, error};

use crate::rpc_client::RpcClient;

const DEFAULT_DEVICE_PORT: u16 = remo_protocol::DEFAULT_PORT;

/// Unique key for a discovered device.
#[derive(Debug, Clone, Hash, Eq, PartialEq)]
pub enum DeviceId {
    Usb(u32),
    Bonjour(String), // service instance name
}

impl std::fmt::Display for DeviceId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DeviceId::Usb(id) => write!(f, "usb:{id}"),
            DeviceId::Bonjour(name) => write!(f, "bonjour:{name}"),
        }
    }
}

/// Transport-agnostic device information.
#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub id: DeviceId,
    pub display_name: String,
    pub transport: DeviceTransport,
}

#[derive(Debug, Clone)]
pub enum DeviceTransport {
    Usb { device: Device },
    Bonjour { host: String, port: u16 },
    Manual { addr: SocketAddr },
}

impl DeviceInfo {
    pub fn addr(&self) -> Option<SocketAddr> {
        match &self.transport {
            DeviceTransport::Bonjour { host, port } => {
                use std::net::ToSocketAddrs;
                format!("{}:{}", host.trim_end_matches('.'), port)
                    .to_socket_addrs()
                    .ok()?
                    .next()
            }
            DeviceTransport::Manual { addr } => Some(*addr),
            DeviceTransport::Usb { .. } => None,
        }
    }
}

#[derive(Debug)]
pub enum DeviceManagerEvent {
    DeviceAdded(DeviceInfo),
    DeviceRemoved(DeviceId),
}

pub struct DeviceManager {
    devices: Arc<DashMap<DeviceId, DeviceInfo>>,
    event_tx: mpsc::Sender<DeviceManagerEvent>,
}

impl DeviceManager {
    pub fn new() -> (Self, mpsc::Receiver<DeviceManagerEvent>) {
        let (event_tx, event_rx) = mpsc::channel(64);
        (
            Self {
                devices: Arc::new(DashMap::new()),
                event_tx,
            },
            event_rx,
        )
    }

    /// Start USB device discovery via usbmuxd.
    pub async fn start_usb_discovery(&self) -> Result<(), remo_usbmuxd::UsbmuxError> {
        let client = UsbmuxClient::connect().await?;
        let (mut rx, _handle) = client.listen().await?;

        let devices = Arc::clone(&self.devices);
        let event_tx = self.event_tx.clone();

        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                match event {
                    DeviceEvent::Attached(dev) => {
                        let id = DeviceId::Usb(dev.device_id);
                        let info = DeviceInfo {
                            id: id.clone(),
                            display_name: format!("USB:{}", dev.serial),
                            transport: DeviceTransport::Usb { device: dev },
                        };
                        info!(device = %id, "USB device attached");
                        devices.insert(id.clone(), info.clone());
                        let _ = event_tx.send(DeviceManagerEvent::DeviceAdded(info)).await;
                    }
                    DeviceEvent::Detached { device_id } => {
                        let id = DeviceId::Usb(device_id);
                        info!(device = %id, "USB device detached");
                        devices.remove(&id);
                        let _ = event_tx.send(DeviceManagerEvent::DeviceRemoved(id)).await;
                    }
                    DeviceEvent::Unknown(_) => {}
                }
            }
        });

        Ok(())
    }

    /// Start Bonjour service discovery for simulators and Wi-Fi devices.
    pub fn start_bonjour_discovery(&self) -> Result<(), remo_bonjour::BonjourError> {
        let (_browser, mut rx) = ServiceBrowser::browse(remo_bonjour::SERVICE_TYPE)?;

        let devices = Arc::clone(&self.devices);
        let event_tx = self.event_tx.clone();

        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                match event {
                    BrowseEvent::Found(svc) => {
                        let id = DeviceId::Bonjour(svc.name.clone());
                        let info = DeviceInfo {
                            id: id.clone(),
                            display_name: svc.name.clone(),
                            transport: DeviceTransport::Bonjour {
                                host: svc.host.clone(),
                                port: svc.port,
                            },
                        };
                        info!(device = %id, host = %svc.host, port = svc.port, "Bonjour service found");
                        devices.insert(id.clone(), info.clone());
                        let _ = event_tx.send(DeviceManagerEvent::DeviceAdded(info)).await;
                    }
                    BrowseEvent::Lost { name } => {
                        let id = DeviceId::Bonjour(name);
                        info!(device = %id, "Bonjour service lost");
                        devices.remove(&id);
                        let _ = event_tx.send(DeviceManagerEvent::DeviceRemoved(id)).await;
                    }
                }
            }
        });

        Ok(())
    }

    /// Connect to a device by its DeviceId.
    pub async fn connect(
        &self,
        id: &DeviceId,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<RpcClient, Box<dyn std::error::Error>> {
        let info = self
            .devices
            .get(id)
            .ok_or_else(|| format!("device not found: {id}"))?
            .clone();

        match &info.transport {
            DeviceTransport::Usb { device } => {
                let client = UsbmuxClient::connect().await?;
                let tunnel = client
                    .connect_to_device(device.device_id, DEFAULT_DEVICE_PORT)
                    .await?;
                let label: SocketAddr = ([0, 0, 0, 0], DEFAULT_DEVICE_PORT).into();
                let conn = Connection::from_unix_stream(tunnel, label);
                Ok(RpcClient::from_connection(conn, event_tx)?)
            }
            DeviceTransport::Bonjour { host, port } => {
                let addr = info
                    .addr()
                    .ok_or_else(|| format!("cannot resolve {host}:{port}"))?;
                Ok(RpcClient::connect(addr, event_tx).await?)
            }
            DeviceTransport::Manual { addr } => {
                Ok(RpcClient::connect(*addr, event_tx).await?)
            }
        }
    }

    /// Connect directly to a known address (backward compat).
    pub async fn connect_direct(
        &self,
        addr: SocketAddr,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<RpcClient, Box<dyn std::error::Error>> {
        Ok(RpcClient::connect(addr, event_tx).await?)
    }

    /// Connect to a USB device by device_id (backward compat).
    pub async fn connect_to_device(
        &self,
        device_id: u32,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<RpcClient, Box<dyn std::error::Error>> {
        self.connect(&DeviceId::Usb(device_id), event_tx).await
    }

    /// List all currently known devices.
    pub fn list_devices(&self) -> Vec<DeviceInfo> {
        self.devices.iter().map(|e| e.value().clone()).collect()
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cargo check -p remo-desktop`

- [ ] **Step 4: Commit**

```bash
git add crates/remo-desktop/
git commit -m "feat(desktop): add Bonjour discovery + unified DeviceInfo model"
```

---

### Task 11: Update CLI to show Bonjour-discovered devices

**Files:**
- Modify: `crates/remo-cli/src/main.rs`

Add a `--scan` mode that uses both USB and Bonjour discovery.

- [ ] **Step 1: Update `cmd_devices()` to support Bonjour**

```rust
async fn cmd_devices() -> Result<()> {
    let (dm, mut event_rx) = DeviceManager::new();

    // Start USB discovery (may fail on machines without usbmuxd).
    if let Err(e) = dm.start_usb_discovery().await {
        eprintln!("USB discovery unavailable: {e}");
    }

    // Start Bonjour discovery.
    if let Err(e) = dm.start_bonjour_discovery() {
        eprintln!("Bonjour discovery unavailable: {e}");
    }

    println!("Scanning for devices (3 seconds)...\n");

    // Collect events for a few seconds.
    let _ = tokio::time::timeout(Duration::from_secs(3), async {
        while let Some(_event) = event_rx.recv().await {
            // Events processed by DeviceManager internally.
        }
    })
    .await;

    let devices = dm.list_devices();
    if devices.is_empty() {
        println!("No devices found.");
    } else {
        println!("{:<16} {:<30} {:<20}", "TYPE", "NAME", "ADDRESS");
        for dev in &devices {
            let addr_str = dev
                .addr()
                .map(|a| a.to_string())
                .unwrap_or_else(|| "N/A (USB tunnel)".into());
            let transport = match &dev.transport {
                DeviceTransport::Usb { .. } => "USB",
                DeviceTransport::Bonjour { .. } => "Bonjour",
                DeviceTransport::Manual { .. } => "Manual",
            };
            println!("{:<16} {:<30} {:<20}", transport, dev.display_name, addr_str);
        }
    }

    Ok(())
}
```

- [ ] **Step 2: Add necessary imports**

Add `use remo_desktop::device_manager::DeviceTransport;` and `use std::time::Duration;` at the top.

- [ ] **Step 3: Verify it compiles**

Run: `cargo check -p remo-cli`

- [ ] **Step 4: Commit**

```bash
git add crates/remo-cli/src/main.rs
git commit -m "feat(cli): remo devices shows USB + Bonjour-discovered devices"
```

---

## Chunk 5: Swift side updates + end-to-end test

### Task 12: Update Swift wrapper to expose dynamic port

**Files:**
- Modify: `swift/RemoSwift/Sources/RemoSwift/Remo.swift`

Add `remo_get_port()` declaration in the C header and expose it in Swift.

- [ ] **Step 1: Add `remo_get_port` to `remo.h`**

Check if `remo.h` exists and add:

```c
uint16_t remo_get_port(void);
```

- [ ] **Step 2: Update `Remo.swift` to expose port**

Add to the `Remo` class:

```swift
/// The actual port the server is listening on.
/// Returns 0 if the server has not started.
public static var port: UInt16 {
    remo_get_port()
}
```

- [ ] **Step 3: Commit**

```bash
git add swift/
git commit -m "feat(swift): expose Remo.port for dynamic port"
```

---

### Task 13: Workspace-level compile check + full test

- [ ] **Step 1: Run full workspace check**

Run: `cargo check --workspace`

- [ ] **Step 2: Run all tests**

Run: `cargo test --workspace`

- [ ] **Step 3: Run clippy**

Run: `cargo clippy --workspace -- -D warnings`

- [ ] **Step 4: Fix any issues found**

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: fix warnings and tests for bonjour-discovery"
```

---

## Summary of data flow

```
iOS Simulator                                macOS Desktop
┌──────────────────────┐                     ┌──────────────────────┐
│  RemoServer          │                     │  DeviceManager       │
│  bind(0.0.0.0:0)     │                     │                      │
│  actual_port = 49152  │                     │  start_bonjour_      │
│                      │                     │    discovery()       │
│  ServiceRegistration │   ── mDNS ──>       │                      │
│  "_remo._tcp"        │                     │  ServiceBrowser      │
│  port=49152          │                     │  "_remo._tcp"        │
│  name="RemoExample"  │                     │                      │
│                      │                     │  BrowseEvent::Found  │
│                      │                     │  → DeviceInfo        │
│                      │                     │    (Bonjour,         │
│                      │  <── TCP ───        │     host, port)      │
│                      │                     │                      │
│                      │                     │  dm.connect(&id)     │
│                      │                     │  → RpcClient         │
└──────────────────────┘                     └──────────────────────┘
```

When multiple simulators run simultaneously, each gets a unique OS-assigned port and advertises under a different Bonjour instance name (based on the device name, e.g. "iPhone 16 Pro" vs "iPad Air"). The macOS `ServiceBrowser` sees all of them and the `DeviceManager` tracks each as a separate `DeviceInfo` entry.
