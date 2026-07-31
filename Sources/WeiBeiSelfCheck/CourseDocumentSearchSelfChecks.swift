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
