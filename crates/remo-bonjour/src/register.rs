use std::ffi::CString;
use std::os::fd::BorrowedFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tokio::io::unix::AsyncFd;
use tokio::io::Interest;
use tracing::{debug, error, info};

use crate::error::BonjourError;
use crate::sys;
use crate::txt::TxtRecord;

/// Wrapper making `DNSServiceRef` transferable across threads.
/// Stores as `usize` so no raw-pointer auto-trait issues arise.
/// SAFETY: Apple docs state that a DNSServiceRef can be used from any
/// single thread; we never access it concurrently.
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

/// A registered Bonjour service. Dropping this de-registers the service.
pub struct ServiceRegistration {
    sd_ref: sys::DNSServiceRef,
    _registered: Arc<AtomicBool>,
}

// SAFETY: DNSServiceRef is thread-safe per Apple documentation —
// a single ref can be used from one thread at a time. We only
// access it from the tokio task or on drop (never concurrently).
#[allow(unsafe_code)]
unsafe impl Send for ServiceRegistration {}
// SAFETY: ServiceRegistration is only accessed from one context at a time
// (the tokio event loop task or drop).
#[allow(unsafe_code)]
unsafe impl Sync for ServiceRegistration {}

impl ServiceRegistration {
    /// Advertise a Bonjour service.
    ///
    /// - `service_type`: e.g. `"_remo._tcp"`
    /// - `port`: the TCP port to advertise (host byte order)
    /// - `name`: instance name, or `None` for the system default
    /// - `txt`: optional TXT record with metadata
    #[allow(unsafe_code)]
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

        // SAFETY: All C strings are valid; sd_ref is out-pointer written by dns_sd.
        // ctx is an Arc we intentionally leak; reclaimed in the callback.
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

    /// Spawn a tokio task that processes dns_sd events on the socket.
    #[allow(unsafe_code)]
    fn spawn_event_loop(&self) {
        let sendable = SendableRef::new(self.sd_ref);

        // SAFETY: DNSServiceRefSockFD returns a valid fd for the lifetime of sd_ref.
        let fd = unsafe { sys::DNSServiceRefSockFD(sendable.ptr()) };

        tokio::spawn(async move {
            // SAFETY: fd is valid for the lifetime of sd_ref; we borrow it
            // without taking ownership (the DNSServiceRef owns the socket).
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
                        // SAFETY: sendable.ptr() is valid; socket has been signalled readable.
                        let err = unsafe { sys::DNSServiceProcessResult(sendable.ptr()) };
                        if err != sys::kDNSServiceErr_NoError {
                            error!(err, "DNSServiceProcessResult failed");
                            break;
                        }
                        guard.clear_ready();
                    }
                    Err(e) => {
                        debug!("bonjour register fd error: {e}");
                        break;
                    }
                }
            }
        });
    }
}

impl Drop for ServiceRegistration {
    #[allow(unsafe_code)]
    fn drop(&mut self) {
        if !self.sd_ref.is_null() {
            // SAFETY: sd_ref is valid and we own it.
            unsafe { sys::DNSServiceRefDeallocate(self.sd_ref) };
        }
    }
}

/// C callback invoked by dns_sd when registration completes or fails.
#[allow(unsafe_code)]
unsafe extern "C" fn register_callback(
    _sd_ref: sys::DNSServiceRef,
    _flags: sys::DNSServiceFlags,
    error_code: sys::DNSServiceErrorType,
    name: *const std::os::raw::c_char,
    _reg_type: *const std::os::raw::c_char,
    _domain: *const std::os::raw::c_char,
    context: *mut std::ffi::c_void,
) {
    // SAFETY: context was created via Arc::into_raw in register().
    // We reconstruct it to peek, then forget to avoid dropping.
    let registered = unsafe { Arc::from_raw(context as *const AtomicBool) };

    if error_code == sys::kDNSServiceErr_NoError {
        let name_str = if name.is_null() {
            "<unknown>"
        } else {
            // SAFETY: name is a valid C string provided by dns_sd.
            unsafe { std::ffi::CStr::from_ptr(name) }
                .to_str()
                .unwrap_or("<invalid>")
        };
        info!(name = name_str, "bonjour service registered");
        registered.store(true, Ordering::SeqCst);
    } else {
        error!(error_code, "bonjour registration failed");
    }

    // Don't drop — ServiceRegistration owns the Arc.
    std::mem::forget(registered);
}
