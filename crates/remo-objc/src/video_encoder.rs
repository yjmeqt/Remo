//! H.264 hardware encoder via VideoToolbox.
//!
//! Wraps `VTCompressionSession` to encode `CVPixelBuffer` frames into H.264 NAL units.
//! The encoder runs asynchronously — encoded frames arrive via a callback on an internal
//! VideoToolbox thread, then forwarded through a bounded `std::sync::mpsc` channel.

use std::sync::mpsc;

/// Configuration for the H.264 encoder.
#[derive(Debug, Clone)]
pub struct EncoderConfig {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate: u32,           // bits per second
    pub keyframe_interval: u32, // frames between IDR
}

impl Default for EncoderConfig {
    fn default() -> Self {
        Self {
            width: 0,
            height: 0,
            fps: 30,
            bitrate: 4_000_000,
            keyframe_interval: 60,
        }
    }
}

/// An encoded H.264 frame produced by the encoder.
#[derive(Debug, Clone)]
pub struct EncodedFrame {
    pub data: Vec<u8>,     // Annex-B formatted NAL units
    pub timestamp_us: u64, // Presentation timestamp in microseconds
    pub is_keyframe: bool,
    pub is_codec_config: bool, // true if this contains only SPS/PPS
}

/// Bounded channel capacity for encoded frames.
/// When full, non-keyframes are dropped (flow control).
#[allow(dead_code)]
const ENCODED_CHANNEL_CAPACITY: usize = 8;

#[cfg(all(target_vendor = "apple", feature = "uikit"))]
mod apple {
    use super::*;
    use std::ffi::c_void;
    use std::ptr;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;

    // ---------------------------------------------------------------------------
    // CoreMedia / CoreVideo / VideoToolbox C FFI types
    // ---------------------------------------------------------------------------

    type OSStatus = i32;
    type CFAllocatorRef = *const c_void;
    type CFDictionaryRef = *const c_void;
    type CFStringRef = *const c_void;
    type CFTypeRef = *const c_void;
    type CFBooleanRef = *const c_void;
    type CFNumberRef = *const c_void;
    type CVPixelBufferRef = *const c_void;
    type CMSampleBufferRef = *const c_void;
    type CMFormatDescriptionRef = *const c_void;
    type CMBlockBufferRef = *const c_void;
    type VTCompressionSessionRef = *mut c_void;
    type CFArrayRef = *const c_void;

    #[repr(C)]
    #[derive(Copy, Clone)]
    struct CMTimeRepr {
        value: i64,
        timescale: i32,
        flags: u32,
        epoch: i64,
    }

    type VTCompressionOutputCallback = unsafe extern "C" fn(
        output_callback_ref_con: *mut c_void,
        source_frame_ref_con: *mut c_void,
        status: OSStatus,
        info_flags: u32,
        sample_buffer: CMSampleBufferRef,
    );

    #[link(name = "VideoToolbox", kind = "framework")]
    extern "C" {
        fn VTCompressionSessionCreate(
            allocator: CFAllocatorRef,
            width: i32,
            height: i32,
            codec_type: u32,
            encoder_specification: CFDictionaryRef,
            source_image_buffer_attributes: CFDictionaryRef,
            compressed_data_allocator: CFAllocatorRef,
            output_callback: VTCompressionOutputCallback,
            output_callback_ref_con: *mut c_void,
            compression_session_out: *mut VTCompressionSessionRef,
        ) -> OSStatus;

        fn VTCompressionSessionEncodeFrame(
            session: VTCompressionSessionRef,
            image_buffer: CVPixelBufferRef,
            presentation_time_stamp: CMTimeRepr,
            duration: CMTimeRepr,
            frame_properties: CFDictionaryRef,
            source_frame_ref_con: *mut c_void,
            info_flags_out: *mut u32,
        ) -> OSStatus;

        fn VTCompressionSessionCompleteFrames(
            session: VTCompressionSessionRef,
            complete_until_presentation_time_stamp: CMTimeRepr,
        ) -> OSStatus;

        fn VTCompressionSessionInvalidate(session: VTCompressionSessionRef);

        fn VTSessionSetProperty(
            session: VTCompressionSessionRef,
            property_key: CFStringRef,
            property_value: CFTypeRef,
        ) -> OSStatus;

        fn VTCompressionSessionPrepareToEncodeFrames(session: VTCompressionSessionRef) -> OSStatus;
    }

    #[link(name = "CoreMedia", kind = "framework")]
    extern "C" {
        fn CMSampleBufferGetFormatDescription(sbuf: CMSampleBufferRef) -> CMFormatDescriptionRef;
        fn CMSampleBufferGetDataBuffer(sbuf: CMSampleBufferRef) -> CMBlockBufferRef;
        fn CMSampleBufferGetPresentationTimeStamp(sbuf: CMSampleBufferRef) -> CMTimeRepr;
        fn CMSampleBufferGetSampleAttachmentsArray(
            sbuf: CMSampleBufferRef,
            create_if_necessary: bool,
        ) -> CFArrayRef;
        fn CMBlockBufferGetDataLength(block: CMBlockBufferRef) -> usize;
        fn CMBlockBufferCopyDataBytes(
            the_buffer: CMBlockBufferRef,
            offset_to_data: usize,
            data_length: usize,
            destination: *mut u8,
        ) -> OSStatus;
        fn CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            video_desc: CMFormatDescriptionRef,
            parameter_set_index: usize,
            parameter_set_pointer_out: *mut *const u8,
            parameter_set_size_out: *mut usize,
            parameter_set_count_out: *mut usize,
            nal_unit_header_length_out: *mut i32,
        ) -> OSStatus;
        fn CMTimeMake(value: i64, timescale: i32) -> CMTimeRepr;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFRelease(cf: CFTypeRef);
        fn CFNumberCreate(
            allocator: CFAllocatorRef,
            the_type: i64,
            value_ptr: *const c_void,
        ) -> CFNumberRef;
        fn CFArrayGetCount(the_array: CFArrayRef) -> isize;
        fn CFArrayGetValueAtIndex(the_array: CFArrayRef, idx: isize) -> *const c_void;
        fn CFDictionaryGetValue(the_dict: *const c_void, key: *const c_void) -> *const c_void;

        static kCFAllocatorDefault: CFAllocatorRef;
        static kCFBooleanTrue: CFBooleanRef;
        static kCFBooleanFalse: CFBooleanRef;
    }

    // VideoToolbox property keys
    extern "C" {
        static kVTCompressionPropertyKey_RealTime: CFStringRef;
        static kVTCompressionPropertyKey_ProfileLevel: CFStringRef;
        static kVTCompressionPropertyKey_AverageBitRate: CFStringRef;
        static kVTCompressionPropertyKey_MaxKeyFrameInterval: CFStringRef;
        static kVTCompressionPropertyKey_AllowFrameReordering: CFStringRef;
        static kVTProfileLevel_H264_Main_AutoLevel: CFStringRef;
    }

    // CoreMedia attachment key
    extern "C" {
        static kCMSampleAttachmentKey_NotSync: CFStringRef;
    }

    const K_CM_VIDEO_CODEC_TYPE_H264: u32 = 0x61766331; // 'avc1'
    const K_CF_NUMBER_SINT32_TYPE: i64 = 3;

    struct EncoderInner {
        tx: mpsc::SyncSender<EncodedFrame>,
        running: AtomicBool,
    }

    /// H.264 hardware encoder.
    pub struct H264Encoder {
        session: VTCompressionSessionRef,
        inner: Arc<EncoderInner>,
        frame_count: u64,
        config: EncoderConfig,
    }

    // Safety: VTCompressionSession is thread-safe for encoding
    unsafe impl Send for H264Encoder {}

    impl H264Encoder {
        /// Create and configure a new H.264 encoder.
        ///
        /// Returns the encoder and a bounded receiver for encoded frames.
        /// When the channel is full, non-keyframes are dropped (flow control).
        pub fn new(config: EncoderConfig) -> Result<(Self, mpsc::Receiver<EncodedFrame>), String> {
            let (tx, rx) = mpsc::sync_channel(ENCODED_CHANNEL_CAPACITY);

            let inner = Arc::new(EncoderInner {
                tx,
                running: AtomicBool::new(true),
            });

            let mut session: VTCompressionSessionRef = ptr::null_mut();
            let inner_ptr = Arc::into_raw(Arc::clone(&inner)) as *mut c_void;

            let status = unsafe {
                VTCompressionSessionCreate(
                    kCFAllocatorDefault,
                    config.width as i32,
                    config.height as i32,
                    K_CM_VIDEO_CODEC_TYPE_H264,
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    output_callback,
                    inner_ptr,
                    &mut session,
                )
            };

            if status != 0 {
                // Reclaim the Arc we gave to VT via into_raw. Combined with
                // `inner` (the original Arc) dropping at function exit, this
                // brings the ref count to zero and frees the allocation.
                unsafe { Arc::from_raw(inner_ptr as *const EncoderInner) };
                return Err(format!("VTCompressionSessionCreate failed: {status}"));
            }

            unsafe {
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_RealTime,
                    kCFBooleanTrue as CFTypeRef,
                );
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_ProfileLevel,
                    kVTProfileLevel_H264_Main_AutoLevel as CFTypeRef,
                );
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_AllowFrameReordering,
                    kCFBooleanFalse as CFTypeRef,
                );

                let bitrate = config.bitrate as i32;
                let bitrate_num = CFNumberCreate(
                    kCFAllocatorDefault,
                    K_CF_NUMBER_SINT32_TYPE,
                    &bitrate as *const i32 as *const c_void,
                );
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_AverageBitRate,
                    bitrate_num as CFTypeRef,
                );
                CFRelease(bitrate_num as CFTypeRef);

                let kfi = config.keyframe_interval as i32;
                let kfi_num = CFNumberCreate(
                    kCFAllocatorDefault,
                    K_CF_NUMBER_SINT32_TYPE,
                    &kfi as *const i32 as *const c_void,
                );
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_MaxKeyFrameInterval,
                    kfi_num as CFTypeRef,
                );
                CFRelease(kfi_num as CFTypeRef);

                VTCompressionSessionPrepareToEncodeFrames(session);
            }

            Ok((
                Self {
                    session,
                    inner,
                    frame_count: 0,
                    config,
                },
                rx,
            ))
        }

        /// Encode a CVPixelBuffer. The result arrives asynchronously via the receiver.
        ///
        /// # Safety
        /// `pixel_buffer` must be a valid `CVPixelBufferRef`.
        pub unsafe fn encode_frame(
            &mut self,
            pixel_buffer: CVPixelBufferRef,
        ) -> Result<(), String> {
            let pts = CMTimeMake(self.frame_count as i64, self.config.fps as i32);
            let duration = CMTimeMake(1, self.config.fps as i32);

            let status = VTCompressionSessionEncodeFrame(
                self.session,
                pixel_buffer,
                pts,
                duration,
                ptr::null(),
                ptr::null_mut(),
                ptr::null_mut(),
            );

            self.frame_count += 1;

            if status != 0 {
                Err(format!("VTCompressionSessionEncodeFrame failed: {status}"))
            } else {
                Ok(())
            }
        }

        /// Flush any pending frames.
        pub fn flush(&self) -> Result<(), String> {
            let time = unsafe { CMTimeMake(i64::MAX, 1) };
            let status = unsafe { VTCompressionSessionCompleteFrames(self.session, time) };
            if status != 0 {
                Err(format!(
                    "VTCompressionSessionCompleteFrames failed: {status}"
                ))
            } else {
                Ok(())
            }
        }

        /// Stop the encoder and release resources.
        pub fn stop(&self) {
            if self.inner.running.swap(false, Ordering::SeqCst) {
                unsafe {
                    VTCompressionSessionInvalidate(self.session);
                }
            }
        }
    }

    impl Drop for H264Encoder {
        fn drop(&mut self) {
            self.stop();
        }
    }

    /// VTCompressionSession output callback — called on an internal VT thread.
    ///
    /// Uses `try_send` (non-async) because this is a synchronous C callback
    /// with no tokio runtime context available.
    unsafe extern "C" fn output_callback(
        output_callback_ref_con: *mut c_void,
        _source_frame_ref_con: *mut c_void,
        status: OSStatus,
        _info_flags: u32,
        sample_buffer: CMSampleBufferRef,
    ) {
        if status != 0 || sample_buffer.is_null() {
            return;
        }

        let inner = &*(output_callback_ref_con as *const EncoderInner);
        if !inner.running.load(Ordering::Relaxed) {
            return;
        }

        let is_keyframe = is_sample_keyframe(sample_buffer);
        let format_desc = CMSampleBufferGetFormatDescription(sample_buffer);

        // Extract and send SPS/PPS on keyframes
        if is_keyframe && !format_desc.is_null() {
            if let Some(config_frame) = extract_parameter_sets(format_desc) {
                // Keyframe config: always try to send (never drop)
                let _ = inner.tx.try_send(config_frame);
            }
        }

        // Extract encoded NAL units
        if let Some(frame) = extract_encoded_data(sample_buffer, is_keyframe) {
            match inner.tx.try_send(frame) {
                Ok(()) => {}
                Err(mpsc::TrySendError::Full(dropped)) => {
                    // Flow control: drop non-keyframes when channel is full
                    if dropped.is_keyframe {
                        // Block the VT thread briefly. If the consumer is persistently slow,
                        // this stalls frame production — acceptable since the alternative
                        // (dropping keyframes) would leave the decoder unable to recover
                        // until the next IDR interval.
                        let _ = inner.tx.send(dropped);
                    }
                    // else: non-keyframe dropped, acceptable
                }
                Err(mpsc::TrySendError::Disconnected(_)) => {}
            }
        }
    }

    /// Check if a sample buffer is a keyframe by inspecting attachments.
    unsafe fn is_sample_keyframe(sample_buffer: CMSampleBufferRef) -> bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample_buffer, false);
        if attachments.is_null() || CFArrayGetCount(attachments) == 0 {
            // No attachments means it's a keyframe (first frame)
            return true;
        }

        let dict = CFArrayGetValueAtIndex(attachments, 0);
        if dict.is_null() {
            return true;
        }

        // kCMSampleAttachmentKey_NotSync == true means NOT a keyframe
        let not_sync = CFDictionaryGetValue(dict, kCMSampleAttachmentKey_NotSync as *const c_void);
        if not_sync.is_null() {
            return true; // key absent → sync sample (keyframe)
        }

        // If NotSync is kCFBooleanTrue, this is NOT a keyframe
        not_sync != kCFBooleanTrue as *const c_void
    }

    /// Extract SPS and PPS from the format description, return as Annex-B.
    unsafe fn extract_parameter_sets(format_desc: CMFormatDescriptionRef) -> Option<EncodedFrame> {
        let mut sps_ptr: *const u8 = ptr::null();
        let mut sps_len: usize = 0;
        let mut pps_ptr: *const u8 = ptr::null();
        let mut pps_len: usize = 0;
        let mut count: usize = 0;

        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format_desc,
            0,
            &mut sps_ptr,
            &mut sps_len,
            &mut count,
            ptr::null_mut(),
        );
        if status != 0 || sps_ptr.is_null() {
            return None;
        }

        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format_desc,
            1,
            &mut pps_ptr,
            &mut pps_len,
            ptr::null_mut(),
            ptr::null_mut(),
        );
        if status != 0 || pps_ptr.is_null() {
            return None;
        }

        let start_code: [u8; 4] = [0x00, 0x00, 0x00, 0x01];
        let mut data = Vec::with_capacity(start_code.len() * 2 + sps_len + pps_len);
        data.extend_from_slice(&start_code);
        data.extend_from_slice(std::slice::from_raw_parts(sps_ptr, sps_len));
        data.extend_from_slice(&start_code);
        data.extend_from_slice(std::slice::from_raw_parts(pps_ptr, pps_len));

        Some(EncodedFrame {
            data,
            timestamp_us: 0,
            is_keyframe: false,
            is_codec_config: true,
        })
    }

    /// Extract encoded NAL units from the sample buffer, convert to Annex-B.
    unsafe fn extract_encoded_data(
        sample_buffer: CMSampleBufferRef,
        is_keyframe: bool,
    ) -> Option<EncodedFrame> {
        let block_buf = CMSampleBufferGetDataBuffer(sample_buffer);
        if block_buf.is_null() {
            return None;
        }

        let data_len = CMBlockBufferGetDataLength(block_buf);
        if data_len == 0 {
            return None;
        }

        let mut raw = vec![0u8; data_len];
        let status = CMBlockBufferCopyDataBytes(block_buf, 0, data_len, raw.as_mut_ptr());
        if status != 0 {
            return None;
        }

        let annex_b = avcc_to_annex_b(&raw);

        let pts = CMSampleBufferGetPresentationTimeStamp(sample_buffer);
        let timestamp_us = if pts.timescale > 0 {
            (pts.value as u64 * 1_000_000) / pts.timescale as u64
        } else {
            0
        };

        Some(EncodedFrame {
            data: annex_b,
            timestamp_us,
            is_keyframe,
            is_codec_config: false,
        })
    }
}

#[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
mod apple {
    use super::*;

    pub struct H264Encoder;

    impl H264Encoder {
        pub fn new(_config: EncoderConfig) -> Result<(Self, mpsc::Receiver<EncodedFrame>), String> {
            tracing::warn!("H264Encoder not available on non-Apple target");
            let (_tx, rx) = mpsc::channel();
            Ok((Self, rx))
        }

        /// # Safety
        /// `_pixel_buffer` must be a valid `CVPixelBufferRef` (unused in stub).
        pub unsafe fn encode_frame(
            &mut self,
            _pixel_buffer: *const std::ffi::c_void,
        ) -> Result<(), String> {
            Ok(())
        }

        pub fn flush(&self) -> Result<(), String> {
            Ok(())
        }

        pub fn stop(&self) {}
    }
}

pub use apple::H264Encoder;

/// Convert AVCC length-prefixed NAL units to Annex-B start code format.
pub fn avcc_to_annex_b(data: &[u8]) -> Vec<u8> {
    let start_code: [u8; 4] = [0x00, 0x00, 0x00, 0x01];
    let mut result = Vec::with_capacity(data.len());
    let mut offset = 0;

    while offset + 4 <= data.len() {
        let nal_len = u32::from_be_bytes([
            data[offset],
            data[offset + 1],
            data[offset + 2],
            data[offset + 3],
        ]) as usize;
        offset += 4;

        if offset + nal_len > data.len() {
            break;
        }

        result.extend_from_slice(&start_code);
        result.extend_from_slice(&data[offset..offset + nal_len]);
        offset += nal_len;
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encoder_config_defaults() {
        let cfg = EncoderConfig::default();
        assert_eq!(cfg.fps, 30);
        assert_eq!(cfg.bitrate, 4_000_000);
        assert_eq!(cfg.keyframe_interval, 60);
    }

    #[test]
    fn encoded_frame_fields() {
        let frame = EncodedFrame {
            data: vec![0x00, 0x00, 0x00, 0x01, 0x67],
            timestamp_us: 33333,
            is_keyframe: true,
            is_codec_config: false,
        };
        assert!(frame.is_keyframe);
        assert!(!frame.is_codec_config);
    }

    #[test]
    fn avcc_to_annex_b_single_nal() {
        // AVCC: [length=3][NAL bytes]
        let avcc = vec![0x00, 0x00, 0x00, 0x03, 0x67, 0x42, 0x00];
        let annex_b = avcc_to_annex_b(&avcc);
        assert_eq!(annex_b, vec![0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00]);
    }

    #[test]
    fn avcc_to_annex_b_multiple_nals() {
        // Two NALs: [len=2][AA BB][len=1][CC]
        let avcc = vec![
            0x00, 0x00, 0x00, 0x02, 0xAA, 0xBB, 0x00, 0x00, 0x00, 0x01, 0xCC,
        ];
        let annex_b = avcc_to_annex_b(&avcc);
        assert_eq!(
            annex_b,
            vec![0x00, 0x00, 0x00, 0x01, 0xAA, 0xBB, 0x00, 0x00, 0x00, 0x01, 0xCC,]
        );
    }

    #[test]
    fn avcc_to_annex_b_empty() {
        assert!(avcc_to_annex_b(&[]).is_empty());
    }

    #[test]
    fn avcc_to_annex_b_truncated() {
        // Length says 10 bytes but only 2 available — should stop gracefully
        let avcc = vec![0x00, 0x00, 0x00, 0x0A, 0xAA, 0xBB];
        let annex_b = avcc_to_annex_b(&avcc);
        assert!(annex_b.is_empty());
    }

    #[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
    #[test]
    fn stub_encoder_creates_ok() {
        let config = EncoderConfig {
            width: 640,
            height: 480,
            ..Default::default()
        };
        let (encoder, _rx) = H264Encoder::new(config).unwrap();
        encoder.stop();
    }
}
