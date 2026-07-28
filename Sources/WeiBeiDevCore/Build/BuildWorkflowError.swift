import Foundation

/// Stable failures reported by dependency preparation and build workflows.
public enum BuildWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case missingExecutable(String)
    case missingRequiredFile(URL)
    case unsupportedNodeVersion(String)
    case unreadableNodeVersion(String)
    case commandFailed(command: String, exitDescription: String, standardError: String)
    case invalidBuildProductsDirectory(String)
    case missingBuildProduct(URL)
    case missingGeneratedResource(URL)
    case preparationStampWriteFailed(URL, String)

    /// Stable code exposed in structured CLI errors.
    public var errorCode: String {
        switch self {
        case .missingExecutable:
            return "missing_executable"
        case .missingRequiredFile:
            return "missing_build_input"
        case .unsupportedNodeVersion:
            return "unsupported_node_version"
        case .unreadableNodeVersion:
            return "unreadable_node_version"
        case .commandFailed:
            return "build_command_failed"
        case .invalidBuildProductsDirectory:
            return "invalid_build_products_directory"
        case .missingBuildProduct:
            return "missing_build_product"
        case .missingGeneratedResource:
            return "missing_generated_resource"
        case .preparationStampWriteFailed:
            return "preparation_stamp_write_failed"
        }
    }

    /// Human-readable dependency preparation or build failure.
    public var errorDescription: String? {
        switch self {
        case let .missingExecutable(name):
            return "Required executable '\(name)' was not found in PATH."
        case let .missingRequiredFile(url):
            return "Required build input is missing at \(url.path)."
        case let .unsupportedNodeVersion(version):
            return "Node.js >=22 <23 is required, but \(version) is active. Run `nvm install 22.22.3 && nvm use 22.22.3`."
        case let .unreadableNodeVersion(output):
            return "Could not parse the Node.js version from '\(output)'."
        case let .commandFailed(command, exitDescription, standardError):
            let detail = standardError.isEmpty ? "" : " \(standardError)"
            return "Command failed (\(exitDescription)): \(command).\(detail)"
        case let .invalidBuildProductsDirectory(output):
            return "SwiftPM returned an invalid build products directory: \(output)"
        case let .missingBuildProduct(url):
            return "Expected Swift build product is missing or not executable at \(url.path)."
        case let .missingGeneratedResource(url):
            return "Expected generated WebEditor resource is missing or empty at \(url.path)."
        case let .preparationStampWriteFailed(url, reason):
            return "Could not write the Node dependency preparation stamp at \(url.path): \(reason)"
        }
    }
}
