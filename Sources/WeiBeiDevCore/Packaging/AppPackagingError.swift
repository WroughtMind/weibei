import Foundation

/// Describes a stable failure raised while assembling or publishing an app bundle.
public enum AppPackagingError: Error, LocalizedError, Sendable {
    case missingInput(URL)
    case invalidVersion(String)
    case shallowRepository
    case invalidBuildMetadata(String)
    case stagingDirectoryInsideRepository(URL)
    case invalidPiManifest(URL)
    case processFailed(tool: String, exitCode: Int32, standardError: String)
    case copiedFileMismatch(source: URL, destination: URL)
    case piHashMismatch(expected: String, actual: String)
    case piVersionMismatch(expected: String, actual: String)
    case invalidSignature(URL)
    case pdfWorkerProbeFailed(String)
    case binaryUUIDMismatch(expected: String, actual: String)
    case invalidBundleMetadata(String)
    case publicationFailed(String)

    /// Stable machine-readable identifier suitable for JSON command output.
    public var errorCode: String {
        switch self {
        case .missingInput:
            return "package_input_missing"
        case .invalidVersion:
            return "package_version_invalid"
        case .shallowRepository:
            return "git_history_shallow"
        case .invalidBuildMetadata:
            return "build_metadata_invalid"
        case .stagingDirectoryInsideRepository:
            return "package_staging_inside_repository"
        case .invalidPiManifest:
            return "pi_manifest_invalid"
        case .processFailed:
            return "package_process_failed"
        case .copiedFileMismatch:
            return "package_copy_mismatch"
        case .piHashMismatch:
            return "pi_hash_mismatch"
        case .piVersionMismatch:
            return "pi_version_mismatch"
        case .invalidSignature:
            return "package_signature_invalid"
        case .pdfWorkerProbeFailed:
            return "pdf_worker_probe_failed"
        case .binaryUUIDMismatch:
            return "package_binary_uuid_mismatch"
        case .invalidBundleMetadata:
            return "package_metadata_invalid"
        case .publicationFailed:
            return "package_publication_failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .missingInput(url):
            return "Required packaging input is missing at \(url.path)."
        case let .invalidVersion(version):
            return "VERSION must use numeric major.minor.patch; found \(version)."
        case .shallowRepository:
            return "A full Git history is required to calculate a stable build number."
        case let .invalidBuildMetadata(reason):
            return "Build metadata is invalid: \(reason)"
        case let .stagingDirectoryInsideRepository(url):
            return "The initial app bundle must be assembled outside the repository: \(url.path)."
        case let .invalidPiManifest(url):
            return "The PI runtime manifest is invalid at \(url.path)."
        case let .processFailed(tool, exitCode, standardError):
            let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(tool) failed with exit code \(exitCode)."
                : "\(tool) failed with exit code \(exitCode): \(detail)"
        case let .copiedFileMismatch(source, destination):
            return "Copied file differs from its source: \(source.path) -> \(destination.path)."
        case let .piHashMismatch(expected, actual):
            return "Packaged PI hash mismatch; expected \(expected), found \(actual)."
        case let .piVersionMismatch(expected, actual):
            return "Packaged PI version mismatch; expected \(expected), found \(actual)."
        case let .invalidSignature(url):
            return "Code signature validation failed for \(url.path)."
        case let .pdfWorkerProbeFailed(output):
            return "The signed PDF worker probe failed: \(output)"
        case let .binaryUUIDMismatch(expected, actual):
            return "Packaged app UUID mismatch; expected \(expected), found \(actual)."
        case let .invalidBundleMetadata(reason):
            return "Packaged app metadata is invalid: \(reason)"
        case let .publicationFailed(reason):
            return "Could not publish the app bundle transactionally: \(reason)"
        }
    }
}
