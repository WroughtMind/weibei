import Darwin
import Foundation

/// Watches the active Markdown note for external changes (S4 + hard stop C3/H5).
///
/// Dual kqueue sources:
/// - **Directory** fd: catches atomic replace (rename/delete/create of the child).
/// - **File** fd: catches in-place writes (`sed -i`, append) that directory kqueue
///   often misses.
///
/// Events from both sources coalesce through the same 0.12s work item. After a
/// directory event the file fd is reopened (inode may have been replaced).
public final class NoteFileWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable (URL) -> Void

    private let queue: DispatchQueue
    private var directoryFileDescriptor: CInt = -1
    private var fileFileDescriptor: CInt = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
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
        // Avoid queue.sync from deinit (can trap under MainActor teardown).
        // Close is owned exclusively by cancel handlers (captures fd by value).
        pendingReloadWorkItem?.cancel()
        pendingReloadWorkItem = nil
        directorySource?.setEventHandler {}
        fileSource?.setEventHandler {}
        directorySource?.cancel()
        fileSource?.cancel()
        directorySource = nil
        fileSource = nil
        watchedFileURL = nil
        watchedFileName = nil
        changeHandler = nil
        // Do not close() here — cancel handlers close their captured fds.
        directoryFileDescriptor = -1
        fileFileDescriptor = -1
    }

    public var isWatching: Bool {
        queue.sync {
            directorySource != nil && directoryFileDescriptor >= 0
        }
    }

    public var currentlyWatchedPath: String? {
        queue.sync { watchedFileURL?.path }
    }

    /// Begin watching the file at `url` (directory + file dual sources).
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
        let dirFD = open(dirPath, O_EVTONLY)
        guard dirFD >= 0 else {
            return
        }
        directoryFileDescriptor = dirFD
        watchedFileURL = fileURL
        watchedFileName = fileURL.lastPathComponent
        changeHandler = onChange

        let dirSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link, .revoke],
            queue: queue
        )
        // C3: capture fd by value so re-watch close targets this source's fd only.
        dirSource.setEventHandler { [weak self] in
            self?.handleDirectoryEventLocked()
        }
        dirSource.setCancelHandler {
            close(dirFD)
        }
        directorySource = dirSource
        dirSource.resume()

        // H5: file-level source for in-place writes. Open failure (iCloud placeholder
        // etc.) degrades to directory-only — same as pre-H5 behaviour.
        openFileSourceLocked(fileURL: fileURL)
    }

    private func openFileSourceLocked(fileURL: URL) {
        // Tear down previous file source first (cancel handler closes its fd).
        if let fileSource {
            fileSource.cancel()
            self.fileSource = nil
        }
        fileFileDescriptor = -1

        let fileFD = open(fileURL.path, O_EVTONLY)
        guard fileFD >= 0 else {
            return
        }
        fileFileDescriptor = fileFD
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileFD,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleCoalescedChangeLocked()
        }
        source.setCancelHandler {
            close(fileFD)
        }
        fileSource = source
        source.resume()
    }

    private func stopLocked() {
        pendingReloadWorkItem?.cancel()
        pendingReloadWorkItem = nil
        if let fileSource {
            fileSource.cancel()
            self.fileSource = nil
        }
        if let directorySource {
            directorySource.cancel()
            self.directorySource = nil
        } else if directoryFileDescriptor >= 0 {
            // No source yet (open failed after fd assigned) — close ourselves.
            close(directoryFileDescriptor)
        }
        // FDs are closed by cancel handlers (or the else branch above).
        directoryFileDescriptor = -1
        fileFileDescriptor = -1
        watchedFileURL = nil
        watchedFileName = nil
        changeHandler = nil
    }

    private func handleDirectoryEventLocked() {
        // Directory event may mean the watched file was atomically replaced;
        // re-open the file fd on the new inode inside the coalesce window.
        scheduleCoalescedChangeLocked(reopenFileDescriptor: true)
    }

    private func scheduleCoalescedChangeLocked(reopenFileDescriptor: Bool = false) {
        guard Date() >= ignoreUntil else { return }
        guard let fileURL = watchedFileURL,
              let fileName = watchedFileName,
              changeHandler != nil else { return }

        pendingReloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard Date() >= self.ignoreUntil else { return }
                guard self.watchedFileName == fileName,
                      let fileURL = self.watchedFileURL,
                      let handler = self.changeHandler else { return }
                if reopenFileDescriptor {
                    self.openFileSourceLocked(fileURL: fileURL)
                }
                handler(fileURL)
            }
        }
        pendingReloadWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}
