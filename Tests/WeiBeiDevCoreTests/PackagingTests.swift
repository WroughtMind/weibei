import Foundation
import XCTest
@testable import WeiBeiDevCore

final class PackagingTests: XCTestCase {
    private var temporaryRoot: URL!

    /// 为单个测试套件实例创建隔离的打包根目录。
    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "weibei-packaging-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    /// 清理测试套件创建的全部临时打包资源。
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryRoot.path) {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    /// 验证组装器复制全部产品资源并写入可追溯构建元数据。
    func testAssemblerCopiesProductResourcesAndWritesBuildMetadata() throws {
        let fixture = try makePackageFixture()
        let metadata = try AppBuildMetadata(
            version: "1.2.3",
            buildNumber: 42,
            gitCommit: String(repeating: "a", count: 40),
            sourceDirty: true
        )

        let layout = try AppBundleAssembler().assemble(
            request: fixture.request,
            metadata: metadata
        )

        XCTAssertTrue(try Data(contentsOf: layout.executable) == Data("app".utf8))
        XCTAssertTrue(try Data(contentsOf: layout.pdfWorker) == Data("worker".utf8))
        XCTAssertTrue(try Data(contentsOf: layout.piExecutable) == Data("pi".utf8))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: layout.bundle
                    .appendingPathComponent("Contents/Resources/WeiBei_WeiBei.bundle/resource.txt")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: layout.bundle
                    .appendingPathComponent("Contents/Resources/Legal/PRIVACY.md")
                    .path
            )
        )

        let plistData = try Data(contentsOf: layout.infoPlist)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertTrue(plist["CFBundleShortVersionString"] as? String == "1.2.3")
        XCTAssertTrue(plist["CFBundleVersion"] as? String == "42")
        XCTAssertTrue(plist["WeiBeiGitCommit"] as? String == String(repeating: "a", count: 40))
        XCTAssertTrue(plist["WeiBeiSourceDirty"] as? Bool == true)
        XCTAssertTrue(
            try AppBundleInspector().inspect(
                layout: layout,
                request: fixture.request,
                metadata: metadata
            ) == "0.80.2"
        )
    }

    /// 验证组装器拒绝在仓库内部创建初始 staging bundle。
    func testAssemblerRejectsStagingInsideRepository() throws {
        let fixture = try makePackageFixture(stagingInsideRepository: true)
        let metadata = try AppBuildMetadata(
            version: "1.0.0",
            buildNumber: 1,
            gitCommit: String(repeating: "b", count: 40),
            sourceDirty: false
        )

        do {
            _ = try AppBundleAssembler().assemble(request: fixture.request, metadata: metadata)
            XCTFail("Expected assembly to reject staging inside the repository.")
        } catch {
            let packagingError = try XCTUnwrap(error as? AppPackagingError)
            XCTAssertTrue(packagingError.errorCode == "package_staging_inside_repository")
        }
    }

    /// 验证最终发布校验失败时恢复上一份可用 App。
    func testPublicationFailureRestoresPreviousApp() async throws {
        let distribution = temporaryRoot.appendingPathComponent("dist", isDirectory: true)
        let destination = distribution.appendingPathComponent("魏碑.app", isDirectory: true)
        let candidate = distribution.appendingPathComponent(".candidate.app", isDirectory: true)
        try writeMarker("old", in: destination)
        try writeMarker("new", in: candidate)

        do {
            try await TransactionalAppPublisher().publish(
                preparedAppBundle: candidate,
                to: destination
            ) { _ in
                throw AppPackagingError.invalidSignature(destination)
            }
            XCTFail("Expected final validation to fail.")
        } catch {
            let packagingError = try XCTUnwrap(error as? AppPackagingError)
            XCTAssertTrue(packagingError.errorCode == "package_signature_invalid")
        }

        XCTAssertTrue(try readMarker(in: destination) == "old")
        XCTAssertTrue(!FileManager.default.fileExists(atPath: candidate.path))
        let remaining = try FileManager.default.contentsOfDirectory(
            at: distribution,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(!remaining.contains { $0.lastPathComponent.contains(".backup-") })
    }

    /// 验证成功发布会替换旧 App 并清理候选产物。
    func testSuccessfulPublicationReplacesPreviousApp() async throws {
        let distribution = temporaryRoot.appendingPathComponent("dist", isDirectory: true)
        let destination = distribution.appendingPathComponent("魏碑.app", isDirectory: true)
        let candidate = distribution.appendingPathComponent(".candidate.app", isDirectory: true)
        try writeMarker("old", in: destination)
        try writeMarker("new", in: candidate)

        try await TransactionalAppPublisher().publish(
            preparedAppBundle: candidate,
            to: destination
        ) { published in
            let marker = try? self.readMarker(in: published)
            XCTAssertTrue(marker == "new")
        }

        XCTAssertTrue(try readMarker(in: destination) == "new")
        XCTAssertTrue(!FileManager.default.fileExists(atPath: candidate.path))
    }

    /// 验证 Packager 的已发布阶段校验失败时完整恢复旧分发产物。
    func testPackagerRestoresPreviousDistributionWhenPublishedValidationFails() async throws {
        let fixture = try makePackageFixture()
        try write("pi-check", to: fixture.request.buildProductsDirectory.appendingPathComponent("WeiBeiPiCheck"))
        let destination = fixture.request.distributionDirectory.appendingPathComponent(
            "魏碑.app",
            isDirectory: true
        )
        try writeMarker("old", in: destination)
        let metadata = try AppBuildMetadata(
            version: "1.0.0",
            buildNumber: 7,
            gitCommit: String(repeating: "d", count: 40),
            sourceDirty: true
        )
        let validator = PackageValidatorStub { phase in
            if phase == .published {
                throw AppPackagingError.invalidSignature(destination)
            }
            return "BUILD-UUID"
        }

        do {
            _ = try await AppBundlePackager().package(
                request: fixture.request,
                metadata: metadata,
                validator: validator
            )
            XCTFail("Expected published validation to fail.")
        } catch {
            let packagingError = try XCTUnwrap(error as? AppPackagingError)
            XCTAssertTrue(packagingError.errorCode == "package_signature_invalid")
        }

        XCTAssertTrue(try readMarker(in: destination) == "old")
        let distributionItems = try FileManager.default.contentsOfDirectory(
            at: fixture.request.distributionDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(distributionItems.map(\.lastPathComponent) == ["魏碑.app"])
    }

    /// 验证 Packager 发布通过校验的 bundle 并返回构建 UUID。
    func testPackagerPublishesValidatedBundleAndReturnsUUID() async throws {
        let fixture = try makePackageFixture()
        try write("pi-check", to: fixture.request.buildProductsDirectory.appendingPathComponent("WeiBeiPiCheck"))
        let metadata = try AppBuildMetadata(
            version: "1.0.0",
            buildNumber: 8,
            gitCommit: String(repeating: "e", count: 40),
            sourceDirty: false
        )

        let result = try await AppBundlePackager().package(
            request: fixture.request,
            metadata: metadata,
            validator: PackageValidatorStub { _ in "BUILD-UUID" }
        )

        XCTAssertTrue(result.executableUUID == "BUILD-UUID")
        XCTAssertTrue(result.appBundle.lastPathComponent == "魏碑.app")
        XCTAssertTrue(
            try Data(
                contentsOf: result.appBundle.appendingPathComponent("Contents/MacOS/WeiBei")
            ) == Data("app".utf8)
        )
    }

    /// 验证安装包检查器拒绝携带 source map 的资源。
    func testInspectorRejectsSourceMaps() throws {
        let fixture = try makePackageFixture()
        let metadata = try AppBuildMetadata(
            version: "1.0.0",
            buildNumber: 1,
            gitCommit: String(repeating: "c", count: 40),
            sourceDirty: false
        )
        let layout = try AppBundleAssembler().assemble(
            request: fixture.request,
            metadata: metadata
        )
        try write(
            "{}",
            to: layout.bundle.appendingPathComponent("Contents/Resources/editor.js.map")
        )

        do {
            _ = try AppBundleInspector().inspect(
                layout: layout,
                request: fixture.request,
                metadata: metadata
            )
            XCTFail("Expected inspection to reject source maps.")
        } catch {
            let packagingError = try XCTUnwrap(error as? AppPackagingError)
            XCTAssertTrue(packagingError.errorCode == "package_metadata_invalid")
        }
    }

    /// 创建包含可组装产品、runtime 和法律资源的隔离 fixture。
    private func makePackageFixture(
        stagingInsideRepository: Bool = false
    ) throws -> (request: AppBundlePackageRequest, repository: URL) {
        let repository = temporaryRoot.appendingPathComponent("repository", isDirectory: true)
        let build = repository.appendingPathComponent(".build/products", isDirectory: true)
        let runtime = temporaryRoot.appendingPathComponent("runtime", isDirectory: true)
        let staging = stagingInsideRepository
            ? repository.appendingPathComponent(".staging", isDirectory: true)
            : temporaryRoot.appendingPathComponent("staging", isDirectory: true)

        try write("app", to: build.appendingPathComponent("WeiBei"))
        try write("worker", to: build.appendingPathComponent("WeiBeiPDFTextWorker"))
        for name in ["WeiBei_WeiBei.bundle", "WeiBei_WeiBeiCore.bundle"] {
            try write(
                "resource",
                to: build
                    .appendingPathComponent(name, isDirectory: true)
                    .appendingPathComponent("resource.txt")
            )
        }
        try write("pi", to: runtime.appendingPathComponent("bin/pi"))
        try write("{}", to: runtime.appendingPathComponent("bin/package.json"))
        try write("theme", to: runtime.appendingPathComponent("bin/theme/default.json"))
        try write(#"{"schemaVersion":1,"piVersion":"0.80.2"}"#, to: runtime.appendingPathComponent("manifest.json"))
        try write("license", to: runtime.appendingPathComponent("LICENSE"))
        try write("notices", to: runtime.appendingPathComponent("THIRD_PARTY_NOTICES.md"))
        try write("archive", to: runtime.appendingPathComponent("artifact.sha256"))
        try write("binary", to: runtime.appendingPathComponent("binary.sha256"))
        try write(
            "icon",
            to: repository.appendingPathComponent("DesignSystem/assets/app-icon/AppIcon.icns")
        )
        for path in [
            "PRIVACY.md",
            "THIRD_PARTY_NOTICES.md",
            "ASSET_ATTRIBUTIONS.md",
            "Docs/releases/v1.0.0.md",
        ] {
            try write(path, to: repository.appendingPathComponent(path))
        }

        return (
            AppBundlePackageRequest(
                repositoryRoot: repository,
                buildProductsDirectory: build,
                piRuntimeDirectory: runtime,
                stagingRoot: staging
            ),
            repository
        )
    }

    /// 写入 fixture 文件并按需创建父目录。
    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }

    /// 在模拟 App bundle 中写入可识别版本标记。
    private func writeMarker(_ value: String, in directory: URL) throws {
        try write(value, to: directory.appendingPathComponent("marker.txt"))
    }

    /// 读取模拟 App bundle 的版本标记。
    private func readMarker(in directory: URL) throws -> String {
        try String(
            contentsOf: directory.appendingPathComponent("marker.txt"),
            encoding: .utf8
        )
    }
}

private struct PackageValidatorStub: AppBundlePackageValidating {
    let validation: @Sendable (AppBundleValidationPhase) throws -> String

    /// 将打包校验阶段转发给测试提供的故障注入闭包。
    func validate(
        layout _: AppBundleLayout,
        builtExecutable _: URL,
        request _: AppBundlePackageRequest,
        metadata _: AppBuildMetadata,
        phase: AppBundleValidationPhase
    ) async throws -> String {
        try validation(phase)
    }
}
