import Darwin
import Foundation

/// Configuration for serializing mutations of one PI runtime cache.
public struct PiRuntimeCacheLockConfiguration: Sendable {
    /// Maximum time to wait for another preparation process.
    public let timeout: Duration

    /// Delay between acquisition attempts.
    public let retryInterval: Duration

    /// Creates cache lock timing configuration.
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait for another preparation process.
    ///   - retryInterval: Delay between acquisition attempts.
    public init(
        timeout: Duration = .seconds(30),
        retryInterval: Duration = .milliseconds(100)
    ) {
        self.timeout = timeout
        self.retryInterval = retryInterval
    }
}

/// Holds an operating-system file lock for one PI runtime cache.
///
/// `flock` ownership is tied to the open descriptor, so the kernel releases
/// abandoned locks when a process exits and no stale-directory reclamation is
/// required.
final class PiRuntimeCacheLock: @unchecked Sendable {
    private let descriptor: Int32
    private let stateLock = NSLock()
    private var released = false

    /// Creates an owned cache lock around an already locked descriptor.
    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        release()
    }

    /// Acquires the architecture cache lock within the configured deadline.
    static func acquire(
        at lockURL: URL,
        configuration: PiRuntimeCacheLockConfiguration,
        fileManager: FileManager
    ) async throws -> PiRuntimeCacheLock {
        do {
            try fileManager.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw PiRuntimePreparationError.fileOperationFailed("create PI runtime cache lock directory", error)
        }

        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw PiRuntimePreparationError.fileOperationFailed(
                "open PI runtime cache lock",
                NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            )
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: configuration.timeout)
        while clock.now < deadline {
            if systemFlock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                writeOwnerPID(to: descriptor)
                return PiRuntimeCacheLock(descriptor: descriptor)
            }
            guard errno == EWOULDBLOCK else {
                let lockError = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                Darwin.close(descriptor)
                throw PiRuntimePreparationError.fileOperationFailed("lock PI runtime cache", lockError)
            }
            do {
                try await Task.sleep(for: configuration.retryInterval)
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }

        Darwin.close(descriptor)
        throw PiRuntimePreparationError.cacheLockTimedOut(lockURL)
    }

    /// Releases the kernel-managed lock exactly once.
    func release() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !released else {
            return
        }
        _ = systemFlock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        released = true
    }

    /// Stores the current PID for diagnostics without participating in ownership.
    private static func writeOwnerPID(to descriptor: Int32) {
        let owner = Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
        guard Darwin.ftruncate(descriptor, 0) == 0,
              Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            return
        }
        owner.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            _ = Darwin.write(descriptor, baseAddress, bytes.count)
        }
    }
}
