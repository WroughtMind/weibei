import Foundation

/// Registration that returns an idempotent disposer (Cordis effect discipline).
public struct NativeRegistration: Sendable {
    private let _dispose: @Sendable () -> Void
    private let disposed = LockedFlag()

    public init(dispose: @escaping @Sendable () -> Void) {
        _dispose = dispose
    }

    public func dispose() {
        guard disposed.mark() else { return }
        _dispose()
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value { return false }
        value = true
        return true
    }
}
