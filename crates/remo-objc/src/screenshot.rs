//! Screenshot capture via UIKit's UIGraphics* API.
//!
//! Returns raw image bytes (JPEG or PNG). The caller is responsible for
//! encoding (e.g. base64) when sending over the wire.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenshotResult {
    pub format: String,
    pub width: f64,
    pub height: f64,
    pub scale: f64,
    pub bytes: Vec<u8>,
}

#[cfg(all(target_vendor = "apple", feature = "uikit"))]
mod apple {
    use super::*;
    use objc2::runtime::AnyObject;
    use objc2::{msg_send, MainThreadMarker};
    use objc2_foundation::NSSize;
    use objc2_ui_kit::UIApplication;

    extern "C" {
        fn UIGraphicsBeginImageContextWithOptions(size: NSSize, opaque: bool, scale: f64);
        fn UIGraphicsGetImageFromCurrentImageContext() -> *mut AnyObject;
        fn UIGraphicsEndImageContext();
        fn UIImageJPEGRepresentation(
            image: *const AnyObject,
            compression_quality: f64,
        ) -> *mut AnyObject;
        fn UIImagePNGRepresentation(image: *const AnyObject) -> *mut AnyObject;
    }

    /// Capture a screenshot of the key window.
    ///
    /// # Safety
    /// Must be called on the main thread.
    pub unsafe fn capture(format: &str, quality: f64) -> Option<ScreenshotResult> {
        let mtm = MainThreadMarker::new_unchecked();
        let app = UIApplication::sharedApplication(mtm);

        #[allow(deprecated)]
        let windows = app.windows();
        let window = windows.iter().find(|w| w.isKeyWindow())?;

        let bounds = window.bounds();

        // scale=0 → native screen scale
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, 0.0);

        let _drawn: bool =
            msg_send![&*window, drawViewHierarchyInRect: bounds, afterScreenUpdates: true];

        let image = UIGraphicsGetImageFromCurrentImageContext();
        if image.is_null() {
            UIGraphicsEndImageContext();
            return None;
        }

        let data_ptr: *mut AnyObject = match format {
            "png" => UIImagePNGRepresentation(image),
            _ => UIImageJPEGRepresentation(image, quality),
        };

        UIGraphicsEndImageContext();

        if data_ptr.is_null() {
            return None;
        }

        let length: usize = msg_send![data_ptr, length];
        let bytes_ptr: *const u8 = msg_send![data_ptr, bytes];
        let bytes = std::slice::from_raw_parts(bytes_ptr, length).to_vec();

        let screen: *mut AnyObject = msg_send![objc2::class!(UIScreen), mainScreen];
        let scale: f64 = msg_send![screen, scale];

        Some(ScreenshotResult {
            format: format.to_owned(),
            width: bounds.size.width,
            height: bounds.size.height,
            scale,
            bytes,
        })
    }
}

#[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
mod apple {
    use super::*;

    #[allow(clippy::unnecessary_wraps)]
    pub unsafe fn capture(_format: &str, _quality: f64) -> Option<ScreenshotResult> {
        tracing::warn!("capture_screenshot called on non-Apple target, returning stub");
        Some(ScreenshotResult {
            format: "stub".into(),
            width: 390.0,
            height: 844.0,
            scale: 3.0,
            bytes: vec![],
        })
    }
}

/// Capture a screenshot of the key window.
///
/// # Safety
/// On iOS, must be called from the main thread.
pub unsafe fn capture_screenshot(format: &str, quality: f64) -> Option<ScreenshotResult> {
    apple::capture(format, quality)
}
