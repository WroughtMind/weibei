import Darwin
import Foundation

/// Watches the directory of the active Markdown note for external changes (S4).
///
/// Atomic writes replace the file inode, so a file-level vnode source misses the
/// update. Watching the parent directory and filtering by last path component
/// catches write/rename/delete while remaining a single lightweight kqueue source.
public final class NoteFileWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable (URL) -> Void

    private let queue: DispatchQueue
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var watchedFileURL: URL?
    private var watchedFileName: String?
    private var changeHandler: ChangeHandler?
    /// Suppress events from our own atomic writes for a short window.
    private var ignoreUntil: Date = .distantPast
    private var pendingReloadWorkItem: DispatchWorkItem?

    public init(queue: DispatchQueue = DispatchQueue(label: "weibei.note-file-watcher")) {
        self.queue = queue
    }

    deinit {
        stop()
    }

    public var isWatching: Bool {
        queue.sync { source != nil && fileDescriptor >= 0 }
    }

    public var currentlyWatchedPath: String? {
        queue.sync { watchedFileURL?.path }
    }

    /// Begin watching the file at `url` (parent directory is monitored).
    public func watch(url: URL, onChange: @escaping ChangeHandler) {
        queue.sync {
            self.startLocked(fileURL: url.standardizedFileURL, onChange: onChange)
        }
    }

    public func stop() {
        queue.sync {
            self.stopLocked()
        }
    }

    /// Ignore filesystem events until `date` (typically now + a few hundred ms
    /// after WeiBei itself writes the file).
    public func ignoreEvents(until date: Date) {
        queue.sync {
            self.ignoreUntil = date
        }
    }

    // MARK: - Private

    private func startLocked(fileURL: URL, onChange: @escaping ChangeHandler) {
        stopLocked()
        let directory = fileURL.deletingLastPathComponent()
        let dirPath = directory.path
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else {
            return
        }
        fileDescriptor = fd
        watchedFileURL = fileURL
        watchedFileName = fileURL.lastPathComponent
        changeHandler = onChange

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleDirectoryEventLocked()
        }
        source.setCancelHandler { [weak self] in
            if let self, self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.source = source
        source.resume()
    }

    private func stopLocked() {
        pendingReloadWorkItem?.cancel()
        pendingReloadWorkItem = nil
        if let source {
            source.cancel()
            self.source = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        watchedFileURL = nil
        watchedFileName = nil
        changeHandler = nil
    }

    private func handleDirectoryEventLocked() {
        guard Date() >= ignoreUntil else { return }
        guard let fileURL = watchedFileURL,
              let fileName = watchedFileName,
              let handler = changeHandler else { return }

        // Directory events do not name the child; poll mtime/size of the target.
        // Coalesce bursty kqueue events from atomic write (temp + rename).
        pendingReloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard Date() >= self.ignoreUntil else { return }
                guard self.watchedFileName == fileName,
                      let fileURL = self.watchedFileURL,
                      let handler = self.changeHandler else { return }
                // Fire even if the file was deleted (caller decides); for present
                // files this is the silent-reload path.
                _ = fileName
                handler(fileURL)
            }
        }
        pendingReloadWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}
