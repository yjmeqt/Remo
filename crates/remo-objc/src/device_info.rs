//! Device and app info retrieval via ObjC runtime.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub name: String,
    pub system_name: String,
    pub system_version: String,
    pub model: String,
    pub screen_width: f64,
    pub screen_height: f64,
    pub screen_scale: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppInfo {
    pub bundle_id: String,
    pub version: String,
    pub build: String,
    pub display_name: String,
}

#[cfg(all(target_vendor = "apple", feature = "uikit"))]
mod apple {
    use super::*;
    use objc2::msg_send;
    use objc2::runtime::AnyObject;
    use objc2_foundation::NSString;

    unsafe fn nsstring_to_string(obj: *mut AnyObject) -> String {
        if obj.is_null() {
            return String::new();
        }
        let ns: &NSString = &*(obj as *const NSString);
        ns.to_string()
    }

    /// Retrieve device information.
    ///
    /// # Safety
    /// Some properties may require main thread access.
    pub unsafe fn get_device_info() -> DeviceInfo {
        let device: *mut AnyObject = msg_send![objc2::class!(UIDevice), currentDevice];
        let name = nsstring_to_string(msg_send![device, name]);
        let system_name = nsstring_to_string(msg_send![device, systemName]);
        let system_version = nsstring_to_string(msg_send![device, systemVersion]);
        let model = nsstring_to_string(msg_send![device, model]);

        let screen: *mut AnyObject = msg_send![objc2::class!(UIScreen), mainScreen];
        let scale: f64 = msg_send![screen, scale];
        let native_bounds_width: f64 = msg_send![screen, nativeScale];

        // Use nativeBounds for pixel dimensions, then divide by nativeScale for points
        let bounds_width: f64 = {
            let b: objc2_foundation::NSRect = msg_send![screen, bounds];
            b.size.width
        };
        let bounds_height: f64 = {
            let b: objc2_foundation::NSRect = msg_send![screen, bounds];
            b.size.height
        };
        let _ = native_bounds_width; // suppress unused

        DeviceInfo {
            name,
            system_name,
            system_version,
            model,
            screen_width: bounds_width,
            screen_height: bounds_height,
            screen_scale: scale,
        }
    }

    /// Retrieve app bundle information.
    ///
    /// # Safety
    /// Accesses NSBundle via ObjC runtime.
    pub unsafe fn get_app_info() -> AppInfo {
        let bundle: *mut AnyObject = msg_send![objc2::class!(NSBundle), mainBundle];

        let bundle_id = nsstring_to_string(msg_send![bundle, bundleIdentifier]);

        let info_dict: *mut AnyObject = msg_send![bundle, infoDictionary];

        let version_key = NSString::from_str("CFBundleShortVersionString");
        let version_obj: *mut AnyObject = msg_send![info_dict, objectForKey: &*version_key];
        let version = nsstring_to_string(version_obj);

        let build_key = NSString::from_str("CFBundleVersion");
        let build_obj: *mut AnyObject = msg_send![info_dict, objectForKey: &*build_key];
        let build = nsstring_to_string(build_obj);

        let name_key = NSString::from_str("CFBundleDisplayName");
        let name_obj: *mut AnyObject = msg_send![info_dict, objectForKey: &*name_key];
        let display_name = if name_obj.is_null() {
            let fallback_key = NSString::from_str("CFBundleName");
            let fallback_obj: *mut AnyObject = msg_send![info_dict, objectForKey: &*fallback_key];
            nsstring_to_string(fallback_obj)
        } else {
            nsstring_to_string(name_obj)
        };

        AppInfo {
            bundle_id,
            version,
            build,
            display_name,
        }
    }
}

#[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
mod apple {
    use super::*;

    pub unsafe fn get_device_info() -> DeviceInfo {
        tracing::warn!("get_device_info called on non-Apple target, returning stub");
        DeviceInfo {
            name: "Stub".into(),
            system_name: "StubOS".into(),
            system_version: "0.0".into(),
            model: "Stub".into(),
            screen_width: 390.0,
            screen_height: 844.0,
            screen_scale: 3.0,
        }
    }

    pub unsafe fn get_app_info() -> AppInfo {
        tracing::warn!("get_app_info called on non-Apple target, returning stub");
        AppInfo {
            bundle_id: "com.stub.app".into(),
            version: "0.0.0".into(),
            build: "0".into(),
            display_name: "Stub".into(),
        }
    }
}

/// Retrieve device information (model, OS version, screen).
///
/// # Safety
/// On iOS, should be called from the main thread.
pub unsafe fn get_device_info() -> DeviceInfo {
    apple::get_device_info()
}

/// Retrieve app bundle information (bundle ID, version, display name).
///
/// # Safety
/// On iOS, accesses NSBundle via ObjC runtime.
pub unsafe fn get_app_info() -> AppInfo {
    apple::get_app_info()
}
