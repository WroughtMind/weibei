import Foundation

/// Materialized paths inside a WeiBei app bundle.
public struct AppBundleLayout: Equatable, Sendable {
    public let bundle: URL
    public let executable: URL
    public let pdfWorker: URL
    public let piExecutable: URL
    public let piRuntimeRoot: URL
    public let infoPlist: URL

    /// Resolves the established bundle layout below an app URL.
    public init(bundle: URL, appExecutableName: String, pdfWorkerExecutableName: String) {
        self.bundle = bundle
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        executable = contents
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(appExecutableName, isDirectory: false)
        pdfWorker = contents
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(pdfWorkerExecutableName, isDirectory: false)
        piRuntimeRoot = contents
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("PiRuntime", isDirectory: true)
        piExecutable = piRuntimeRoot
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("pi", isDirectory: false)
        infoPlist = contents.appendingPathComponent("Info.plist", isDirectory: false)
    }
}

/// Assembles all product, runtime, icon, and legal resources before signing.
public struct AppBundleAssembler: @unchecked Sendable {
    private let fileManager: FileManager

    /// Creates an assembler backed by the supplied file manager.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Builds an unsigned app bundle in a unique directory outside the repository.
    ///
    /// - Parameters:
    ///   - request: Product paths and bundle attributes.
    ///   - metadata: Version and Git provenance written to `Info.plist`.
    /// - Returns: Paths for the newly assembled app bundle.
    public func assemble(
        request: AppBundlePackageRequest,
        metadata: AppBuildMetadata
    ) throws -> AppBundleLayout {
        let repository = request.repositoryRoot.standardizedFileURL
        let stagingRoot = request.stagingRoot.standardizedFileURL
        guard !stagingRoot.isEqualToOrDescendant(of: repository) else {
            throw AppPackagingError.stagingDirectoryInsideRepository(stagingRoot)
        }

        let workingDirectory = stagingRoot.appendingPathComponent(
            "weibei-package-\(UUID().uuidString)",
            isDirectory: true
        )
        let bundle = workingDirectory.appendingPathComponent(
            "\(request.displayName).app",
            isDirectory: true
        )
        let layout = AppBundleLayout(
            bundle: bundle,
            appExecutableName: request.appExecutableName,
            pdfWorkerExecutableName: request.pdfWorkerExecutableName
        )
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)

        try fileManager.createDirectory(
            at: layout.executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: layout.pdfWorker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

        let builtExecutable = request.buildProductsDirectory.appendingPathComponent(
            request.appExecutableName,
            isDirectory: false
        )
        let builtPDFWorker = request.buildProductsDirectory.appendingPathComponent(
            request.pdfWorkerExecutableName,
            isDirectory: false
        )
        try copyRequiredFile(from: builtExecutable, to: layout.executable, executable: true)
        try copyRequiredFile(from: builtPDFWorker, to: layout.pdfWorker, executable: true)

        for bundleName in request.resourceBundleNames {
            let source = request.buildProductsDirectory.appendingPathComponent(
                bundleName,
                isDirectory: true
            )
            guard isDirectory(source) else {
                throw AppPackagingError.missingInput(source)
            }
            try fileManager.copyItem(
                at: source,
                to: resources.appendingPathComponent(bundleName, isDirectory: true)
            )
        }

        try copyPiRuntime(from: request.piRuntimeDirectory, to: layout.piRuntimeRoot)

        let iconSource = repository
            .appendingPathComponent("DesignSystem/assets/app-icon", isDirectory: true)
            .appendingPathComponent("AppIcon.icns", isDirectory: false)
        try copyRequiredFile(
            from: iconSource,
            to: resources.appendingPathComponent("AppIcon.icns", isDirectory: false)
        )

        let legalDestination = resources.appendingPathComponent("Legal", isDirectory: true)
        try fileManager.createDirectory(at: legalDestination, withIntermediateDirectories: true)
        for relativePath in request.legalDocumentPaths {
            let source = repository.appendingPathComponent(relativePath, isDirectory: false)
            try copyRequiredFile(
                from: source,
                to: legalDestination.appendingPathComponent(source.lastPathComponent, isDirectory: false)
            )
        }

        try writeInfoPlist(request: request, metadata: metadata, destination: layout.infoPlist)
        return layout
    }

    /// Copies the allowlisted PI runtime payload into the app Resources directory.
    private func copyPiRuntime(from sourceRoot: URL, to destinationRoot: URL) throws {
        let sourceBin = sourceRoot.appendingPathComponent("bin", isDirectory: true)
        let destinationBin = destinationRoot.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: destinationBin, withIntermediateDirectories: true)
        try copyRequiredFile(
            from: sourceBin.appendingPathComponent("pi", isDirectory: false),
            to: destinationBin.appendingPathComponent("pi", isDirectory: false),
            executable: true
        )
        try copyRequiredFile(
            from: sourceBin.appendingPathComponent("package.json", isDirectory: false),
            to: destinationBin.appendingPathComponent("package.json", isDirectory: false)
        )

        let themeSource = sourceBin.appendingPathComponent("theme", isDirectory: true)
        guard isDirectory(themeSource) else {
            throw AppPackagingError.missingInput(themeSource)
        }
        try fileManager.copyItem(
            at: themeSource,
            to: destinationBin.appendingPathComponent("theme", isDirectory: true)
        )

        for name in [
            "manifest.json",
            "LICENSE",
            "THIRD_PARTY_NOTICES.md",
            "artifact.sha256",
            "binary.sha256",
        ] {
            try copyRequiredFile(
                from: sourceRoot.appendingPathComponent(name, isDirectory: false),
                to: destinationRoot.appendingPathComponent(name, isDirectory: false)
            )
        }
    }

    /// Copies one required file, preserving executable intent and verifying bytes.
    private func copyRequiredFile(
        from source: URL,
        to destination: URL,
        executable: Bool = false
    ) throws {
        guard isRegularFile(source) else {
            throw AppPackagingError.missingInput(source)
        }
        try fileManager.copyItem(at: source, to: destination)
        if executable {
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.path
            )
        }
        guard try filesHaveEqualContents(source, destination) else {
            throw AppPackagingError.copiedFileMismatch(source: source, destination: destination)
        }
    }

    /// Writes product identity and exact build provenance into the bundle metadata.
    private func writeInfoPlist(
        request: AppBundlePackageRequest,
        metadata: AppBuildMetadata,
        destination: URL
    ) throws {
        let properties: [String: Any] = [
            "CFBundleExecutable": request.appExecutableName,
            "CFBundleIdentifier": request.bundleIdentifier,
            "CFBundleName": request.displayName,
            "CFBundleDisplayName": request.displayName,
            "CFBundleIconFile": "AppIcon.icns",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": metadata.version,
            "CFBundleVersion": String(metadata.buildNumber),
            "WeiBeiGitCommit": metadata.gitCommit,
            "WeiBeiSourceDirty": metadata.sourceDirty,
            "LSMinimumSystemVersion": request.minimumSystemVersion,
            "NSPrincipalClass": "NSApplication",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: properties,
            format: .xml,
            options: 0
        )
        try data.write(to: destination, options: .atomic)
    }

    /// Reports whether a URL exists as a non-directory filesystem entry.
    private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    /// Reports whether a URL exists as a directory.
    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Compares copied inputs byte-for-byte after an inexpensive size check.
    private func filesHaveEqualContents(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let lhsAttributes = try fileManager.attributesOfItem(atPath: lhs.path)
        let rhsAttributes = try fileManager.attributesOfItem(atPath: rhs.path)
        guard lhsAttributes[.size] as? NSNumber == rhsAttributes[.size] as? NSNumber else {
            return false
        }
        return try Data(contentsOf: lhs, options: .mappedIfSafe)
            == Data(contentsOf: rhs, options: .mappedIfSafe)
    }
}

private extension URL {
    /// Prevents staging beneath the repository, including the repository root itself.
    func isEqualToOrDescendant(of directory: URL) -> Bool {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let candidateComponents = standardizedFileURL.pathComponents
        return candidateComponents.starts(with: directoryComponents)
    }
}
