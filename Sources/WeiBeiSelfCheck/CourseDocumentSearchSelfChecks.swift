import Foundation
import CoreGraphics
import CoreText
import PDFKit
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

    let progressiveBody = (0..<92).map { section in
        "# 第 \(section + 1) 节\n段落-\(section)-" + String(repeating: "课程正文", count: 30)
    }.joined(separator: "\n\n") + "\n\nFULL_ARTICLE_TAIL_TOKEN"
    let progressive = try makeSearchItem(
        "progressive",
        body: progressiveBody,
        root: root
    )
    var cursor: String?
    var pages: [String] = []
    var cursors = Set<String>()
    repeat {
        let page = index.read(
            item: progressive,
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
        try requireSearchCheck((page.text?.count ?? 0) <= 240, "读取擅自扩大了请求的字数")
        if let cursor { try requireSearchCheck(cursors.insert(cursor).inserted, "渐进读取游标重复") }
    } while cursor != nil
    try requireSearchCheck(
        pages.count > 1
            && pages.joined() == progressiveBody,
        "渐进读取无法续读到长文末尾"
    )
    var outlineOffset = 0
    var outline: [CourseDocumentPassage] = []
    repeat {
        let page = index.outlinePassages(item: progressive, offset: outlineOffset, limit: 17)
        outline += page.passages
        guard let next = page.nextCursor, let offset = Int(next) else { break }
        try requireSearchCheck(offset > outlineOffset, "目录游标没有前进")
        outlineOffset = offset
    } while true
    try requireSearchCheck(outline.count == 92, "目录无法翻到后半段")
    let lateSection = index.read(item: progressive, location: outline.last?.location, maximumCharacters: 240)
    try requireSearchCheck(lateSection.text?.contains("FULL_ARTICLE_TAIL_TOKEN") == true, "后半段目录位置不能读取")
    let exactSection = index.read(item: progressive, location: "markdown-heading-1", maximumCharacters: 240)
    try requireSearchCheck(exactSection.passages.count == 1 && exactSection.passages.first?.location == "markdown-heading-1", "章节 1 混入章节 10")
    try requireSearchCheck(index.searchPassages(item: progressive, query: "课程正文 不存在").passages.isEmpty, "搜索擅自拆词匹配")
    let markdownPage = CourseDocumentSearchIndex.readMarkdown(
        progressiveBody,
        location: nil,
        maximumCharacters: 240
    )
    let staleMarkdownPage = CourseDocumentSearchIndex.readMarkdown(
        progressiveBody + "\n新增内容",
        location: nil,
        cursor: markdownPage.nextCursor,
        maximumCharacters: 240
    )
    try requireSearchCheck(
        markdownPage.nextCursor != nil && staleMarkdownPage.availability == .unavailable,
        "正文变化后仍接受旧的渐进读取游标"
    )

    let coveragePDFURL = root.appendingPathComponent("coverage.pdf")
    try makeSearchRetryPDF(at: coveragePDFURL, pageCount: 2)
    let coveragePDF = StudyItem(
        id: "coverage-pdf", title: "coverage-pdf",
        subtitle: coveragePDFURL.lastPathComponent, kind: .pdf,
        urlPath: coveragePDFURL.path, isSample: false
    )
    let coverageIndex = CourseDocumentSearchIndex(
        databaseURL: root.appendingPathComponent("CourseIndex/coverage.sqlite3"),
        nativePDFTextLoader: { _, pageIndexes, _, _ in
            Dictionary(uniqueKeysWithValues: pageIndexes.map {
                ($0, BoundedPDFTextPage(
                    text: "第 \($0 + 1) 页完整正文 " + String(repeating: "有效", count: 20),
                    isPartial: false
                ))
            })
        }
    )
    coverageIndex.schedule([coveragePDF])
    let completeMiss = waitForSearchResult(until: Date().addingTimeInterval(8)) {
        coverageIndex.lookup(items: [coveragePDF], query: "绝不命中")[coveragePDF.id]
    } where: { $0.indexedPageCount == 2 }
    try requireSearchCheck(
        completeMiss?.text == nil && completeMiss?.totalPageCount == 2
            && completeMiss?.uncoveredPageIndexes.isEmpty == true
            && completeMiss?.failedPageIndexes.isEmpty == true,
        "完全覆盖 PDF 的零命中没有报告 100% 覆盖"
    )
    let currentRevision = completeMiss?.sourceRevision
    try makeSearchRetryPDF(at: coveragePDFURL, pageCount: 1)
    let changedResult = waitForSearchResult(until: Date().addingTimeInterval(8)) {
        coverageIndex.lookup(items: [coveragePDF], query: "绝不命中")[coveragePDF.id]
    } where: {
        $0.sourceRevision != nil && $0.sourceRevision != currentRevision && $0.totalPageCount == 1
    }
    try requireSearchCheck(
        changedResult?.failedPageIndexes.isEmpty == true,
        "PDF 文件变化后仍返回旧版本覆盖率或失败页"
    )

    let retryPDFURL = root.appendingPathComponent("retry.pdf")
    try makeSearchRetryPDF(at: retryPDFURL, pageCount: 1)
    let retryPDF = StudyItem(
        id: "retry-pdf", title: "retry-pdf",
        subtitle: retryPDFURL.lastPathComponent, kind: .pdf,
        urlPath: retryPDFURL.path, isSample: false
    )
    let retryProbe = SearchPDFManualRetryProbe()
    let retryIndex = CourseDocumentSearchIndex(
        databaseURL: root.appendingPathComponent("CourseIndex/retry.sqlite3"),
        nativePDFTextLoader: { _, pageIndexes, _, _ in
            retryProbe.nativeExtractions(for: pageIndexes)
        },
        pdfOCRPageLoader: { _, pageIndex in retryProbe.ocrOutcome(for: pageIndex) }
    )
    retryIndex.schedule([retryPDF])
    let failedResult = waitForSearchResult(until: Date().addingTimeInterval(8)) {
        retryIndex.lookup(items: [retryPDF], query: "绝不命中")[retryPDF.id]
    } where: { $0.failedPageIndexes == [0] }
    let failedContext = CourseKnowledgeIndex.build(
        title: "重试课程",
        sources: [CourseKnowledgeSource(
            id: retryPDF.id, title: retryPDF.title, subtitle: retryPDF.subtitle,
            kind: retryPDF.kind.rawValue, role: "material", text: "",
            isTruncated: true, indexedPageCount: failedResult?.indexedPageCount,
            totalPageCount: failedResult?.totalPageCount,
            uncoveredPageNumbers: failedResult?.uncoveredPageIndexes.map { $0 + 1 },
            failedPageNumbers: failedResult?.failedPageIndexes.map { $0 + 1 },
            failedPageReasons: failedResult.map {
                Dictionary(uniqueKeysWithValues: $0.failedPageReasons.map { ($0.key + 1, $0.value) })
            }
        )],
        links: [], query: "绝不命中", currentMaterialID: nil, currentNoteID: nil
    )
    try requireSearchCheck(
        failedResult?.indexedPageCount == 0 && failedResult?.totalPageCount == 1
            && failedResult?.uncoveredPageIndexes == [0]
            && failedResult?.failedPageReasons == [0: PDFOCRFailureReason.recognition.rawValue]
            && retryProbe.counts == (native: 1, ocr: 1)
            && failedContext.items.first?.failedPageReasons == [1: "文字识别失败，可重试"],
        "PDF 失败页、内部诊断或 Agent 人话原因不真实"
    )
    retryProbe.allowRecovery()
    try requireSearchCheck(retryIndex.retryFailedPDFPages(in: retryPDF), "当前失败页不能手动重试")
    let recovered = waitForSearchResult(until: Date().addingTimeInterval(8)) {
        retryIndex.lookup(items: [retryPDF], query: "手动重试恢复")[retryPDF.id]
    } where: { $0.indexedPageCount == 1 && $0.failedPageIndexes.isEmpty }
    try requireSearchCheck(
        recovered?.text?.contains("手动重试恢复") == true
            && retryProbe.counts == (native: 2, ocr: 1)
            && !retryIndex.retryFailedPDFPages(in: retryPDF),
        "手动重试没有只重新处理当前失败页，或后端未复核当前失败状态"
    )

    let courseID = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let profile = CourseKnowledgeProfile(
        courseID: courseID,
        revision: 2,
        entries: [
            CourseKnowledgeProfileEntry(
                kind: .concept,
                text: "用户自述：已掌握单利，复利还不熟。",
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
    struct LegacyProfileShape: Codable {
        var courseID: UUID
        var revision: UInt64
        var overview: String
        var entries: [LegacyEntryShape]
        var updatedAt: Date?
    }
    struct LegacyEntryShape: Codable {
        var id: UUID
        var kind: String
        var text: String
        var createdAt: Date
        var updatedAt: Date
    }
    let legacyProfileJSON = try JSONEncoder().encode(
        LegacyProfileShape(
            courseID: courseID,
            revision: 2,
            overview: "这门课讨论货币政策如何传导。",
            entries: [
                LegacyEntryShape(
                    id: UUID(),
                    kind: "overview",
                    text: "这门课讨论货币政策如何传导。",
                    createdAt: now,
                    updatedAt: now
                ),
            ],
            updatedAt: now
        )
    )
    let legacyDecoded = try JSONDecoder().decode(
        CourseKnowledgeProfile.self,
        from: legacyProfileJSON
    )
    try requireSearchCheck(
        legacyDecoded.entries.isEmpty && legacyDecoded.revision == 2,
        "旧档案里的材料认识条目解不出新的 kind 时应兜底回空档案"
    )

    // 兼容保证:写侧永远输出旧版本必填的 sources/overview 字段,否则旧版本 App
    // 会把新数据判成损坏并回退空备份;读侧则要能完整吃下 main 格式的历史数据。
    let compatibilityEncoded = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(profile)
    ) as? [String: Any] ?? [:]
    let compatibilityEntries = compatibilityEncoded["entries"] as? [[String: Any]] ?? []
    try requireSearchCheck(
        (compatibilityEncoded["overview"] as? String) != nil
            && compatibilityEntries.allSatisfy { ($0["sources"] as? [Any]) != nil },
        "档案编码必须带 overview 与 sources 兼容字段,防止旧版本把数据判损坏"
    )
    let mainShaped: [String: Any] = [
        "courseID": courseID.uuidString,
        "revision": 3,
        "overview": "旧版本写下的概览",
        "entries": [[
            "id": UUID().uuidString,
            "kind": "concept",
            "text": "用户自述：已理解货币政策传导",
            "sources": [[
                "itemID": "imported:material",
                "role": "material",
                "sourceRevision": "rev-1",
            ]],
            "createdAt": now.timeIntervalSince1970,
            "updatedAt": now.timeIntervalSince1970,
        ]],
        "updatedAt": NSNull(),
    ]
    let mainDecoded = try JSONDecoder().decode(
        CourseKnowledgeProfile.self,
        from: JSONSerialization.data(withJSONObject: mainShaped)
    )
    try requireSearchCheck(
        mainDecoded.overview == "旧版本写下的概览"
            && mainDecoded.entries.count == 1
            && mainDecoded.entries.first?.sources.first?.itemID == "imported:material",
        "main 格式的历史档案数据应被完整读入,兼容字段保留不丢"
    )
    try checkDirectSourceReading()
    try checkCourseDocumentSearchConnectionReuse()
}

// 保护原文不等完整索引、外部修改立即可读、同页 OCR 结果复用。
private func checkDirectSourceReading() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("weibei-direct-read-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let item = try makeSearchItem("fresh", body: "# 原文\n磁盘上的内容", root: root)
    let unavailableCache = root.appendingPathComponent("unavailable.sqlite3")
    try FileManager.default.createDirectory(at: unavailableCache, withIntermediateDirectories: true)
    let uncached = CourseDocumentSearchIndex(databaseURL: unavailableCache)
    let first = uncached.read(item: item, location: nil, maximumCharacters: 3)
    try requireSearchCheck(first.text == "# 原" && first.nextCursor != nil, "没有可用搜索缓存时不能直接读取原文")
    let changed = "# 修改后的原文\n外部编辑立即生效"
    try changed.write(to: root.appendingPathComponent("fresh.md"), atomically: true, encoding: .utf8)
    try requireSearchCheck(uncached.read(item: item, location: nil).text == changed, "原文读取仍返回修改前的缓存")
    try requireSearchCheck(uncached.read(item: item, location: nil, cursor: first.nextCursor).availability == .unavailable,
                           "外部修改后仍接受旧游标")
    try FileManager.default.removeItem(at: root.appendingPathComponent("fresh.md"))
    try requireSearchCheck(uncached.read(item: item, location: nil).availability == .unavailable, "删除后仍能读到旧原文")

    let pdfURL = root.appendingPathComponent("target.pdf")
    try makeSearchRetryPDF(at: pdfURL, pageCount: 6)
    let pdf = StudyItem(id: "direct-pdf", title: "direct-pdf", subtitle: "target.pdf", kind: .pdf,
                        urlPath: pdfURL.path, isSample: false)
    let probe = DirectPDFReadProbe()
    let index = CourseDocumentSearchIndex(databaseURL: root.appendingPathComponent("search.sqlite3"),
        verifiedFileDidOpen: { probe.recordSnapshot() },
        nativePDFTextLoader: { _, pages, _, _ in probe.native(pages) },
        pdfOCRPageLoader: { _, page in probe.ocr(page) })
    let native = index.read(item: pdf, page: 6, location: nil, maximumCharacters: 7)
    try requireSearchCheck(native.text?.count == 7 && native.passages.first?.pageIndex == 5
        && native.indexedPageCount == 1 && native.totalPageCount == 6
        && native.uncoveredPageIndexes == [0, 1, 2, 3, 4]
        && probe.nativePages == [5] && probe.ocrPages.isEmpty,
        "读取指定原生文字页却提取了其他页或进行了 OCR")
    let continuation = index.read(item: pdf, page: 6, location: nil, cursor: native.nextCursor)
    try requireSearchCheck((native.text ?? "") + (continuation.text ?? "") == DirectPDFReadProbe.nativeText
        && probe.nativePages == [5] && probe.snapshotCount == 1, "PDF 续读遗漏正文或重复复制、提取")
    let scanned = index.read(item: pdf, page: 4, location: nil)
    let repeated = index.read(item: pdf, page: 4, location: nil)
    try requireSearchCheck(scanned.text == DirectPDFReadProbe.ocrText && repeated.text == scanned.text
        && probe.nativePages == [5, 3] && probe.ocrPages == [3] && probe.snapshotCount == 2,
        "扫描页读取没有复用同页识别结果或重复复制整份文件")
    index.schedule([pdf])
    let searched = waitForSearchResult(until: Date().addingTimeInterval(8)) {
        index.searchPassages(item: pdf, query: DirectPDFReadProbe.ocrText)
    } where: { $0.availability == .ready }
    try requireSearchCheck(searched?.passages.contains(where: { $0.pageIndex == 3 }) == true
        && probe.ocrPages.filter({ $0 == 3 }).count == 1,
        "直接读取的识别结果未被后续搜索或后台索引复用")

    // 原生文字只有页码时，扫描正文仍须可读；后台索引不能抢先缓存残缺页。
    let mixedURL = root.appendingPathComponent("mixed.pdf")
    try makeNumberedScanPDF(at: mixedURL)
    let mixed = StudyItem(id: "mixed", title: "mixed", subtitle: "mixed.pdf", kind: .pdf,
                          urlPath: mixedURL.path, isSample: false)
    let nativeLoader: CourseNativePDFTextLoader = { url, pages, _, _ in
        guard let document = PDFDocument(url: url) else { return nil }
        return Dictionary(uniqueKeysWithValues: pages.map {
            ($0, BoundedPDFTextPage(text: document.page(at: $0)?.string ?? "", isPartial: false))
        })
    }
    let mixedIndex = CourseDocumentSearchIndex(databaseURL: root.appendingPathComponent("mixed.sqlite3"),
                                               nativePDFTextLoader: nativeLoader)
    let body = mixedIndex.read(item: mixed, page: 1, location: nil)
    try requireSearchCheck(body.text?.contains("SCANNED BODY") == true && body.text?.split(separator: "\n").contains("1") == true,
                           "带原生页码的扫描页漏掉图片正文或原生文字")
    let background = CourseDocumentSearchIndex(databaseURL: root.appendingPathComponent("mixed-background.sqlite3"),
                                               nativePDFTextLoader: nativeLoader)
    background.schedule([mixed])
    let backgroundBody = waitForSearchResult(until: Date().addingTimeInterval(8)) {
        background.searchPassages(item: mixed, query: "SCANNED BODY")
    } where: { !$0.passages.isEmpty }
    try requireSearchCheck(backgroundBody?.passages.first?.text.contains("SCANNED BODY") == true,
                           "后台索引把混合扫描页误当成完整原生页")
    let failedIndex = CourseDocumentSearchIndex(databaseURL: root.appendingPathComponent("mixed-failed.sqlite3"),
        nativePDFTextLoader: nativeLoader, pdfOCRPageLoader: { _, page in .failed(pageIndex: page, reason: .recognition) })
    let failed = failedIndex.read(item: mixed, page: 1, location: nil)
    try requireSearchCheck(failed.text?.contains("1") == true && failed.isTruncated && failed.failedPageIndexes == [0],
                           "图片识别失败时丢弃原生文字或谎报整页已完整读取")

}

private func makeNumberedScanPDF(at url: URL) throws {
    let bitmap = CGContext(data: nil, width: 600, height: 500, bitsPerComponent: 8, bytesPerRow: 600,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: 600, height: 500))
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 28, nil)
    ]
    bitmap.textPosition = CGPoint(x: 30, y: 350)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "SCANNED BODY 10: market perfection", attributes: attributes)), bitmap)
    func stream(_ header: String, _ data: Data) -> Data {
        Data("<< \(header) /Length \(data.count) >>\nstream\n".utf8) + data + Data("\nendstream".utf8)
    }
    // 图片置于未声明 Resources 的 Form，必须沿用页面资源；原生层只有页码。
    let objects = [
        Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
        Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
        Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 700] /Resources << /Font << /F1 4 0 R >> /XObject << /Im1 5 0 R /Fm1 6 0 R >> >> /Contents 7 0 R >>".utf8),
        Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".utf8),
        stream("/Type /XObject /Subtype /Image /Width 600 /Height 500 /ColorSpace /DeviceGray /BitsPerComponent 8",
               Data(bytes: bitmap.data!, count: 600 * 500)),
        stream("/Type /XObject /Subtype /Form /BBox [0 0 1 1]", Data("/Im1 Do".utf8)),
        stream("", Data("q 600 0 0 500 0 100 cm /Fm1 Do Q BT /F1 28 Tf 300 30 Td (1) Tj ET".utf8))
    ]
    var pdf = Data("%PDF-1.7\n".utf8)
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(pdf.count)
        pdf += Data("\(index + 1) 0 obj\n".utf8) + object + Data("\nendobj\n".utf8)
    }
    let xref = pdf.count
    pdf += Data("xref\n0 8\n0000000000 65535 f \n".utf8)
    for offset in offsets { pdf += Data(String(format: "%010d 00000 n \n", offset).utf8) }
    pdf += Data("trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8)
    try pdf.write(to: url)
}

private final class DirectPDFReadProbe: @unchecked Sendable {
    static let nativeText = "短页原生文字也应直接读取"
    static let ocrText = "扫描页面按需识别 " + String(repeating: "内容", count: 20)
    private let lock = NSLock()
    private var snapshots = 0
    var snapshotCount: Int { lock.lock(); defer { lock.unlock() }; return snapshots }
    func recordSnapshot() { lock.lock(); defer { lock.unlock() }; snapshots += 1 }
    private var nativeCalls: [Int] = []
    private var ocrCalls: [Int] = []
    var nativePages: [Int] { lock.lock(); defer { lock.unlock() }; return nativeCalls }
    var ocrPages: [Int] { lock.lock(); defer { lock.unlock() }; return ocrCalls }
    func native(_ pages: [Int]) -> [Int: BoundedPDFTextPage] {
        lock.lock(); defer { lock.unlock() }
        nativeCalls += pages
        return Dictionary(uniqueKeysWithValues: pages.filter { $0 != 3 }.map {
            ($0, BoundedPDFTextPage(text: Self.nativeText, isPartial: false))
        })
    }
    func ocr(_ page: Int) -> PDFOCRPageOutcome {
        lock.lock(); defer { lock.unlock() }
        ocrCalls.append(page)
        return .text(PDFOCRPage(pageIndex: page, lines: [PDFOCRLine(text: Self.ocrText, boundingBox: .zero)]))
    }
}

func checkCourseDocumentSearchConnectionReuse() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("weibei-search-connection-reuse-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("CourseIndex/search.sqlite3")
    let snapshotsDirectory = databaseURL.deletingLastPathComponent()
        .appendingPathComponent("ReadSnapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
    try Data("stale".utf8).write(to: snapshotsDirectory.appendingPathComponent("snapshot-old"))
    let snapshotsSentinel = databaseURL.deletingLastPathComponent()
        .appendingPathComponent("read-snapshots-sentinel")
    try Data("keep".utf8).write(to: snapshotsSentinel)
    let item = try makeSearchItem(
        "shared",
        body: "公开市场操作与政策利率",
        root: root
    )

    do {
        let first = CourseDocumentSearchIndex(databaseURL: databaseURL)
        try requireSearchCheck(
            !FileManager.default.fileExists(atPath: snapshotsDirectory.path)
                && FileManager.default.fileExists(atPath: snapshotsSentinel.path),
            "搜索索引初始化只应清理 ReadSnapshots，不应删除同级文件"
        )
        first.schedule([item])
        let firstHit = waitForSearchResult(until: Date().addingTimeInterval(8)) {
            first.lookup(items: [item], query: "公开市场操作")[item.id]
        } where: {
            $0.availability == .ready && $0.text?.contains("公开市场操作") == true
        }
        try requireSearchCheck(firstHit != nil, "第一个搜索器没有编进刚加入的资料")

        let second = CourseDocumentSearchIndex(databaseURL: databaseURL)
        let secondHit = second.lookup(items: [item], query: "公开市场操作")[item.id]
        try requireSearchCheck(
            secondHit?.availability == .ready
                && secondHit?.text?.contains("公开市场操作") == true,
            "同一课程库上另一个搜索器读不到已编进的资料"
        )

        let group = DispatchGroup()
        let firstBox = LockedSearchResult()
        let secondBox = LockedSearchResult()
        group.enter()
        DispatchQueue.global().async {
            firstBox.value = first.lookup(items: [item], query: "政策利率")[item.id]
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            secondBox.value = second.lookup(items: [item], query: "政策利率")[item.id]
            group.leave()
        }
        try requireSearchCheck(
            group.wait(timeout: .now() + 8) == .success,
            "两个搜索器同时查询没有在时限内返回"
        )
        try requireSearchCheck(
            firstBox.value?.text?.contains("政策利率") == true
                && secondBox.value?.text?.contains("政策利率") == true,
            "两个搜索器同时查询没有都找到资料"
        )
    }

    let reopened = CourseDocumentSearchIndex(databaseURL: databaseURL)
    let reopenedHit = reopened.lookup(items: [item], query: "公开市场操作")[item.id]
    try requireSearchCheck(
        reopenedHit?.availability == .ready
            && reopenedHit?.text?.contains("公开市场操作") == true,
        "关掉搜索器后再打开，课程库里已编过的资料找不到了"
    )
}

private final class LockedSearchResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CourseDocumentIndexResult?

    var value: CourseDocumentIndexResult? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}

private func makeSearchRetryPDF(at url: URL, pageCount: Int) throws {
    guard let consumer = CGDataConsumer(url: url as CFURL) else {
        throw NSError(domain: "WeiBeiSearchCheck", code: 1)
    }
    var mediaBox = CGRect(x: 0, y: 0, width: 320, height: 480)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw NSError(domain: "WeiBeiSearchCheck", code: 2)
    }
    for _ in 0..<pageCount {
        context.beginPDFPage(nil)
        context.endPDFPage()
    }
    context.closePDF()
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

private func waitForSearchResult(
    until deadline: Date,
    lookup: () -> CourseDocumentIndexResult?,
    where matches: (CourseDocumentIndexResult) -> Bool
) -> CourseDocumentIndexResult? {
    repeat {
        if let result = lookup(), matches(result) { return result }
        Thread.sleep(forTimeInterval: 0.02)
    } while Date() < deadline
    return lookup()
}

private final class SearchPDFManualRetryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recovers = false
    private var nativeCount = 0
    private var ocrCount = 0

    func nativeExtractions(for pageIndexes: [Int]) -> [Int: BoundedPDFTextPage] {
        lock.lock()
        nativeCount += 1
        let shouldRecover = recovers
        lock.unlock()
        guard shouldRecover else { return [:] }
        return Dictionary(uniqueKeysWithValues: pageIndexes.map { pageIndex in
            return (
                pageIndex,
                BoundedPDFTextPage(
                    text: "手动重试恢复 " + String(repeating: "有效", count: 20),
                    isPartial: false
                )
            )
        })
    }

    func ocrOutcome(for pageIndex: Int) -> PDFOCRPageOutcome {
        lock.lock()
        ocrCount += 1
        lock.unlock()
        return .failed(pageIndex: pageIndex, reason: .recognition)
    }

    func allowRecovery() {
        lock.lock()
        recovers = true
        lock.unlock()
    }

    var counts: (native: Int, ocr: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (nativeCount, ocrCount)
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
