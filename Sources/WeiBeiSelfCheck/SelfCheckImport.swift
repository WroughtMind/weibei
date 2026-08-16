import Foundation
import WeiBeiCore

func checkImportIdentityScenes() throws {
    let ownerCourseID = UUID()
    let ownedItem = StudyItem(
        id: "imported:owned",
        title: "课程文稿",
        subtitle: "课程文稿.pdf",
        kind: .pdf,
        urlPath: "/tmp/课程/文稿/课程文稿.pdf",
        isSample: false,
        storage: .courseOwned(
            ownerCourseID: ownerCourseID,
            relativePath: "文稿/课程文稿.pdf"
        ),
        contentRevision: 7,
        contentDigest: "sha256:owned"
    )
    let commonItem = StudyItem(
        id: "imported:common",
        title: "讲义",
        subtitle: "讲义.pdf",
        kind: .pdf,
        urlPath: "/tmp/通用资料/讲义.pdf",
        isSample: false,
        storage: .common(relativePath: "通用资料/讲义.pdf"),
        contentRevision: 3,
        contentDigest: "sha256:common"
    )
    let sample = StudyItem(
        id: "sample",
        title: "样例",
        subtitle: "样例",
        kind: .html,
        urlPath: nil,
        isSample: true
    )
    expect(sample.storage == .bundledSample, "samples stay bundledSample")

    for item in [ownedItem, commonItem, sample] {
        let data = try JSONEncoder().encode(item)
        let text = String(data: data, encoding: .utf8) ?? ""
        expect(
            !text.contains("urlPath")
                && !text.contains("importedFileLastKnownPath")
                && !text.contains("importedFileBookmarkData")
                && !text.contains("legacyExternal")
                && !text.contains("sharedRelativePath"),
            "persisted items omit the old external-file address model"
        )
        let decoded = try JSONDecoder().decode(StudyItem.self, from: data)
        expect(
            decoded.storage == item.storage
                && decoded.contentRevision == item.contentRevision
                && decoded.contentDigest == item.contentDigest
                && decoded.urlPath == nil
                && decoded.importedFileIdentity == nil,
            "storage and content fields round-trip; addresses stay runtime-only"
        )
    }

    let workspace = PersistedWorkspace(
        importedItems: [ownedItem, commonItem],
        notesByItemID: [:],
        courses: [
            Course(id: ownerCourseID, title: "课程", sourceRootRelativePath: "课程")
        ]
    )
    let workspaceText = String(data: try JSONEncoder().encode(workspace), encoding: .utf8) ?? ""
    expect(
        !workspaceText.contains("courseItemMemberships")
            || workspaceText.contains("\"courseItemMemberships\":null"),
        "new workspace does not persist the multi-course mount table"
    )

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("weibei-selfcheck-import-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let attachments = root.appendingPathComponent("attachments", isDirectory: true)
    var rejectedOversizedImage = false
    do {
        _ = try MarkdownAttachmentStore.save(
            data: Data(count: MarkdownAttachmentStore.maximumImageByteCount + 1),
            originalName: "large.png",
            mime: "image/png",
            attachmentDirectory: attachments,
            markdownBaseURLString: root.absoluteString
        )
    } catch {
        rejectedOversizedImage = true
    }
    expect(rejectedOversizedImage, "oversized attachment data is rejected")
    expect(
        !FileManager.default.fileExists(atPath: attachments.path),
        "oversized attachment rejection writes no files"
    )
}
