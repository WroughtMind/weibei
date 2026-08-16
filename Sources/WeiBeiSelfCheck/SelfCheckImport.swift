import Foundation
import WeiBeiCore

/// Local no-Xcode mirrors for import-identity and membership scenes from
/// `ImportedIdentitySelfCheck.storageModelsDecodeLegacySnapshotsAndRoundTrip`
/// plus `MarkdownAttachmentStore` size rejection.
func checkImportIdentityScenes() throws {
    let legacyExternal = try JSONDecoder().decode(
        StudyItem.self,
        from: Data(
            """
            {
              "id":"file:/tmp/legacy.txt",
              "title":"旧资料",
              "subtitle":"legacy.txt",
              "kind":"text",
              "urlPath":"/tmp/legacy.txt",
              "isSample":false,
              "isNotebookNote":false
            }
            """.utf8
        )
    )
    expect(
        legacyExternal.storage == .legacyExternal
            && legacyExternal.contentRevision == 1
            && legacyExternal.contentDigest == nil,
        "legacy external materials migrate to legacyExternal without inventing a digest"
    )

    let legacySample = try JSONDecoder().decode(
        StudyItem.self,
        from: Data(
            """
            {
              "id":"sample",
              "title":"内置样例",
              "subtitle":"样例",
              "kind":"html",
              "urlPath":null,
              "isSample":true
            }
            """.utf8
        )
    )
    expect(
        legacySample.storage == .bundledSample,
        "legacy bundled samples stay bundledSample"
    )

    let ownerCourseID = UUID()
    let identity = ImportedFileIdentity(
        volumeID: 12,
        fileID: 34,
        birthTimeSeconds: 56,
        birthTimeNanoseconds: 78
    )
    let ownedItem = StudyItem(
        id: "imported:owned",
        title: "课程文稿",
        subtitle: "课程文稿.pdf",
        kind: .pdf,
        urlPath: "/tmp/课程/文稿/课程文稿.pdf",
        importedFileIdentity: identity,
        importedFileLastKnownPath: "/tmp/课程/文稿/课程文稿.pdf",
        isSample: false,
        storage: .courseOwned(ownerCourseID: ownerCourseID),
        contentRevision: 7,
        contentDigest: "sha256:owned"
    )
    let sharedItem = StudyItem(
        id: "imported:shared",
        title: "共享文稿",
        subtitle: "共享文稿.pdf",
        kind: .pdf,
        urlPath: "/tmp/共享文稿/共享文稿.pdf",
        isSample: false,
        storage: .shared(sharedRelativePath: "共享文稿/共享文稿.pdf"),
        contentRevision: 3,
        contentDigest: "sha256:shared"
    )
    for item in [ownedItem, sharedItem, legacyExternal, legacySample] {
        let decoded = try JSONDecoder().decode(
            StudyItem.self,
            from: JSONEncoder().encode(item)
        )
        expect(decoded == item, "item storage, identity, revision, and digest round-trip")
    }
    expect(
        ownedItem.importedFileIdentity == identity,
        "imported file identity stays attached to the same item"
    )

    struct LegacyMembership: Encodable {
        var id: UUID
        var courseID: UUID
        var itemID: String
        var createdAt: Date
    }
    let legacyMembership = LegacyMembership(
        id: UUID(),
        courseID: ownerCourseID,
        itemID: ownedItem.id,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let decodedLegacyMembership = try JSONDecoder().decode(
        CourseItemMembership.self,
        from: JSONEncoder().encode(legacyMembership)
    )
    expect(
        decodedLegacyMembership.courseRelativePath == nil
            && decodedLegacyMembership.entryIdentity == nil
            && decodedLegacyMembership.documentIdentifier == nil,
        "legacy course memberships do not invent path or identity fields"
    )

    let membership = CourseItemMembership(
        courseID: ownerCourseID,
        itemID: sharedItem.id,
        courseRelativePath: "文稿/共享文稿.pdf",
        entryIdentity: identity,
        documentIdentifier: 9_001,
        createdAt: Date(timeIntervalSince1970: 1_700_000_200)
    )
    let decodedMembership = try JSONDecoder().decode(
        CourseItemMembership.self,
        from: JSONEncoder().encode(membership)
    )
    expect(
        decodedMembership == membership
            && decodedMembership.entryIdentity == identity,
        "course entry path and identity round-trip"
    )

    let oldestMembershipID = UUID()
    let partialMemberships = CourseItemMemberships(values: [
        CourseItemMembership(
            id: oldestMembershipID,
            courseID: ownerCourseID,
            itemID: sharedItem.id,
            courseRelativePath: "文稿/共享文稿.pdf",
            createdAt: Date(timeIntervalSince1970: 1)
        ),
        CourseItemMembership(
            courseID: ownerCourseID,
            itemID: sharedItem.id,
            entryIdentity: identity,
            documentIdentifier: 9_001,
            createdAt: Date(timeIntervalSince1970: 2)
        ),
    ])
    expect(
        partialMemberships.values.count == 1
            && partialMemberships.values.first?.id == oldestMembershipID
            && partialMemberships.values.first?.courseRelativePath == "文稿/共享文稿.pdf"
            && partialMemberships.values.first?.entryIdentity == identity
            && partialMemberships.values.first?.documentIdentifier == 9_001,
        "complementary membership metadata merges onto the oldest relationship"
    )

    let conflictingMemberships = CourseItemMemberships(values: [
        membership,
        CourseItemMembership(
            courseID: ownerCourseID,
            itemID: sharedItem.id,
            courseRelativePath: "文稿/另一个入口.pdf",
            entryIdentity: identity,
            documentIdentifier: 9_001
        ),
    ])
    expect(
        conflictingMemberships.values.count == 2,
        "conflicting membership metadata is kept, not silently dropped"
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
