import Foundation

/// Validation point in the transactionally published app lifecycle.
public enum AppBundleValidationPhase: String, Sendable {
    case staged
    case distributionCandidate
    case published
}

/// Seals and validates app bundles with system tools at each packaging boundary.
public protocol AppBundlePackageValidating: Sendable {
    /// Validates an app bundle and returns the UUID of its main executable.
    ///
    /// Implementations use the shared process executor to clear extended
    /// attributes, ad-hoc sign nested executables and the app, run the PDF
    /// worker probe and PI check, verify signatures, and compare Mach-O UUIDs.
    ///
    /// - Parameters:
    ///   - layout: Paths within the app being validated.
    ///   - builtExecutable: Main executable produced by the current Swift build.
    ///   - request: Product and repository expectations.
    ///   - metadata: Expected build provenance.
    ///   - phase: Current publication boundary.
    /// - Returns: UUID reported for the app's main executable.
    func validate(
        layout: AppBundleLayout,
        builtExecutable: URL,
        request: AppBundlePackageRequest,
        metadata: AppBuildMetadata,
        phase: AppBundleValidationPhase
    ) async throws -> String
}

/// Orchestrates assembly, staged validation, and transaction-safe publication.
public final class AppBundlePackager: @unchecked Sendable {
    private let assembler: AppBundleAssembler
    private let inspector: AppBundleInspector
    private let publisher: TransactionalAppPublisher
    private let fileOperator: any AppBundleFileOperating

    /// Creates the production app bundle packaging workflow.
    public convenience init() {
        self.init(
            assembler: AppBundleAssembler(),
            inspector: AppBundleInspector(),
            publisher: TransactionalAppPublisher(),
            fileOperator: FoundationAppBundleFileOperator()
        )
    }

    /// Creates a packager from injectable assembly, inspection, publication, and file services.
    init(
        assembler: AppBundleAssembler,
        inspector: AppBundleInspector,
        publisher: TransactionalAppPublisher,
        fileOperator: any AppBundleFileOperating
    ) {
        self.assembler = assembler
        self.inspector = inspector
        self.publisher = publisher
        self.fileOperator = fileOperator
    }

    /// Packages the current release build and updates only `dist/魏碑.app`.
    ///
    /// The initial bundle is assembled outside the repository. A validated
    /// copy is then created under a hidden path in `dist`, validated again,
    /// and renamed into place. Any failure before or after the rename leaves
    /// the previous distribution app intact.
    ///
    /// - Parameters:
    ///   - request: Repository, build product, runtime, and destination paths.
    ///   - metadata: Version and Git provenance embedded in the bundle.
    ///   - validator: System-level signing and runtime validator.
    /// - Returns: Final app path and validated executable provenance.
    public func package(
        request: AppBundlePackageRequest,
        metadata: AppBuildMetadata,
        validator: any AppBundlePackageValidating
    ) async throws -> AppBundlePackageResult {
        let builtExecutable = request.buildProductsDirectory.appendingPathComponent(
            request.appExecutableName,
            isDirectory: false
        )
        guard fileOperator.itemExists(at: builtExecutable) else {
            throw AppPackagingError.missingInput(builtExecutable)
        }

        let stagedLayout = try assembler.assemble(request: request, metadata: metadata)
        let stagingWorkingDirectory = stagedLayout.bundle.deletingLastPathComponent()
        defer {
            if fileOperator.itemExists(at: stagingWorkingDirectory) {
                try? fileOperator.removeItem(at: stagingWorkingDirectory)
            }
        }

        _ = try inspector.inspect(
            layout: stagedLayout,
            request: request,
            metadata: metadata
        )
        let stagedUUID = try await validator.validate(
            layout: stagedLayout,
            builtExecutable: builtExecutable,
            request: request,
            metadata: metadata,
            phase: .staged
        )
        guard !stagedUUID.isEmpty else {
            throw AppPackagingError.binaryUUIDMismatch(expected: "non-empty UUID", actual: "")
        }

        try fileOperator.createDirectory(at: request.distributionDirectory)
        let candidate = request.distributionDirectory.appendingPathComponent(
            ".\(request.displayName).app.staging-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            if fileOperator.itemExists(at: candidate) {
                try? fileOperator.removeItem(at: candidate)
            }
        }
        try fileOperator.copyItem(at: stagedLayout.bundle, to: candidate)

        let candidateLayout = AppBundleLayout(
            bundle: candidate,
            appExecutableName: request.appExecutableName,
            pdfWorkerExecutableName: request.pdfWorkerExecutableName
        )
        _ = try inspector.inspect(
            layout: candidateLayout,
            request: request,
            metadata: metadata
        )
        guard try filesHaveEqualContents(stagedLayout.executable, candidateLayout.executable) else {
            throw AppPackagingError.copiedFileMismatch(
                source: stagedLayout.executable,
                destination: candidateLayout.executable
            )
        }
        let candidateUUID = try await validator.validate(
            layout: candidateLayout,
            builtExecutable: builtExecutable,
            request: request,
            metadata: metadata,
            phase: .distributionCandidate
        )
        guard candidateUUID == stagedUUID else {
            throw AppPackagingError.binaryUUIDMismatch(
                expected: stagedUUID,
                actual: candidateUUID
            )
        }
        let candidateExecutableContents = try Data(
            contentsOf: candidateLayout.executable,
            options: .mappedIfSafe
        )

        let destination = request.distributionDirectory.appendingPathComponent(
            "\(request.displayName).app",
            isDirectory: true
        )
        try await publisher.publish(
            preparedAppBundle: candidate,
            to: destination
        ) { published in
            let publishedLayout = AppBundleLayout(
                bundle: published,
                appExecutableName: request.appExecutableName,
                pdfWorkerExecutableName: request.pdfWorkerExecutableName
            )
            _ = try self.inspector.inspect(
                layout: publishedLayout,
                request: request,
                metadata: metadata
            )
            guard try candidateExecutableContents == Data(
                contentsOf: publishedLayout.executable,
                options: .mappedIfSafe
            ) else {
                throw AppPackagingError.copiedFileMismatch(
                    source: candidateLayout.executable,
                    destination: publishedLayout.executable
                )
            }
            let publishedUUID = try await validator.validate(
                layout: publishedLayout,
                builtExecutable: builtExecutable,
                request: request,
                metadata: metadata,
                phase: .published
            )
            guard publishedUUID == candidateUUID else {
                throw AppPackagingError.binaryUUIDMismatch(
                    expected: candidateUUID,
                    actual: publishedUUID
                )
            }
        }

        return AppBundlePackageResult(
            appBundle: destination,
            metadata: metadata,
            executableUUID: candidateUUID
        )
    }

    /// Ensures publication copies did not alter the current build executable.
    private func filesHaveEqualContents(_ lhs: URL, _ rhs: URL) throws -> Bool {
        try Data(contentsOf: lhs, options: .mappedIfSafe)
            == Data(contentsOf: rhs, options: .mappedIfSafe)
    }
}
