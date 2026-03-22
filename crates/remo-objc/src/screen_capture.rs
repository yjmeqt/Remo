//! Screen capture via UIKit rendering to CVPixelBuffer.
//!
//! Captures the app's key window by rendering into a CGContext backed by a
//! CVPixelBuffer, suitable for feeding directly into VideoToolbox encoding.

/// Info about the captured screen dimensions.
#[derive(Debug, Clone)]
pub struct CaptureInfo {
    pub width: u32,
    pub height: u32,
    pub scale: f64,
}

#[cfg(all(target_vendor = "apple", feature = "uikit"))]
mod apple {
    use super::*;
    use std::ffi::c_void;
    use std::ptr;

    type CVReturn = i32;
    type CVPixelBufferRef = *mut c_void;
    type CGContextRef = *mut c_void;
    type CGColorSpaceRef = *mut c_void;

    #[link(name = "CoreVideo", kind = "framework")]
    extern "C" {
        fn CVPixelBufferCreate(
            allocator: *const c_void,
            width: usize,
            height: usize,
            pixel_format_type: u32,
            pixel_buffer_attributes: *const c_void,
            pixel_buffer_out: *mut CVPixelBufferRef,
        ) -> CVReturn;
        fn CVPixelBufferLockBaseAddress(pixel_buffer: CVPixelBufferRef, flags: u64) -> CVReturn;
        fn CVPixelBufferUnlockBaseAddress(pixel_buffer: CVPixelBufferRef, flags: u64) -> CVReturn;
        fn CVPixelBufferGetBaseAddress(pixel_buffer: CVPixelBufferRef) -> *mut c_void;
        fn CVPixelBufferGetBytesPerRow(pixel_buffer: CVPixelBufferRef) -> usize;
    }

    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGBitmapContextCreate(
            data: *mut c_void,
            width: usize,
            height: usize,
            bits_per_component: usize,
            bytes_per_row: usize,
            space: CGColorSpaceRef,
            bitmap_info: u32,
        ) -> CGContextRef;
        fn CGColorSpaceCreateDeviceRGB() -> CGColorSpaceRef;
        fn CGContextRelease(context: CGContextRef);
        fn CGColorSpaceRelease(color_space: CGColorSpaceRef);
        fn CGContextTranslateCTM(c: CGContextRef, tx: f64, ty: f64);
        fn CGContextScaleCTM(c: CGContextRef, sx: f64, sy: f64);
    }

    extern "C" {
        fn UIGraphicsPushContext(context: CGContextRef);
        fn UIGraphicsPopContext();
    }

    extern "C" {
        fn CFRelease(cf: *const c_void);
    }

    // kCVPixelFormatType_32BGRA
    const K_CV_PIXEL_FORMAT_TYPE_32BGRA: u32 = 0x42475241;
    // CGBitmapInfo: kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    const K_CG_BITMAP_INFO: u32 = (2 << 12) | 2;

    /// Capture the key window into a CVPixelBuffer.
    ///
    /// Returns the raw `CVPixelBufferRef` pointer. Caller must `CFRelease` it when done.
    ///
    /// # Safety
    /// Must be called on the main thread.
    pub unsafe fn capture_frame_to_pixel_buffer(
        width: u32,
        height: u32,
        scale: f64,
    ) -> Option<*mut c_void> {
        use objc2::msg_send;
        use objc2::MainThreadMarker;
        use objc2_ui_kit::UIApplication;

        let mtm = MainThreadMarker::new_unchecked();
        let app = UIApplication::sharedApplication(mtm);
        #[allow(deprecated)]
        let windows = app.windows();
        let key_window = windows.iter().find(|w| w.isKeyWindow())?;

        let bounds: objc2_foundation::NSRect = msg_send![&*key_window, bounds];

        let pixel_width = (width as f64 * scale) as usize;
        let pixel_height = (height as f64 * scale) as usize;

        // Create CVPixelBuffer
        let mut pixel_buffer: CVPixelBufferRef = ptr::null_mut();
        let status = CVPixelBufferCreate(
            ptr::null(),
            pixel_width,
            pixel_height,
            K_CV_PIXEL_FORMAT_TYPE_32BGRA,
            ptr::null(),
            &mut pixel_buffer,
        );
        if status != 0 || pixel_buffer.is_null() {
            return None;
        }

        CVPixelBufferLockBaseAddress(pixel_buffer, 0);
        let base_address = CVPixelBufferGetBaseAddress(pixel_buffer);
        let bytes_per_row = CVPixelBufferGetBytesPerRow(pixel_buffer);

        let color_space = CGColorSpaceCreateDeviceRGB();
        let context = CGBitmapContextCreate(
            base_address,
            pixel_width,
            pixel_height,
            8,
            bytes_per_row,
            color_space,
            K_CG_BITMAP_INFO,
        );
        CGColorSpaceRelease(color_space);

        if context.is_null() {
            CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
            CFRelease(pixel_buffer as *const c_void);
            return None;
        }

        // Transform CG coordinates (origin bottom-left) → UIKit (origin top-left)
        // and scale from points to pixels in one step.
        CGContextTranslateCTM(context, 0.0, pixel_height as f64);
        CGContextScaleCTM(context, scale, -scale);

        // Render view hierarchy directly into the CVPixelBuffer's CGContext.
        UIGraphicsPushContext(context);

        let after_updates: bool = false; // false for speed in continuous capture
        let _success: bool = msg_send![
            &*key_window,
            drawViewHierarchyInRect: bounds,
            afterScreenUpdates: after_updates
        ];

        UIGraphicsPopContext();
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);

        Some(pixel_buffer)
    }

    /// Get screen dimensions of the key window.
    ///
    /// # Safety
    /// Must be called on the main thread.
    pub unsafe fn get_screen_info() -> Option<CaptureInfo> {
        use objc2::msg_send;
        use objc2::runtime::AnyObject;
        use objc2::MainThreadMarker;
        use objc2_ui_kit::UIApplication;

        let mtm = MainThreadMarker::new_unchecked();
        let app = UIApplication::sharedApplication(mtm);
        #[allow(deprecated)]
        let windows = app.windows();
        let key_window = windows.iter().find(|w| w.isKeyWindow())?;

        let bounds: objc2_foundation::NSRect = msg_send![&*key_window, bounds];
        let screen: *mut AnyObject = msg_send![&*key_window, screen];
        let scale: f64 = msg_send![screen, scale];

        Some(CaptureInfo {
            width: bounds.size.width as u32,
            height: bounds.size.height as u32,
            scale,
        })
    }
}

#[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
mod apple {
    use super::*;

    /// # Safety
    /// Stub — no-op on non-Apple targets.
    pub unsafe fn capture_frame_to_pixel_buffer(
        _width: u32,
        _height: u32,
        _scale: f64,
    ) -> Option<*mut std::ffi::c_void> {
        tracing::warn!("capture_frame_to_pixel_buffer called on non-Apple target");
        None
    }

    /// # Safety
    /// Stub — no-op on non-Apple targets.
    pub unsafe fn get_screen_info() -> Option<CaptureInfo> {
        tracing::warn!("get_screen_info called on non-Apple target");
        None
    }
}

pub use apple::{capture_frame_to_pixel_buffer, get_screen_info};
