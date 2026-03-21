use std::ffi::CString;
use std::os::fd::BorrowedFd;

use tokio::io::unix::AsyncFd;
use tokio::io::Interest;
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

use crate::error::BonjourError;
use crate::sys;

/// Wrapper making `DNSServiceRef` transferable across threads.
/// Stores as `usize` so no raw-pointer auto-trait issues arise.
#[derive(Clone, Copy)]
struct SendableRef(usize);

impl SendableRef {
    fn new(ptr: sys::DNSServiceRef) -> Self {
        Self(ptr as usize)
    }

    fn ptr(self) -> sys::DNSServiceRef {
        self.0 as sys::DNSServiceRef
    }
}

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
    pub fn socket_addr(&self) -> Option<std::net::SocketAddr> {
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

// SAFETY: Same rationale as ServiceRegistration — single-threaded access
// pattern (tokio task + drop).
#[allow(unsafe_code)]
unsafe impl Send for ServiceBrowser {}
// SAFETY: ServiceBrowser is only accessed from one context at a time
// (the tokio event loop task or drop).
#[allow(unsafe_code)]
unsafe impl Sync for ServiceBrowser {}

struct BrowseContext {
    event_tx: mpsc::Sender<BrowseEvent>,
    service_type: CString,
}

impl ServiceBrowser {
    /// Start browsing for services of the given type.
    /// Returns a receiver that emits `BrowseEvent`s.
    #[allow(unsafe_code)]
    pub fn browse(service_type: &str) -> Result<(Self, mpsc::Receiver<BrowseEvent>), BonjourError> {
        let reg_type = CString::new(service_type)?;
        let (event_tx, event_rx) = mpsc::channel(64);

        let ctx = Box::new(BrowseContext {
            event_tx,
            service_type: reg_type.clone(),
        });
        let ctx_ptr = Box::into_raw(ctx) as *mut std::ffi::c_void;

        let mut sd_ref: sys::DNSServiceRef = std::ptr::null_mut();

        // SAFETY: reg_type is a valid C string; sd_ref is an out-pointer.
        // ctx_ptr is a Box we intentionally leak; it lives as long as the browser.
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

    #[allow(unsafe_code)]
    fn spawn_event_loop(&self) {
        let sendable = SendableRef::new(self.sd_ref);

        // SAFETY: DNSServiceRefSockFD returns a valid fd.
        let fd = unsafe { sys::DNSServiceRefSockFD(sendable.ptr()) };

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
                        // SAFETY: sendable.ptr() is valid; socket is readable.
                        let err = unsafe { sys::DNSServiceProcessResult(sendable.ptr()) };
                        if err != sys::kDNSServiceErr_NoError {
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
    #[allow(unsafe_code)]
    fn drop(&mut self) {
        if !self.sd_ref.is_null() {
            // SAFETY: we own sd_ref.
            unsafe { sys::DNSServiceRefDeallocate(self.sd_ref) };
        }
    }
}

// ---------------------------------------------------------------------------
// C callbacks
// ---------------------------------------------------------------------------

/// C callback for browse events from dns_sd.
#[allow(unsafe_code)]
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
    if error_code != sys::kDNSServiceErr_NoError {
        error!(error_code, "browse callback error");
        return;
    }

    // SAFETY: context is a valid BrowseContext pointer that outlives this callback
    // (owned by the ServiceBrowser via Box::into_raw).
    let ctx = unsafe { &*(context as *const BrowseContext) };

    // SAFETY: service_name is a valid C string from dns_sd.
    let name = unsafe { std::ffi::CStr::from_ptr(service_name) }
        .to_string_lossy()
        .into_owned();

    let is_add = (flags & sys::kDNSServiceFlagsAdd) != 0;

    if is_add {
        info!(name = %name, "bonjour service found, resolving...");

        // SAFETY: reply_domain is a valid C string from dns_sd.
        let domain = unsafe { std::ffi::CStr::from_ptr(reply_domain) };
        let domain_owned = domain.to_owned();
        let Ok(name_c) = CString::new(name.clone()) else {
            return;
        };

        let resolve_ctx = Box::new(ResolveContext {
            name: name.clone(),
            event_tx: ctx.event_tx.clone(),
        });
        let resolve_ctx_ptr = Box::into_raw(resolve_ctx) as *mut std::ffi::c_void;

        let mut resolve_ref: sys::DNSServiceRef = std::ptr::null_mut();

        // SAFETY: All strings are valid C strings; resolve_ref is an out-pointer.
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

        if err != sys::kDNSServiceErr_NoError {
            error!(err, name = %name, "DNSServiceResolve failed");
            // SAFETY: reclaim the leaked context since resolve won't use it.
            let _ = unsafe { Box::from_raw(resolve_ctx_ptr as *mut ResolveContext) };
            return;
        }

        // Process the resolve result synchronously — dns_sd calls the
        // callback once and then we can deallocate the resolve ref.
        // SAFETY: resolve_ref is valid.
        let resolve_err = unsafe { sys::DNSServiceProcessResult(resolve_ref) };
        if resolve_err != sys::kDNSServiceErr_NoError {
            warn!(resolve_err, "resolve process result failed");
        }
        // SAFETY: resolve_ref is valid.
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

/// C callback for resolve events from dns_sd.
#[allow(unsafe_code)]
unsafe extern "C" fn resolve_callback(
    _sd_ref: sys::DNSServiceRef,
    _flags: sys::DNSServiceFlags,
    interface_index: u32,
    error_code: sys::DNSServiceErrorType,
    _fullname: *const std::os::raw::c_char,
    hosttarget: *const std::os::raw::c_char,
    port: u16,
    _txt_len: u16,
    _txt_record: *const std::os::raw::c_uchar,
    context: *mut std::ffi::c_void,
) {
    // SAFETY: context was created via Box::into_raw in browse_callback.
    // This is a one-shot resolve, so we take ownership back.
    let ctx = unsafe { Box::from_raw(context as *mut ResolveContext) };

    if error_code != sys::kDNSServiceErr_NoError {
        error!(error_code, name = %ctx.name, "resolve callback error");
        return;
    }

    // SAFETY: hosttarget is a valid C string from dns_sd.
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
