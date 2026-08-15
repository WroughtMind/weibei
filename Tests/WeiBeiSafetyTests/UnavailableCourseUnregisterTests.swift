import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class UnavailableCourseUnregisterTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    func testUnregisterUnavailableCourseLeavesExternalFiles() async throws {
        let fixture = try Fixture(name: "unregister-success")
        defer { fixture.remove() }

        let external = fixture.root.appendingPathComponent("external-course", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let marker = external.appendingPathComponent("must-survive.txt")
        let markerData = Data("KEEP".utf8)
        try markerData.write(to: marker)
        let courseID = UUID()
        try fixture.write(
            PersistedWorkspace(
                importedItems: [],
                courses: [
                    Course(
                        id: courseID,
                        title: "失联课程",
                        sourceRootPath: external.path
                    ),
                ],
                activeCourseID: courseID
            )
        )
        try FileManager.default.removeItem(at: external)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try markerData.write(to: marker)
        let beforeBytes = try Data(contentsOf: marker)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        XCTAssertNotNil(store.course(withID: courseID))
        try store.removeCourseFromWeiBeiForSelfCheck(courseID)
        XCTAssertNil(store.course(withID: courseID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(try Data(contentsOf: marker), beforeBytes)
    }

    @MainActor
    func testFailedSaveLeavesUnavailableCourseRegistered() async throws {
        let fixture = try Fixture(name: "unregister-save-fail")
        defer { fixture.remove() }

        let external = fixture.root.appendingPathComponent("kept-course", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let marker = external.appendingPathComponent("must-survive.txt")
        let markerData = Data("KEEP".utf8)
        try markerData.write(to: marker)
        let courseID = UUID()
        try fixture.write(
            PersistedWorkspace(
                importedItems: [],
                courses: [
                    Course(
                        id: courseID,
                        title: "保存失败仍应留下",
                        sourceRootPath: "/Users/nobody/missing-course"
                    ),
                ],
                activeCourseID: courseID
            )
        )

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            workspaceSnapshotWriter: { _, _ in
                throw NSError(
                    domain: "WeiBei.UnavailableCourseUnregisterTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "forced save failure"]
                )
            },
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        XCTAssertThrowsError(
            try store.removeCourseFromWeiBeiForSelfCheck(courseID)
        )
        XCTAssertNotNil(store.course(withID: courseID))
        XCTAssertEqual(try Data(contentsOf: marker), markerData)
    }

    private struct Fixture {
        let root: URL
        let workspaceDirectory: URL

        init(name: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "weibei-unregister-\(name)-\(UUID().uuidString)",
                    isDirectory: true
                )
            workspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workspaceDirectory,
                withIntermediateDirectories: true
            )
        }

        func write(_ snapshot: PersistedWorkspace) throws {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(
                to: workspaceDirectory.appendingPathComponent("workspace.json"),
                options: [.atomic]
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
