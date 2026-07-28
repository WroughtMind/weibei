import Foundation

/// Pure filesystem and metadata inspection for a fully assembled app bundle.
public struct AppBundleInspector: @unchecked Sendable {
    private let fileManager: FileManager

    /// Creates an inspector backed by the supplied file manager.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Verifies required files and exact build provenance without invoking system tools.
    ///
    /// - Parameters:
    ///   - layout: Materialized paths inside the app bundle.
    ///   - request: Product resource and bundle expectations.
    ///   - metadata: Expected version and source provenance.
    /// - Returns: PI version declared by the packaged runtime manifest.
    public func inspect(
        layout: AppBundleLayout,
        request: AppBundlePackageRequest,
        metadata: AppBuildMetadata
    ) throws -> String {
        for executable in [layout.executable, layout.pdfWorker, layout.piExecutable] {
            guard fileManager.isExecutableFile(atPath: executable.path) else {
                throw AppPackagingError.missingInput(executable)
            }
        }

        let resources = layout.bundle.appendingPathComponent(
            "Contents/Resources",
            isDirectory: true
        )
        for bundleName in request.resourceBundleNames {
            let resourceBundle = resources.appendingPathComponent(bundleName, isDirectory: true)
            guard isDirectory(resourceBundle) else {
                throw AppPackagingError.missingInput(resourceBundle)
            }
        }
        for requiredPath in [
            "PiRuntime/manifest.json",
            "PiRuntime/LICENSE",
            "PiRuntime/THIRD_PARTY_NOTICES.md",
            "PiRuntime/artifact.sha256",
            "PiRuntime/binary.sha256",
            "PiRuntime/bin/package.json",
            "AppIcon.icns",
        ] {
            let requiredURL = resources.appendingPathComponent(requiredPath, isDirectory: false)
            guard isRegularFile(requiredURL) else {
                throw AppPackagingError.missingInput(requiredURL)
            }
        }
        let piTheme = resources.appendingPathComponent("PiRuntime/bin/theme", isDirectory: true)
        guard isDirectory(piTheme) else {
            throw AppPackagingError.missingInput(piTheme)
        }
        for relativePath in request.legalDocumentPaths {
            let legalDocument = resources
                .appendingPathComponent("Legal", isDirectory: true)
                .appendingPathComponent(
                    URL(fileURLWithPath: relativePath).lastPathComponent,
                    isDirectory: false
                )
            guard isRegularFile(legalDocument) else {
                throw AppPackagingError.missingInput(legalDocument)
            }
        }

        try inspectInfoPlist(
            at: layout.infoPlist,
            request: request,
            metadata: metadata
        )

        let manifestURL = layout.piRuntimeRoot.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )
        guard let manifest = try? JSONDecoder().decode(
            PiRuntimeManifest.self,
            from: Data(contentsOf: manifestURL)
        ),
        manifest.schemaVersion == 1,
        !manifest.piVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AppPackagingError.invalidPiManifest(manifestURL)
        }

        if let enumerator = fileManager.enumerator(
            at: layout.bundle,
            includingPropertiesForKeys: nil
        ) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "map" {
                throw AppPackagingError.invalidBundleMetadata(
                    "source map must not be packaged: \(fileURL.path)"
                )
            }
        }
        return manifest.piVersion
    }

    /// Confirms Info.plist matches product settings and Git-derived metadata.
    private func inspectInfoPlist(
        at url: URL,
        request: AppBundlePackageRequest,
        metadata: AppBuildMetadata
    ) throws {
        guard let properties = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url),
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw AppPackagingError.invalidBundleMetadata("Info.plist is not a dictionary")
        }

        let expectedStrings = [
            "CFBundleExecutable": request.appExecutableName,
            "CFBundleIdentifier": request.bundleIdentifier,
            "CFBundleName": request.displayName,
            "CFBundleDisplayName": request.displayName,
            "CFBundleIconFile": "AppIcon.icns",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": metadata.version,
            "CFBundleVersion": String(metadata.buildNumber),
            "WeiBeiGitCommit": metadata.gitCommit,
            "LSMinimumSystemVersion": request.minimumSystemVersion,
            "NSPrincipalClass": "NSApplication",
        ]
        for (key, expected) in expectedStrings {
            guard properties[key] as? String == expected else {
                throw AppPackagingError.invalidBundleMetadata(
                    "Info.plist \(key) does not match \(expected)"
                )
            }
        }
        let dirty: Bool?
        if let value = properties["WeiBeiSourceDirty"] as? Bool {
            dirty = value
        } else if let value = properties["WeiBeiSourceDirty"] as? NSNumber {
            dirty = value.boolValue
        } else {
            dirty = nil
        }
        guard dirty == metadata.sourceDirty else {
            throw AppPackagingError.invalidBundleMetadata(
                "Info.plist WeiBeiSourceDirty does not match source state"
            )
        }
    }

    /// Reports whether a required bundle entry is a regular file.
    private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    /// Reports whether a required bundle entry is a directory.
    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
