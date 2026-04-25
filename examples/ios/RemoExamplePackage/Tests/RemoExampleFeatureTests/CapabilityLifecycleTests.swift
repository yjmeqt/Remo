import Testing
import RemoSwift
import Foundation

// End-to-end verification that registering a capability does not leak the
// Swift HandlerBox or anything captured by the handler closure. Mirrors the
// Rust-side unit tests for `CallbackHandle::drop` — those prove the destroy
// callback fires; these prove `swiftCapabilityDestroy` correctly balances
// `Unmanaged.passRetained`.
//
// Lives in the example's test target because RemoSwift's own SPM tests can't
// run via `xcodebuild test -destination iOS` (the package's macro plugin
// dependency is host-only). The example workspace handles macros correctly,
// so we exercise the same Remo.register/unregister API here.

@Suite struct CapabilityLifecycleTests {

    /// Reference type whose `deinit` increments a shared counter. Captured
    /// inside each registered handler closure so the counter reflects when
    /// the underlying HandlerBox (and its closure) is released.
    private final class DeallocSentinel: @unchecked Sendable {
        let onDealloc: @Sendable () -> Void
        init(onDealloc: @escaping @Sendable () -> Void) { self.onDealloc = onDealloc }
        deinit { onDealloc() }
    }

    /// Register `name` with a handler that captures a fresh sentinel.
    /// In a separate function so the local `sentinel` reference is gone from
    /// the caller's stack frame on return — leaving the HandlerBox's retain
    /// (via `passRetained`) as the only strong reference to it.
    private func registerWithSentinel(
        _ name: String,
        onDealloc: @escaping @Sendable () -> Void
    ) {
        let sentinel = DeallocSentinel(onDealloc: onDealloc)
        Remo.register(name) { _ in
            _ = sentinel
            return [:]
        }
    }

    @Test
    func unregisterReleasesHandlerBox() {
        let counter = AtomicCounter()
        registerWithSentinel("remo.test.lifecycle.unregister") { counter.increment() }

        #expect(counter.value == 0, "sentinel must remain alive while registered")

        #expect(Remo.unregister("remo.test.lifecycle.unregister"))
        #expect(counter.value == 1, "sentinel must be released after unregister")
    }

    @Test
    func replacementReleasesPreviousHandlerBox() {
        let counter = AtomicCounter()
        registerWithSentinel("remo.test.lifecycle.replace") { counter.increment() }
        #expect(counter.value == 0)

        // Re-registering the same name must release the previous HandlerBox.
        Remo.register("remo.test.lifecycle.replace") { _ in [:] }
        #expect(counter.value == 1, "previous registration's HandlerBox must be released on replacement")

        Remo.unregister("remo.test.lifecycle.replace")
    }

    @Test
    func repeatedCyclesDoNotAccumulate() {
        let counter = AtomicCounter()
        let cycles = 50
        for i in 0..<cycles {
            let name = "remo.test.lifecycle.cycle.\(i)"
            registerWithSentinel(name) { counter.increment() }
            #expect(Remo.unregister(name))
        }
        #expect(counter.value == cycles, "all sentinels must be released across register/unregister cycles")
    }
}

/// Thread-safe counter — `deinit` callbacks may run on whichever thread
/// drops the last reference.
private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
}
