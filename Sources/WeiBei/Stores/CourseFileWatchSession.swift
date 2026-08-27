import Darwin
import Dispatch
import Foundation

/// 课程库 / 课根目录的 DispatchSource 监视会话。
///
/// 只监视目录（含子目录），事件合并后再通知对账。
/// cancel handler 按值关闭自己的 fd，避免重挂时误关新描述符。
final class CourseFileWatchSession: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "weibei.course-file-watch",
        qos: .utility
    )
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var pauseCount = 0
    private var debounceWork: DispatchWorkItem?
    private var stopped = false
    private let debounceInterval: DispatchTimeInterval = .milliseconds(300)
    private let onDebouncedEvent: @Sendable () -> Void

    var watchedDirectoryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sources.count
    }

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pauseCount > 0
    }

    init(onDebouncedEvent: @escaping @Sendable () -> Void) {
        self.onDebouncedEvent = onDebouncedEvent
    }

    func pause() {
        lock.lock()
        pauseCount += 1
        debounceWork?.cancel()
        debounceWork = nil
        lock.unlock()
    }

    /// 最后一层突变结束：拆掉旧 source 再重挂，丢掉自写期间积压的 kqueue 事件。
    func resume(watching directories: [URL]) {
        lock.lock()
        if pauseCount > 0 {
            pauseCount -= 1
        }
        let stillPaused = pauseCount > 0 || stopped
        lock.unlock()
        guard !stillPaused else { return }
        recreateAll(directories)
    }

    func poke() {
        handleEvent()
    }

    func replaceDirectories(_ directories: [URL]) {
        lock.lock()
        if stopped || pauseCount > 0 {
            lock.unlock()
            return
        }
        lock.unlock()
        let wanted = Self.uniquePaths(directories)
        lock.lock()
        let current = Set(sources.keys)
        let toRemove = current.subtracting(Set(wanted))
        var removed: [DispatchSourceFileSystemObject] = []
        for path in toRemove {
            if let source = sources.removeValue(forKey: path) {
                removed.append(source)
            }
        }
        let alreadyHave = current.subtracting(toRemove)
        lock.unlock()
        for source in removed {
            source.cancel()
        }
        for path in wanted where !alreadyHave.contains(path) {
            startWatching(path)
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        debounceWork?.cancel()
        debounceWork = nil
        let closing = sources
        sources.removeAll()
        lock.unlock()
        for source in closing.values {
            source.cancel()
        }
    }

    private func recreateAll(_ directories: [URL]) {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        debounceWork?.cancel()
        debounceWork = nil
        let closing = sources
        sources.removeAll()
        lock.unlock()
        for source in closing.values {
            source.cancel()
        }
        for path in Self.uniquePaths(directories) {
            startWatching(path)
        }
    }

    private func startWatching(_ path: String) {
        let fd = path.withCString { pointer in
            Darwin.open(pointer, Darwin.O_EVTONLY)
        }
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .write, .extend, .rename, .attrib, .link, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleEvent()
        }
        let capturedFD = fd
        source.setCancelHandler {
            Darwin.close(capturedFD)
        }

        lock.lock()
        if stopped || pauseCount > 0 || sources[path] != nil {
            lock.unlock()
            source.cancel()
            return
        }
        sources[path] = source
        lock.unlock()
        source.resume()
    }

    private func handleEvent() {
        lock.lock()
        if stopped || pauseCount > 0 {
            lock.unlock()
            return
        }
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldNotify = !self.stopped && self.pauseCount == 0
            self.lock.unlock()
            if shouldNotify {
                self.onDebouncedEvent()
            }
        }
        debounceWork = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private static func uniquePaths(_ directories: [URL]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for directory in directories {
            let path = directory.standardizedFileURL.path
            if seen.insert(path).inserted {
                result.append(path)
            }
        }
        return result
    }
}

enum CourseFileWatchRegistry {
    private static let lock = NSLock()
    private static var sessions: [ObjectIdentifier: CourseFileWatchSession] = [:]

    static func attach(_ storeID: ObjectIdentifier, session: CourseFileWatchSession) {
        lock.lock()
        let old = sessions.updateValue(session, forKey: storeID)
        lock.unlock()
        old?.stop()
    }

    static func session(for storeID: ObjectIdentifier) -> CourseFileWatchSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[storeID]
    }

    static func remove(_ storeID: ObjectIdentifier) {
        lock.lock()
        let old = sessions.removeValue(forKey: storeID)
        lock.unlock()
        old?.stop()
    }

    static func removeIfCurrent(_ storeID: ObjectIdentifier, session: CourseFileWatchSession) {
        lock.lock()
        if sessions[storeID] === session {
            sessions.removeValue(forKey: storeID)
        }
        lock.unlock()
        session.stop()
    }
}
