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
