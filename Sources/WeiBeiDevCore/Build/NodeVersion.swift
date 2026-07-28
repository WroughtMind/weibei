import Foundation

/// Parsed semantic version reported by the Node.js executable.
public struct NodeVersion: Codable, Equatable, Sendable {
    /// Semantic major version.
    public let major: Int
    /// Semantic minor version.
    public let minor: Int
    /// Semantic patch version.
    public let patch: Int

    /// Normalized semantic version without Node.js's leading `v`.
    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    /// Creates a semantic Node.js version.
    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses the output produced by `node --version`.
    ///
    /// - Parameter output: Version text such as `v22.22.3`.
    /// - Returns: Parsed numeric Node.js version.
    public static func parse(_ output: String) throws -> NodeVersion {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionText = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let components = versionText.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patchText = components[2].split(separator: "-", maxSplits: 1).first,
              let patch = Int(patchText)
        else {
            throw BuildWorkflowError.unreadableNodeVersion(trimmed)
        }
        return NodeVersion(major: major, minor: minor, patch: patch)
    }

    /// Ensures the version meets the minimum supported Node.js major release.
    public func requireSupportedMajor() throws {
        guard major >= 22 else {
            throw BuildWorkflowError.unsupportedNodeVersion(description)
        }
    }
}
