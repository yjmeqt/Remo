#[allow(unsafe_code)]
pub mod browser;
pub mod error;
#[allow(unsafe_code)]
pub mod register;
#[allow(unsafe_code)]
pub mod sys;
#[allow(unsafe_code)]
pub mod txt;

pub use browser::{BrowseEvent, ServiceBrowser, ServiceInfo};
pub use error::BonjourError;
pub use register::ServiceRegistration;
pub use txt::TxtRecord;

/// Bonjour service type for Remo.
pub const SERVICE_TYPE: &str = "_remo._tcp";

/// Wrapper making `DNSServiceRef` transferable across threads.
/// Stores as `usize` so no raw-pointer auto-trait issues arise.
///
/// SAFETY: Apple docs state that a `DNSServiceRef` can be used from any
/// single thread; callers must ensure no concurrent access.
#[derive(Clone, Copy)]
pub(crate) struct SendableRef(usize);

impl SendableRef {
    pub(crate) fn new(ptr: sys::DNSServiceRef) -> Self {
        Self(ptr as usize)
    }

    pub(crate) fn ptr(self) -> sys::DNSServiceRef {
        self.0 as sys::DNSServiceRef
    }
}
