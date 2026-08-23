import XCTest
@testable import WeiBei
import WeiBeiCore

final class ContextualContentPerformanceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testDirectoryExpansionSkipsDependenciesButAllowsExplicitFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rootMaterial = root.appendingPathComponent("root.md")
        let buildMaterial = root.appendingPathComponent("build/讲义.md")
        let dependencyMaterial = root.appendingPathComponent("node_modules/README.md")
        try writeMaterial(at: rootMaterial)
        try writeMaterial(at: buildMaterial)
        try writeMaterial(at: dependencyMaterial)

        let directoryExpansion = CourseProjectFileWorker.expandedSupportedFiles(
            from: [root],
            markdownOnly: false
        )
        XCTAssertEqual(
            directoryExpansion.map(\.standardizedFileURL),
            [buildMaterial, rootMaterial].map(\.standardizedFileURL)
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        )

        let directExpansion = CourseProjectFileWorker.expandedSupportedFiles(
            from: [dependencyMaterial],
            markdownOnly: false
        )
        XCTAssertEqual(
            directExpansion.map(\.standardizedFileURL),
            [dependencyMaterial.standardizedFileURL]
        )
    }

    func testDirectoryExpansionKeepsEveryDeduplicatedFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0...500 {
            try writeMaterial(at: root.appendingPathComponent("material-\(index).md"))
        }

        XCTAssertEqual(
            CourseProjectFileWorker.expandedSupportedFiles(
                from: [root, root],
                markdownOnly: false
            ).count,
            501
        )
    }

    func testCourseScanIgnoresNewDependenciesAndPreservesRegisteredPaths() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ordinary = root.appendingPathComponent("资料/讲义.md")
        let dependency = root.appendingPathComponent("node_modules/pkg/README.md")
        try writeMaterial(at: ordinary)
        try writeMaterial(at: dependency)

        let snapshot = try await CourseProjectFileWorker().scanCourse(at: root)

        XCTAssertEqual(snapshot.observations.map(\.relativePath), ["资料/讲义.md"])
        XCTAssertTrue(snapshot.preservesExistingRecord(at: "node_modules/pkg/README.md"))
        XCTAssertFalse(snapshot.preservesExistingRecord(at: "资料/缺失.md"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiImportExpansion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeMaterial(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("material".utf8).write(to: url)
    }
}
