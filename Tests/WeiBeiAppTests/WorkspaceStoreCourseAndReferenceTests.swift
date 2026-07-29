import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class WorkspaceStoreCourseAndReferenceTests: WorkspaceStoreTestCase {
    /**
     * 验证课程成员关系过滤无效 ID，并在删除课程时清理关系。
     */
    @MainActor
    func testCourseMembershipUsesOnlyExistingCoursesAndItems() throws {
        let directory = try makeTemporaryWorkspace()
        let materialURL = try writeFile(named: "lesson.txt", contents: "Lesson", in: directory)
        let store = makeStore(in: directory)
        let material = try XCTUnwrap(store.importFiles([materialURL]).first)
        let firstCourseID = try XCTUnwrap(store.createCourse(title: " Course A "))
        let secondCourseID = try XCTUnwrap(store.createCourse(title: "Course B"))

        store.setCourseIDs([firstCourseID, secondCourseID, UUID()], for: material.id)
        XCTAssertEqual(Set(store.courseIDs(for: material.id)), Set([firstCourseID, secondCourseID]))
        store.setCourseIDs([firstCourseID], for: "missing-item")
        XCTAssertTrue(store.courseIDs(for: "missing-item").isEmpty)

        store.deleteCourse(firstCourseID)
        XCTAssertEqual(store.courseIDs(for: material.id), [secondCourseID])
    }

    /**
     * 验证笔记资料关系只接受真实的笔记和资料，并支持双向查询。
     */
    @MainActor
    func testNoteSourceRelationshipsAreValidatedAndQueryableBothWays() throws {
        let directory = try makeTemporaryWorkspace()
        let materialURL = try writeFile(named: "source.txt", contents: "Source", in: directory)
        let noteURL = try writeFile(named: "note.md", contents: "# Note\n", in: directory)
        let store = makeStore(in: directory)
        let material = try XCTUnwrap(store.importFiles([materialURL]).first)
        _ = store.importFiles([noteURL], markdownAsNotes: true)
        let note = try XCTUnwrap(store.importedItems.first { $0.urlPath == noteURL.path })

        store.setLinkedSourceIDs([material.id, "missing"], for: note.id)
        XCTAssertEqual(store.linkedSourceIDs(for: note.id), [material.id])
        XCTAssertEqual(store.linkedNoteIDs(for: material.id), [note.id])

        store.setLinkedSourceIDs([material.id], for: material.id)
        XCTAssertTrue(store.linkedSourceIDs(for: material.id).isEmpty)
    }

    /**
     * 验证课程空间路由只接受有效对象，并在打开材料时恢复阅读表面。
     */
    @MainActor
    func testCourseWorkspaceRoutingRejectsInvalidTargetsAndOpensMaterial() throws {
        let directory = try makeTemporaryWorkspace()
        let materialURL = try writeFile(named: "route.txt", contents: "Route", in: directory)
        let store = makeStore(in: directory)
        let material = try XCTUnwrap(store.importFiles([materialURL]).first)
        let courseID = try XCTUnwrap(store.createCourse(title: "Routing"))
        store.assignItemIDs([material.id], to: courseID)

        store.openCourseSpace(UUID())
        XCTAssertFalse(store.courseWorkspacePresented)
        store.openCourseSpace(courseID)
        XCTAssertTrue(store.courseWorkspacePresented)
        XCTAssertEqual(store.activeCourseID, courseID)

        store.setLayout(.immersiveWriting)
        store.openCourseMaterial(material.id)
        XCTAssertFalse(store.courseWorkspacePresented)
        XCTAssertEqual(store.selectedItemID, material.id)
        XCTAssertEqual(store.layout, .immersiveReading)
        XCTAssertEqual(store.focusedPane, .reader)
    }

    /**
     * 验证结构化来源引用会打开真实材料并保留 HTML 章节跳转坐标。
     */
    @MainActor
    func testSourceReferenceOpensMaterialAndRequestsSection() throws {
        let directory = try makeTemporaryWorkspace()
        let materialURL = try writeFile(
            named: "rates.html",
            contents: "<h1 id=\"rates\">Rates</h1>",
            in: directory
        )
        let store = makeStore(in: directory)
        let material = try XCTUnwrap(store.importFiles([materialURL]).first)
        store.setLayout(.immersiveConversation)

        XCTAssertTrue(
            store.openSourceReference(
                "Source: \(material.title), section id: html-heading-3, section: Real rates"
            )
        )

        XCTAssertEqual(store.selectedItemID, material.id)
        XCTAssertEqual(store.layout, .immersiveReading)
        XCTAssertEqual(store.readerTargetLocationID, "html-heading-3")
        XCTAssertEqual(store.readerTargetLocationTitle, "Real rates")
        XCTAssertEqual(store.focusedPane, .reader)
    }
}
