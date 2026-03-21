use crate::sys::DNSServiceErrorType;

#[derive(Debug, thiserror::Error)]
pub enum BonjourError {
    #[error("dns_sd error: code {0}")]
    DnsService(DNSServiceErrorType),

    #[error("service name contained interior null byte")]
    NullByte(#[from] std::ffi::NulError),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("TXT record value too long ({0} bytes, max 255)")]
    ValueTooLong(usize),
}

impl BonjourError {
    pub(crate) fn from_code(code: DNSServiceErrorType) -> Result<(), Self> {
        if code == crate::sys::kDNSServiceErr_NoError {
            Ok(())
        } else {
            Err(Self::DnsService(code))
        }
    }
}
