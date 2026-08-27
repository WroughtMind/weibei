import XCTest
@testable import WeiBeiCore

final class MarkdownAttachmentGCTests: XCTestCase {
    private let gracePeriod: TimeInterval = 24 * 60 * 60

    /// 正文仍引用的图片不删，包括实际写入的转义路径。
    func testReferencedAttachmentIsNotCollected() {
        let now = Date()
        let attachment = MarkdownAttachment(src: ".weibei-assets/图 1).png", alt: "图 1)")
        let markdown = """
        前文

        \(MarkdownAttachmentStore.markdownImage(for: attachment))

        后文
        """
        let file = MarkdownAttachmentFile(
            url: URL(fileURLWithPath: "/tmp/.weibei-assets/图 1).png"),
            relativePath: ".weibei-assets/图 1).png",
            timestamp: now.addingTimeInterval(-48 * 60 * 60)
        )
        let doomed = MarkdownAttachmentGC.urlsEligibleForDeletion(
            files: [file],
            referencedRelativePaths: MarkdownAttachmentGC.referencedRelativePaths(
                inMarkdownBodies: [markdown]
            ),
            now: now,
            gracePeriod: gracePeriod
        )
        XCTAssertTrue(doomed.isEmpty)
    }

    /// 全库无引用且超过宽限期的附件才可删。
    func testUnreferencedAttachmentPastGracePeriodIsCollected() {
        let now = Date()
        let orphan = MarkdownAttachmentFile(
            url: URL(fileURLWithPath: "/tmp/.weibei-assets/orphan.png"),
            relativePath: ".weibei-assets/orphan.png",
            timestamp: now.addingTimeInterval(-48 * 60 * 60)
        )
        let kept = MarkdownAttachmentFile(
            url: URL(fileURLWithPath: "/tmp/.weibei-assets/kept.png"),
            relativePath: ".weibei-assets/kept.png",
            timestamp: now.addingTimeInterval(-48 * 60 * 60)
        )
        let markdown = MarkdownAttachmentStore.markdownImage(
            for: MarkdownAttachment(src: ".weibei-assets/kept.png", alt: "kept")
        )
        let doomed = MarkdownAttachmentGC.urlsEligibleForDeletion(
            files: [orphan, kept],
            referencedRelativePaths: MarkdownAttachmentGC.referencedRelativePaths(
                inMarkdownBodies: [markdown]
            ),
            now: now,
            gracePeriod: gracePeriod
        )
        XCTAssertEqual(doomed, [orphan.url])
    }

    /// 无引用但未过宽限期的新图不删，避免编辑中途回收。
    func testUnreferencedAttachmentWithinGracePeriodIsKept() {
        let now = Date()
        let file = MarkdownAttachmentFile(
            url: URL(fileURLWithPath: "/tmp/Attachments/fresh.png"),
            relativePath: "Attachments/fresh.png",
            timestamp: now.addingTimeInterval(-60 * 60)
        )
        let doomed = MarkdownAttachmentGC.urlsEligibleForDeletion(
            files: [file],
            referencedRelativePaths: [],
            now: now,
            gracePeriod: gracePeriod
        )
        XCTAssertTrue(doomed.isEmpty)
    }
}
