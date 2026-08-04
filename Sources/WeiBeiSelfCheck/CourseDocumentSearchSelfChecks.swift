import Foundation
import WeiBeiCore

func checkCourseDocumentSearchReadiness() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("weibei-search-readiness-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let blocker = try makeSearchItem("blocker", body: "后台队列占用", root: root)
    let fillers = try (0..<24).map {
        try makeSearchItem("filler-\($0)", body: "第 \($0) 份资料", root: root)
    }
    let target = try makeSearchItem(
        "target",
        body: "公开市场操作与政策利率",
        root: root
    )
    let gate = CourseSearchIndexGate()
    let index = CourseDocumentSearchIndex(
        databaseURL: root.appendingPathComponent("CourseIndex/search.sqlite3"),
        verifiedFileDidOpen: { gate.fileDidOpen() }
    )

    index.schedule([blocker])
    try requireSearchCheck(
        gate.backgroundEntered.wait(timeout: .now() + 2) == .success,
        "后台索引没有启动"
    )
    defer { gate.releaseBackground.signal() }

    let resultLock = NSLock()
    var targetResult: CourseDocumentIndexResult?
    DispatchQueue.global().async {
        let result = index.lookup(
            items: fillers + [target],
            query: "公开市场操作"
        )[target.id]
        resultLock.lock()
        targetResult = result
        resultLock.unlock()
        gate.lookupReturned.signal()
    }

    try requireSearchCheck(
        gate.foregroundLimitReached.wait(timeout: .now() + 5) == .success,
        "前台索引没有到达数量预算"
    )
    try requireSearchCheck(
        gate.lookupReturned.wait(timeout: .now() + 2) == .timedOut,
        "首次搜索在目标资料仍排队时提前返回"
    )
    gate.releaseBackground.signal()
    try requireSearchCheck(
        gate.lookupReturned.wait(timeout: .now() + 5) == .success,
        "目标资料完成索引后搜索仍未返回"
    )

    resultLock.lock()
    let result = targetResult
    resultLock.unlock()
    try requireSearchCheck(
        result?.availability == .ready
            && result?.text?.contains("公开市场操作") == true,
        "首次搜索没有等待并找到排队中的目标资料"
    )

    let missingURL = root.appendingPathComponent("missing.md")
    let missing = StudyItem(
        id: "missing",
        title: "missing",
        subtitle: missingURL.lastPathComponent,
        kind: .markdown,
        urlPath: missingURL.path,
        isSample: false
    )
    try requireSearchCheck(
        index.lookup(items: [missing], query: "不存在")[missing.id]?.availability
            == .unavailable,
        "无法读取的资料被伪装成普通空结果"
    )

    let progressiveBody = (0..<18).map { section in
        "# 第 \(section + 1) 节\n段落-\(section)-" + String(repeating: "课程正文", count: 30)
    }.joined(separator: "\n\n") + "\n\nFULL_ARTICLE_TAIL_TOKEN"
    let progressive = try makeSearchItem(
        "progressive",
        body: progressiveBody,
        root: root
    )
    var cursor: String?
    var pages: [String] = []
    repeat {
        let page = index.read(
            item: progressive,
            query: "",
            location: nil,
            cursor: cursor,
            maximumCharacters: 240
        )
        try requireSearchCheck(
            page.availability == .ready && page.text?.isEmpty == false,
            "渐进读取没有返回可用正文"
        )
        pages.append(page.text ?? "")
        cursor = page.nextCursor
        try requireSearchCheck(pages.count < 100, "渐进读取游标没有收敛")
    } while cursor != nil
    try requireSearchCheck(
        pages.count > 1
            && pages.joined(separator: "").contains("FULL_ARTICLE_TAIL_TOKEN"),
        "渐进读取无法续读到长文末尾"
    )
    let markdownPage = CourseDocumentSearchIndex.readMarkdown(
        progressiveBody,
        query: "",
        location: nil,
        maximumCharacters: 240
    )
    let staleMarkdownPage = CourseDocumentSearchIndex.readMarkdown(
        progressiveBody + "\n新增内容",
        query: "",
        location: nil,
        cursor: markdownPage.nextCursor,
        maximumCharacters: 240
    )
    try requireSearchCheck(
        markdownPage.nextCursor != nil && staleMarkdownPage.availability == .unavailable,
        "正文变化后仍接受旧的渐进读取游标"
    )

    let courseID = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let profile = CourseKnowledgeProfile(
        courseID: courseID,
        revision: 2,
        overview: "这门课讨论货币政策如何传导。",
        entries: [
            CourseKnowledgeProfileEntry(
                kind: .concept,
                text: "政策利率通过资金价格影响总需求。",
                sources: [
                    CourseKnowledgeProfileSource(
                        itemID: "material-1",
                        role: .material,
                        location: "利率渠道",
                        sourceRevision: "revision-1"
                    ),
                ],
                createdAt: now,
                updatedAt: now
            ),
        ],
        updatedAt: now
    )
    let portable = try CoursePortableState(
        courseID: courseID,
        revision: 3,
        savedAt: now,
        metadata: CoursePortableMetadata(
            title: "货币金融学",
            colorIndex: 0,
            createdAt: now,
            updatedAt: now
        ),
        items: [
            CoursePortableItem(
                itemID: "material-1",
                title: "政策传导",
                kind: .markdown,
                isNotebookNote: false,
                courseRelativePath: "materials/policy.md",
                storage: .courseOwned,
                contentRevision: 1,
                contentDigest: nil,
                membershipCreatedAt: now
            ),
        ],
        studySessions: [],
        learningMemoryState: nil,
        courseKnowledgeProfile: profile,
        noteSourceLinks: [],
        studyLocationsByItemID: [:],
        resumePoint: nil,
        pendingNoteDrafts: []
    ).validated(expectedCourseID: courseID)
    let roundTripped = try JSONDecoder().decode(
        CoursePortableState.self,
        from: JSONEncoder().encode(portable)
    )
    try requireSearchCheck(
        roundTripped.courseKnowledgeProfile == profile,
        "课程知识档案没有随课程状态完整往返"
    )
    let sourceRemoved = profile.retainingAvailableSources(
        materialItemIDs: [],
        noteItemIDs: []
    )
    try requireSearchCheck(
        sourceRemoved.entries.isEmpty
            && sourceRemoved.overview.isEmpty
            && sourceRemoved.revision == profile.revision + 1,
        "课程来源移除后仍保留了失效的知识档案条目"
    )
}

private func makeSearchItem(
    _ id: String,
    body: String,
    root: URL
) throws -> StudyItem {
    let url = root.appendingPathComponent("\(id).md")
    try body.write(to: url, atomically: true, encoding: .utf8)
    return StudyItem(
        id: id,
        title: id,
        subtitle: url.lastPathComponent,
        kind: .markdown,
        urlPath: url.path,
        isSample: false
    )
}

private func requireSearchCheck(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else {
        throw CourseDocumentSearchSelfCheckError.failed(message)
    }
}

private final class CourseSearchIndexGate: @unchecked Sendable {
    let backgroundEntered = DispatchSemaphore(value: 0)
    let foregroundLimitReached = DispatchSemaphore(value: 0)
    let releaseBackground = DispatchSemaphore(value: 0)
    let lookupReturned = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var openCount = 0

    func fileDidOpen() {
        lock.lock()
        openCount += 1
        let currentOpen = openCount
        lock.unlock()

        if currentOpen == 1 {
            backgroundEntered.signal()
            releaseBackground.wait()
        } else if currentOpen == 25 {
            foregroundLimitReached.signal()
        }
    }
}

private enum CourseDocumentSearchSelfCheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return "课程搜索就绪自检失败：\(message)"
        }
    }
}
