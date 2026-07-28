import Foundation

protocol AppBundleFileOperating {
    /// Reports whether a publication path exists.
    func itemExists(at url: URL) -> Bool

    /// Creates a publication directory and missing parents.
    func createDirectory(at url: URL) throws

    /// Copies an app candidate without changing its source.
    func copyItem(at source: URL, to destination: URL) throws

    /// Renames a publication item on the same filesystem.
    func moveItem(at source: URL, to destination: URL) throws

    /// Removes a publication item.
    func removeItem(at url: URL) throws
}

struct FoundationAppBundleFileOperator: AppBundleFileOperating {
    private let fileManager = FileManager.default

    /// Reports whether Foundation can resolve the path.
    func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    /// Creates the requested directory with intermediate parents.
    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Copies a filesystem item through FileManager.
    func copyItem(at source: URL, to destination: URL) throws {
        try fileManager.copyItem(at: source, to: destination)
    }

    /// Moves a filesystem item through FileManager.
    func moveItem(at source: URL, to destination: URL) throws {
        try fileManager.moveItem(at: source, to: destination)
    }

    /// Removes a filesystem item through FileManager.
    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}

/// Atomically commits an already validated app candidate while preserving the previous app on failure.
public final class TransactionalAppPublisher: @unchecked Sendable {
    private let fileOperator: any AppBundleFileOperating

    /// Creates a publisher backed by Foundation file operations.
    public convenience init() {
        self.init(fileOperator: FoundationAppBundleFileOperator())
    }

    /// Creates a publisher from an injectable file-operation service.
    init(fileOperator: any AppBundleFileOperating) {
        self.fileOperator = fileOperator
    }

    /// Moves a prepared sibling candidate into its distribution path and rolls back failed final validation.
    ///
    /// The candidate must already be fully assembled and validated. It must also
    /// live beside the destination so the final rename stays on one filesystem.
    ///
    /// - Parameters:
    ///   - preparedAppBundle: Validated candidate located in the distribution directory.
    ///   - destinationAppBundle: Stable app bundle path exposed to users and release tooling.
    ///   - finalValidator: Last validation performed after the candidate assumes its final path.
    public func publish(
        preparedAppBundle: URL,
        to destinationAppBundle: URL,
        finalValidator: @Sendable (URL) async throws -> Void
    ) async throws {
        let prepared = preparedAppBundle.standardizedFileURL
        let destination = destinationAppBundle.standardizedFileURL
        let distributionDirectory = destination.deletingLastPathComponent()
        guard prepared.deletingLastPathComponent() == distributionDirectory else {
            throw AppPackagingError.publicationFailed(
                "prepared app must be a sibling of the destination to guarantee a same-volume rename"
            )
        }
        guard fileOperator.itemExists(at: prepared) else {
            throw AppPackagingError.missingInput(prepared)
        }

        try fileOperator.createDirectory(at: distributionDirectory)
        let backup = distributionDirectory.appendingPathComponent(
            ".\(destination.lastPathComponent).backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let hadPreviousApp = fileOperator.itemExists(at: destination)

        do {
            if hadPreviousApp {
                try fileOperator.moveItem(at: destination, to: backup)
            }
            try fileOperator.moveItem(at: prepared, to: destination)
        } catch {
            if hadPreviousApp, fileOperator.itemExists(at: backup) {
                let rollbackError = rollback(
                    destination: destination,
                    backup: backup,
                    hadPreviousApp: true
                )
                if let rollbackError {
                    throw AppPackagingError.publicationFailed(
                        "candidate move failed (\(error.localizedDescription)); rollback also failed (\(rollbackError.localizedDescription))"
                    )
                }
            } else if !hadPreviousApp, fileOperator.itemExists(at: destination) {
                try? fileOperator.removeItem(at: destination)
            }
            throw AppPackagingError.publicationFailed(error.localizedDescription)
        }

        do {
            try await finalValidator(destination)
        } catch {
            let rollbackError = rollback(
                destination: destination,
                backup: backup,
                hadPreviousApp: hadPreviousApp
            )
            if let rollbackError {
                throw AppPackagingError.publicationFailed(
                    "final validation failed (\(error.localizedDescription)); rollback also failed (\(rollbackError.localizedDescription))"
                )
            }
            throw error
        }

        if hadPreviousApp, fileOperator.itemExists(at: backup) {
            do {
                try fileOperator.removeItem(at: backup)
            } catch {
                // A validated destination is authoritative. A stale hidden
                // backup is safer than rolling back a successful publication.
            }
        }
    }

    /// Restores the previous app, removing a failed published candidate first.
    private func rollback(
        destination: URL,
        backup: URL,
        hadPreviousApp: Bool
    ) -> Error? {
        do {
            if fileOperator.itemExists(at: destination) {
                try fileOperator.removeItem(at: destination)
            }
            if hadPreviousApp, fileOperator.itemExists(at: backup) {
                try fileOperator.moveItem(at: backup, to: destination)
            }
            return nil
        } catch {
            return error
        }
    }
}
