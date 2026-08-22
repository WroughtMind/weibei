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

public final class NativeDisposableStore: @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [NativeRegistration] = []

    public init() {}

    public func add(_ registration: NativeRegistration) {
        lock.lock()
        registrations.append(registration)
        lock.unlock()
    }

    public func disposeAll() {
        lock.lock()
        let copy = registrations.reversed()
        registrations.removeAll()
        lock.unlock()
        for registration in copy {
            registration.dispose()
        }
    }

    deinit {
        disposeAll()
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
