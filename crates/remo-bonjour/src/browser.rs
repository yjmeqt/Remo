use std::ffi::CString;
use std::os::fd::BorrowedFd;

use tokio::io::unix::AsyncFd;
use tokio::io::Interest;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tracing::{debug, error, info, warn};

use crate::error::BonjourError;
use crate::sys;
use crate::SendableRef;

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
    pub metadata: ServiceMetadata,
}

/// Optional metadata surfaced through Bonjour TXT records.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ServiceMetadata {
    pub device_name: Option<String>,
    pub device_model: Option<String>,
    pub app_name: Option<String>,
    pub bundle_id: Option<String>,
    pub platform: Option<String>,
}

impl ServiceInfo {
    /// For simulators on localhost, resolve to a `SocketAddr`.
    pub fn socket_addr(&self) -> Option<std::net::SocketAddr> {
        socket_addr_for_host(&self.host, self.port)
    }
}

pub fn socket_addr_for_host(host: &str, port: u16) -> Option<std::net::SocketAddr> {
    use std::net::ToSocketAddrs;

    let addrs: Vec<_> = format!("{}:{}", host.trim_end_matches('.'), port)
        .to_socket_addrs()
        .ok()?
        .collect();

    addrs
        .iter()
        .copied()
        .find(|addr| addr.ip().is_loopback() && addr.is_ipv4())
        .or_else(|| addrs.iter().copied().find(|addr| addr.ip().is_loopback()))
        .or_else(|| addrs.into_iter().next())
}

fn parse_txt_metadata(txt_record: &[u8]) -> ServiceMetadata {
    let mut metadata = ServiceMetadata::default();
    let mut cursor = 0;

    while cursor < txt_record.len() {
        let len = usize::from(txt_record[cursor]);
        cursor += 1;

        if len == 0 || cursor + len > txt_record.len() {
            break;
        }

        let entry = &txt_record[cursor..cursor + len];
        cursor += len;

        let Some(separator) = entry.iter().position(|byte| *byte == b'=') else {
            continue;
        };
        let (key, value) = entry.split_at(separator);
        let value = &value[1..];

        let Ok(key) = std::str::from_utf8(key) else {
            continue;
        };
        let Ok(value) = std::str::from_utf8(value) else {
            continue;
        };
        let value = value.trim();
        if value.is_empty() {
            continue;
        }

        match key {
            "device_name" => metadata.device_name = Some(value.to_string()),
            "device_model" => metadata.device_model = Some(value.to_string()),
            "app_name" => metadata.app_name = Some(value.to_string()),
            "bundle_id" => metadata.bundle_id = Some(value.to_string()),
            "platform" => metadata.platform = Some(value.to_string()),
            _ => {}
        }
    }

    metadata
}

/// Browses the local network for Bonjour services of a given type.
#[must_use = "dropping a ServiceBrowser immediately stops discovery"]
pub struct ServiceBrowser {
    sd_ref: sys::DNSServiceRef,
    ctx_ptr: *mut BrowseContext,
    event_loop: Option<JoinHandle<()>>,
}

// SAFETY: Same rationale as ServiceRegistration — single-threaded access
// pattern (tokio task + drop). ctx_ptr is only reclaimed after abort.
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
        let ctx_ptr = Box::into_raw(ctx);

        let mut sd_ref: sys::DNSServiceRef = std::ptr::null_mut();

        // SAFETY: reg_type is a valid C string; sd_ref is an out-pointer.
        // ctx_ptr is a Box we intentionally leak; reclaimed in Drop.
        let err = unsafe {
            sys::DNSServiceBrowse(
                &mut sd_ref,
                0, // no flags
                0, // all interfaces
                reg_type.as_ptr(),
                std::ptr::null(), // default domain
                browse_callback,
                ctx_ptr as *mut std::ffi::c_void,
            )
        };
        BonjourError::from_code(err)?;

        info!(service_type, "bonjour browse started");

        let event_loop = spawn_event_loop(sd_ref);

        let browser = Self {
            sd_ref,
            ctx_ptr,
            event_loop: Some(event_loop),
        };

        Ok((browser, event_rx))
    }
}

/// Spawn a tokio task that processes dns_sd events on the socket.
#[allow(unsafe_code)]
fn spawn_event_loop(sd_ref: sys::DNSServiceRef) -> JoinHandle<()> {
    let sendable = SendableRef::new(sd_ref);

    // SAFETY: DNSServiceRefSockFD returns a valid fd.
    let fd = unsafe { sys::DNSServiceRefSockFD(sendable.ptr()) };

    tokio::spawn(async move {
        // SAFETY: fd is valid for the lifetime of sd_ref.
        let async_fd =
            match unsafe { AsyncFd::with_interest(BorrowedFd::borrow_raw(fd), Interest::READABLE) }
            {
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
    })
}

impl Drop for ServiceBrowser {
    #[allow(unsafe_code)]
    fn drop(&mut self) {
        if let Some(handle) = self.event_loop.take() {
            handle.abort();
        }
        if !self.sd_ref.is_null() {
            // SAFETY: event loop is aborted above, so no concurrent access.
            unsafe { sys::DNSServiceRefDeallocate(self.sd_ref) };
        }
        if !self.ctx_ptr.is_null() {
            // SAFETY: ctx_ptr was created via Box::into_raw in browse().
            // Callbacks only borrow it; we own it.
            unsafe { drop(Box::from_raw(self.ctx_ptr)) };
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
    // (owned by the ServiceBrowser, reclaimed in Drop).
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
    txt_len: u16,
    txt_record: *const std::os::raw::c_uchar,
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
        metadata: parse_txt_metadata(std::slice::from_raw_parts(
            txt_record.cast(),
            usize::from(txt_len),
        )),
    };

    let _ = ctx.event_tx.try_send(BrowseEvent::Found(info));
}

#[cfg(test)]
mod tests {
    use super::{parse_txt_metadata, socket_addr_for_host, ServiceMetadata};

    fn encode_txt(entries: &[(&str, &str)]) -> Vec<u8> {
        let mut bytes = Vec::new();
        for (key, value) in entries {
            let entry = format!("{key}={value}");
            bytes.push(u8::try_from(entry.len()).expect("TXT entry should fit in one byte"));
            bytes.extend_from_slice(entry.as_bytes());
        }
        bytes
    }

    #[test]
    fn prefers_ipv4_loopback_for_localhost() {
        let addr = socket_addr_for_host("localhost", 65425).expect("localhost should resolve");
        assert!(addr.ip().is_loopback());
        assert!(addr.is_ipv4());
        assert_eq!(addr.port(), 65425);
    }

    #[test]
    fn parses_supported_txt_metadata_fields() {
        let txt = encode_txt(&[
            ("device_name", "iPhone 17 Pro"),
            ("app_name", "RemoExample"),
            ("bundle_id", "com.example.remo"),
            ("platform", "simulator"),
        ]);

        let metadata = parse_txt_metadata(&txt);

        assert_eq!(
            metadata,
            ServiceMetadata {
                device_name: Some("iPhone 17 Pro".into()),
                device_model: None,
                app_name: Some("RemoExample".into()),
                bundle_id: Some("com.example.remo".into()),
                platform: Some("simulator".into()),
            }
        );
    }
}
