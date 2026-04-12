#if DEBUG && canImport(UIKit)
import UIKit
import ObjectiveC

/// UIKit lifecycle manager used by `#remoScope(scopedTo:)` macro expansions.
///
/// Swizzles `UIViewController.viewDidDisappear(_:)` once per process lifetime.
/// Uses associated objects to track registered capability names per VC instance.
/// When a VC disappears, all its tracked capabilities are unregistered.
public enum _RemoLifecycle {
    private static var _swizzled = false
    private static let _lock = NSLock()

    // Key for objc associated object storing [String] of registered capability names.
    // Must be `fileprivate` (not `private`) so the UIViewController extension below can read it.
    fileprivate static var _namesKey: UInt8 = 0

    /// Track capability names for automatic unregistration on `viewDidDisappear`.
    ///
    /// Called by the `#remoScope(scopedTo:)` macro expansion. The capabilities
    /// themselves are registered by `#remoCap` expansions in the same scope.
    public static func trackNames(_ names: [String], owner: UIViewController) {
        _swizzleOnce()
        var existing = objc_getAssociatedObject(owner, &_namesKey) as? [String] ?? []
        for name in names where !existing.contains(name) {
            existing.append(name)
        }
        objc_setAssociatedObject(owner, &_namesKey, existing, .OBJC_ASSOCIATION_RETAIN)
    }

    private static func _swizzleOnce() {
        _lock.lock()
        defer { _lock.unlock() }
        guard !_swizzled else { return }
        _swizzled = true

        let cls = UIViewController.self
        let original = #selector(UIViewController.viewDidDisappear(_:))
        let swizzled = #selector(UIViewController._remo_viewDidDisappear(_:))
        guard
            let originalMethod = class_getInstanceMethod(cls, original),
            let swizzledMethod = class_getInstanceMethod(cls, swizzled)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension UIViewController {
    @objc func _remo_viewDidDisappear(_ animated: Bool) {
        // After swizzling, calling this invokes the original viewDidDisappear.
        _remo_viewDidDisappear(animated)
        guard let names = objc_getAssociatedObject(self, &_RemoLifecycle._namesKey) as? [String],
              !names.isEmpty else { return }
        names.forEach { Remo.unregister($0) }
        objc_setAssociatedObject(self, &_RemoLifecycle._namesKey, nil, .OBJC_ASSOCIATION_RETAIN)
    }
}
#endif // DEBUG && canImport(UIKit)
