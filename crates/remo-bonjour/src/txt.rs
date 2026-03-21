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
        // tells the implementation to allocate internally.
        #[allow(unsafe_code)]
        unsafe {
            sys::TXTRecordCreate(&mut inner, 0, std::ptr::null_mut());
        }
        Self { inner }
    }

    /// Insert a key-value pair. Value must be <= 255 bytes.
    pub fn set(&mut self, key: &str, value: &str) -> Result<(), BonjourError> {
        let key_c = CString::new(key)?;
        let value_bytes = value.as_bytes();
        let len = u8::try_from(value_bytes.len()).unwrap_or(255);

        // SAFETY: key_c is a valid C string; value_bytes is valid for len bytes.
        #[allow(unsafe_code)]
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
        #[allow(unsafe_code)]
        unsafe {
            sys::TXTRecordGetLength(&self.inner)
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub(crate) fn as_ptr(&self) -> *const std::ffi::c_void {
        // SAFETY: inner is a valid TXTRecordRef.
        #[allow(unsafe_code)]
        unsafe {
            sys::TXTRecordGetBytesPtr(&self.inner)
        }
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
        #[allow(unsafe_code)]
        unsafe {
            sys::TXTRecordDeallocate(&mut self.inner);
        }
    }
}
