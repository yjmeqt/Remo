//! Raw FFI bindings to Apple's `dns_sd.h` (part of libSystem).
//!
//! These functions are available on macOS and iOS without additional
//! linker flags — `dns_sd` is part of the always-linked libSystem.

#![allow(non_camel_case_types, non_upper_case_globals)]

use std::os::raw::{c_char, c_int, c_uchar, c_void};

pub type DNSServiceRef = *mut c_void;
pub type DNSServiceFlags = u32;
pub type DNSServiceErrorType = i32;

pub const kDNSServiceFlagsAdd: DNSServiceFlags = 0x2;
pub const kDNSServiceErr_NoError: DNSServiceErrorType = 0;

// ---------------------------------------------------------------------------
// Callback types
// ---------------------------------------------------------------------------

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
    port: u16,
    txt_len: u16,
    txt_record: *const c_uchar,
    context: *mut c_void,
);

// ---------------------------------------------------------------------------
// TXT record opaque struct (16 bytes on Apple platforms)
// ---------------------------------------------------------------------------

#[repr(C)]
pub struct TXTRecordRef {
    pub(crate) _opaque: [u8; 16],
}

// ---------------------------------------------------------------------------
// Extern functions
// ---------------------------------------------------------------------------

extern "C" {
    pub fn DNSServiceRegister(
        sd_ref: *mut DNSServiceRef,
        flags: DNSServiceFlags,
        interface_index: u32,
        name: *const c_char,
        reg_type: *const c_char,
        domain: *const c_char,
        host: *const c_char,
        port: u16,
        txt_len: u16,
        txt_record: *const c_void,
        callback: DNSServiceRegisterReply,
        context: *mut c_void,
    ) -> DNSServiceErrorType;

    pub fn DNSServiceBrowse(
        sd_ref: *mut DNSServiceRef,
        flags: DNSServiceFlags,
        interface_index: u32,
        reg_type: *const c_char,
        domain: *const c_char,
        callback: DNSServiceBrowseReply,
        context: *mut c_void,
    ) -> DNSServiceErrorType;

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

    pub fn DNSServiceRefSockFD(sd_ref: DNSServiceRef) -> c_int;

    pub fn DNSServiceProcessResult(sd_ref: DNSServiceRef) -> DNSServiceErrorType;

    pub fn DNSServiceRefDeallocate(sd_ref: DNSServiceRef);

    pub fn TXTRecordCreate(txt_record: *mut TXTRecordRef, buffer_len: u16, buffer: *mut c_void);

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
