import Foundation

/// Stable failures produced while preparing or validating the embedded PI runtime.
public enum PiRuntimePreparationError: Error {
    case repositoryLayoutInvalid(URL)
    case manifestUnreadable(URL, Error)
    case manifestInvalid(String)
    case unsupportedArchitecture(String)
    case cacheLockTimedOut(URL)
    case downloadFailed(URL, Error)
    case archiveHashMismatch(URL, expected: String, actual: String)
    case archiveInvalid(String)
    case processFailed(executable: URL, exitCode: Int32, stderr: String)
    case runtimeInvalid(URL, String)
    case fileOperationFailed(String, Error)

    /// Stable machine-readable error code for CLI JSON output.
    public var code: String {
        switch self {
        case .repositoryLayoutInvalid:
            return "repository_layout_invalid"
        case .manifestUnreadable:
            return "pi_manifest_unreadable"
        case .manifestInvalid:
            return "pi_manifest_invalid"
        case .unsupportedArchitecture:
            return "pi_architecture_unsupported"
        case .cacheLockTimedOut:
            return "pi_cache_lock_timeout"
        case .downloadFailed:
            return "pi_download_failed"
        case .archiveHashMismatch:
            return "pi_archive_hash_mismatch"
        case .archiveInvalid:
            return "pi_archive_invalid"
        case .processFailed:
            return "pi_process_failed"
        case .runtimeInvalid:
            return "pi_runtime_invalid"
        case .fileOperationFailed:
            return "pi_file_operation_failed"
        }
    }
}

extension PiRuntimePreparationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .repositoryLayoutInvalid(url):
            return "PI runtime repository layout is incomplete at \(url.path)"
        case let .manifestUnreadable(url, error):
            return "Cannot read PI runtime manifest at \(url.path): \(error.localizedDescription)"
        case let .manifestInvalid(reason):
            return "PI runtime manifest is invalid: \(reason)"
        case let .unsupportedArchitecture(architecture):
            return "Unsupported PI runtime architecture: \(architecture)"
        case let .cacheLockTimedOut(url):
            return "Timed out waiting for PI runtime cache lock at \(url.path)"
        case let .downloadFailed(url, error):
            return "Failed to download PI runtime from \(url.absoluteString): \(error.localizedDescription)"
        case let .archiveHashMismatch(url, expected, actual):
            return "PI runtime archive SHA-256 mismatch at \(url.path): expected \(expected), got \(actual)"
        case let .archiveInvalid(reason):
            return "PI runtime archive is invalid: \(reason)"
        case let .processFailed(executable, exitCode, stderr):
            return "\(executable.path) failed with exit code \(exitCode): \(stderr)"
        case let .runtimeInvalid(url, reason):
            return "PI runtime at \(url.path) is invalid: \(reason)"
        case let .fileOperationFailed(operation, error):
            return "PI runtime file operation failed (\(operation)): \(error.localizedDescription)"
        }
    }
}
