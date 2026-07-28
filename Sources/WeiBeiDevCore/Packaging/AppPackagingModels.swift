import Foundation

/// Git-derived provenance embedded into a locally packaged WeiBei app.
public struct AppBuildMetadata: Equatable, Sendable {
    public let version: String
    public let buildNumber: Int
    public let gitCommit: String
    public let sourceDirty: Bool

    /// Creates validated build provenance for an app bundle.
    public init(version: String, buildNumber: Int, gitCommit: String, sourceDirty: Bool) throws {
        guard version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
            throw AppPackagingError.invalidVersion(version)
        }
        guard buildNumber > 0 else {
            throw AppPackagingError.invalidBuildMetadata("build number must be positive")
        }
        guard gitCommit.range(of: #"^[0-9a-fA-F]{40}$"#, options: .regularExpression) != nil else {
            throw AppPackagingError.invalidBuildMetadata("Git commit must be a full 40-character SHA")
        }
        self.version = version
        self.buildNumber = buildNumber
        self.gitCommit = gitCommit.lowercased()
        self.sourceDirty = sourceDirty
    }
}

/// Complete set of paths and product attributes needed to assemble a WeiBei app.
public struct AppBundlePackageRequest: Sendable {
    public let repositoryRoot: URL
    public let buildProductsDirectory: URL
    public let piRuntimeDirectory: URL
    public let stagingRoot: URL
    public let distributionDirectory: URL
    public let productName: String
    public let displayName: String
    public let bundleIdentifier: String
    public let minimumSystemVersion: String
    public let appExecutableName: String
    public let pdfWorkerExecutableName: String
    public let piCheckExecutableName: String
    public let resourceBundleNames: [String]
    public let legalDocumentPaths: [String]

    /// Creates a package request using the repository's established product layout.
    public init(
        repositoryRoot: URL,
        buildProductsDirectory: URL,
        piRuntimeDirectory: URL,
        stagingRoot: URL,
        distributionDirectory: URL? = nil,
        productName: String = "WeiBei",
        displayName: String = "魏碑",
        bundleIdentifier: String = "com.changfenhuang.weibei",
        minimumSystemVersion: String = "14.0",
        appExecutableName: String = "WeiBei",
        pdfWorkerExecutableName: String = "WeiBeiPDFTextWorker",
        piCheckExecutableName: String = "WeiBeiPiCheck",
        resourceBundleNames: [String] = ["WeiBei_WeiBei.bundle", "WeiBei_WeiBeiCore.bundle"],
        legalDocumentPaths: [String] = [
            "PRIVACY.md",
            "THIRD_PARTY_NOTICES.md",
            "ASSET_ATTRIBUTIONS.md",
            "Docs/releases/v1.0.0.md",
        ]
    ) {
        let normalizedRoot = repositoryRoot.standardizedFileURL
        self.repositoryRoot = normalizedRoot
        self.buildProductsDirectory = buildProductsDirectory.standardizedFileURL
        self.piRuntimeDirectory = piRuntimeDirectory.standardizedFileURL
        self.stagingRoot = stagingRoot.standardizedFileURL
        self.distributionDirectory = (distributionDirectory
            ?? normalizedRoot.appendingPathComponent("dist", isDirectory: true)).standardizedFileURL
        self.productName = productName
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.minimumSystemVersion = minimumSystemVersion
        self.appExecutableName = appExecutableName
        self.pdfWorkerExecutableName = pdfWorkerExecutableName
        self.piCheckExecutableName = piCheckExecutableName
        self.resourceBundleNames = resourceBundleNames
        self.legalDocumentPaths = legalDocumentPaths
    }
}

/// Paths and provenance produced by a successful local package operation.
public struct AppBundlePackageResult: Equatable, Sendable {
    public let appBundle: URL
    public let metadata: AppBuildMetadata
    public let executableUUID: String

    /// Creates the result returned after the distribution bundle is validated and published.
    public init(appBundle: URL, metadata: AppBuildMetadata, executableUUID: String) {
        self.appBundle = appBundle
        self.metadata = metadata
        self.executableUUID = executableUUID
    }
}

struct PiRuntimeManifest: Decodable {
    let schemaVersion: Int
    let piVersion: String
}
