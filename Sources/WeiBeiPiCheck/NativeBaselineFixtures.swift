import Foundation
import WeiBeiCore

/// Records Pi-backend traces for the 12 Native on-parity scenarios.
/// Invoked as `WeiBeiPiCheck --native-baseline`. Never writes secrets.
enum NativeBaselineFixtures {
    struct Scenario: Sendable {
        var id: String
        var question: String
        var cancelAfterNanoseconds: UInt64?
        var forceUnauthorized: Bool
        var includeVisualAsset: Bool
        var reuseSession: Bool
    }

    static func runIfRequested(arguments: [String], environment: [String: String]) async -> Bool {
        guard arguments.contains("--native-baseline") else { return false }
        do {
            try await run(environment: environment)
        } catch {
            fputs("native-baseline failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        return true
    }

    static func run(environment: [String: String]) async throws {
        let executable = try locatePi(environment: environment)
        let outputRoot = outputDirectory(environment: environment)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let authSource = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.changfenhuang.weibei/PiAgent/auth.json")
        guard FileManager.default.fileExists(atPath: authSource.path) else {
            throw NSError(
                domain: "WeiBei.NativeBaseline",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "missing Pi auth.json for DeepSeek live fixtures"]
            )
        }

        var records: [[String: Any]] = []
        let sessionID = UUID()
        let visualURL = try writeTinyPNG()

        let scenarios: [Scenario] = [
            Scenario(id: "01-plain-qa", question: "2+2 等于几？只回答一个数字。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "02-course-search", question: "利率这一节讲了什么？先搜索课程再回答，并标明来源。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "03-course-read", question: "请读取「利率课程」正文，引用原文解释为什么利率可称为资金价格，并给出可跳转来源。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "04-learning-memory", question: "读取学习记忆，告诉我上次学到哪里、还有什么困惑。记忆不是课程证据。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "05-course-profile", question: "我们刚学完利率定义这一节。请把本轮真实读到的认识整理进课程知识档案。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "06-note-relation", question: "请把当前选区整理成一个带来源的 Markdown 核心要点，提交待确认的笔记建议；如果笔记与材料尚未关联，也提出关系建议。不要直接写入。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "07-visualize", question: "用一个互动界面演示名义利率减去通货膨胀得到实际利率。只提交一次 visualize。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "08-visual-asset", question: "观察当前材料图像，只根据可见像素描述图里有没有文字。不要编造精确测量。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: true, reuseSession: false),
            Scenario(id: "09-cancel", question: "请详细解释名义利率、实际利率与通货膨胀的关系，分步骤慢慢讲。", cancelAfterNanoseconds: 800_000_000, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "10-unauthorized", question: "随便打个招呼。", cancelAfterNanoseconds: nil, forceUnauthorized: true, includeVisualAsset: false, reuseSession: false),
            Scenario(id: "11-resume-a", question: "请记住：本轮课程关键词是「资金价格」。先搜索再简短确认。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: true),
            Scenario(id: "12-resume-b", question: "我刚才让你记住的课程关键词是什么？不要重新搜索。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: true),
            Scenario(id: "13-multi-tool", question: "请同时搜索「通货膨胀」并读取通货膨胀补充材料，比较它和利率的关系，列出用到的工具。", cancelAfterNanoseconds: nil, forceUnauthorized: false, includeVisualAsset: false, reuseSession: false),
        ]

        var resumePrepared: PreparedRuntime?

        for scenario in scenarios {
            print("native-baseline running \(scenario.id)")
            fflush(stdout)
            let record: [String: Any]
            if scenario.reuseSession {
                if resumePrepared == nil {
                    resumePrepared = try await prepareRuntime(
                        executable: executable,
                        authSource: authSource,
                        forceUnauthorized: false
                    )
                }
                record = try await runScenario(
                    scenario,
                    prepared: resumePrepared!,
                    sessionID: sessionID,
                    visualURL: visualURL
                )
            } else {
                let prepared = try await prepareRuntime(
                    executable: executable,
                    authSource: authSource,
                    forceUnauthorized: scenario.forceUnauthorized
                )
                record = try await runScenario(
                    scenario,
                    prepared: prepared,
                    sessionID: UUID(),
                    visualURL: visualURL
                )
                await prepared.runtime.shutdown()
                try? FileManager.default.removeItem(at: prepared.root)
            }
            records.append(record)
            let scenarioURL = outputRoot.appendingPathComponent("\(scenario.id).json")
            try writeJSON(record, to: scenarioURL)
        }

        await resumePrepared?.runtime.shutdown()
        if let resumePrepared {
            try? FileManager.default.removeItem(at: resumePrepared.root)
        }

        let index: [String: Any] = [
            "recordedAt": ISO8601DateFormatter().string(from: Date()),
            "originMain": "c7018f0",
            "piVersion": "0.82.1",
            "provider": "deepseek",
            "model": environment["WEIBEI_NATIVE_BASELINE_MODEL"] ?? "deepseek-chat",
            "scenarioCount": records.count,
            "scenarios": records.map { $0["id"] as? String ?? "" },
        ]
        try writeJSON(index, to: outputRoot.appendingPathComponent("index.json"))
        print("native-baseline wrote \(records.count) scenarios to \(outputRoot.path)")
    }

    private static func locatePi(environment: [String: String]) throws -> URL {
        let explicit = environment["WEIBEI_PI_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty {
            return URL(fileURLWithPath: explicit)
        }
        let cached = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/pi-runtime/0.82.1/darwin-arm64/PiRuntime/bin/pi")
        if FileManager.default.isExecutableFile(atPath: cached.path) {
            return cached
        }
        guard let located = PiExecutableLocator.locate() else {
            throw NSError(
                domain: "WeiBei.NativeBaseline",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "embedded PI runtime not found"]
            )
        }
        return located
    }

    private static func outputDirectory(environment: [String: String]) -> URL {
        if let raw = environment["WEIBEI_NATIVE_BASELINE_OUT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return URL(fileURLWithPath: raw)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Docs/audit/2026-08-22-native-agent-runtime-Pi行为夹具")
    }

    private struct PreparedRuntime {
        var runtime: PiAgentRuntime
        var root: URL
        var runtimeDirectory: URL
    }

    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        func append(_ item: String) {
            lock.lock()
            items.append(item)
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    private static func prepareRuntime(
        executable: URL,
        authSource: URL,
        forceUnauthorized: Bool
    ) async throws -> PreparedRuntime {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-native-baseline-\(UUID().uuidString)", isDirectory: true)
        let piAgent = root.appendingPathComponent("PiAgent", isDirectory: true)
        let runtimeDir = root.appendingPathComponent("Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: piAgent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        let authDest = piAgent.appendingPathComponent("auth.json")
        if forceUnauthorized {
            try Data(#"{"deepseek":{"type":"api","key":"sk-invalid-native-baseline"}}"#.utf8)
                .write(to: authDest, options: .atomic)
        } else {
            try FileManager.default.copyItem(at: authSource, to: authDest)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: authDest.path
        )
        let runtime = PiAgentRuntime(
            executableURL: executable,
            runtimeDirectory: runtimeDir,
            persistentPiConfigurationDirectory: piAgent
        )
        let model = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_BASELINE_MODEL"] ?? "deepseek-chat"
        await runtime.configure(
            PiAgentProviderConfiguration(provider: "deepseek", model: model, thinkingLevel: "low")
        )
        return PreparedRuntime(runtime: runtime, root: root, runtimeDirectory: runtimeDir)
    }

    private static func runScenario(
        _ scenario: Scenario,
        prepared: PreparedRuntime,
        sessionID: UUID,
        visualURL: URL
    ) async throws -> [String: Any] {
        let request = makeRequest(
            question: scenario.question,
            sessionID: sessionID,
            visualURL: scenario.includeVisualAsset ? visualURL : nil
        )
        let handler = makeHostHandler(request: request)
        let progress = ProgressLog()
        let started = Date()
        do {
            let reply: StudyAgentReply
            if let delay = scenario.cancelAfterNanoseconds {
                let task = Task {
                    try await prepared.runtime.respond(
                        to: request,
                        sessionID: sessionID,
                        workingDirectory: prepared.runtimeDirectory,
                        hostToolHandler: handler,
                        progress: { event in
                            progress.append(progressLabel(event))
                        }
                    )
                }
                try await Task.sleep(nanoseconds: delay)
                await prepared.runtime.cancel()
                do {
                    reply = try await task.value
                } catch {
                    return snapshot(
                        scenario: scenario,
                        request: request,
                        reply: nil,
                        progress: progress.snapshot(),
                        error: error,
                        elapsed: Date().timeIntervalSince(started)
                    )
                }
            } else {
                reply = try await prepared.runtime.respond(
                    to: request,
                    sessionID: sessionID,
                    workingDirectory: prepared.runtimeDirectory,
                    hostToolHandler: handler,
                    progress: { event in
                        progress.append(progressLabel(event))
                    }
                )
            }
            return snapshot(
                scenario: scenario,
                request: request,
                reply: reply,
                progress: progress.snapshot(),
                error: nil,
                elapsed: Date().timeIntervalSince(started)
            )
        } catch {
            return snapshot(
                scenario: scenario,
                request: request,
                reply: nil,
                progress: progress.snapshot(),
                error: error,
                elapsed: Date().timeIntervalSince(started)
            )
        }
    }

    private static func makeRequest(
        question: String,
        sessionID: UUID,
        visualURL: URL?
    ) -> StudyAgentRequest {
        let material = StudyAgentCourseItem(
            id: "material-rates",
            title: "利率课程",
            subtitle: "利率讲义",
            kind: "html",
            role: "material",
            isCurrentMaterial: true,
            linkedItemIDs: ["note-rates"],
            headings: ["利率的含义", "名义利率与实际利率"],
            searchText: "利率是资金使用价格的表达。实际利率会扣除通货膨胀对购买力的影响。在课程的近似计算中：实际利率 = 名义利率 - 通货膨胀率。"
        )
        let inflation = StudyAgentCourseItem(
            id: "material-inflation",
            title: "通货膨胀补充材料",
            subtitle: "PDF 第 4 章",
            kind: "pdf",
            role: "material",
            headings: ["第 4 页", "购买力与实际利率"],
            searchText: "通货膨胀会改变货币购买力，区分名义利率与实际利率时需要考虑通货膨胀。"
        )
        let note = StudyAgentCourseItem(
            id: "note-rates",
            title: "利率笔记",
            subtitle: "Markdown",
            kind: "markdown",
            role: "note",
            isCurrentNote: true,
            linkedItemIDs: ["material-rates"],
            headings: ["核心要点"],
            searchText: "名义利率与实际利率的区别还需要复习。"
        )
        return StudyAgentRequest(
            purpose: .conversation,
            question: question,
            materialTitle: "利率课程",
            materialText: "利率是资金使用价格的表达。名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。在课程的近似计算中：实际利率 = 名义利率 - 通货膨胀率。",
            noteTitle: "课堂笔记",
            noteText: "# 利率\n\n## 待整理",
            selectionTitle: "利率定义",
            selectionText: "利率是资金使用价格的表达。",
            courseContext: StudyAgentCourseContext(
                title: "货币金融学",
                items: [material, inflation, note],
                relations: [
                    StudyAgentCourseRelation(noteItemID: "note-rates", sourceItemID: "material-rates"),
                ]
            ),
            projectScope: StudyAgentProjectScope(
                kind: .course,
                chatID: sessionID.uuidString.lowercased(),
                courseID: "11111111-1111-1111-1111-111111111111",
                courseTitle: "货币金融学"
            ),
            visualAssets: visualURL.map {
                [StudyAgentVisualAsset(id: "asset-rates", filePath: $0.path, mediaType: "image/png")]
            } ?? [],
            learningContext: StudyAgentLearningContext(
                memoryRevision: 3,
                lastLocation: StudyLocation(
                    itemID: "material-rates",
                    itemTitle: "利率课程",
                    locationTitle: "期限结构",
                    pageIndex: 11
                ),
                memories: [
                    LearningMemoryEntry(
                        kind: .confusion,
                        text: "还不能稳定区分名义利率与实际利率",
                        evidence: "[用户：本轮] 用户上次明确说这个区别还没掌握",
                        origin: .userStatement
                    ),
                ],
                session: StudyAgentSessionSnapshot(
                    id: "pi-check-session",
                    title: "利率复习",
                    summary: "上次学到期限结构，实际利率与通货膨胀的关系还需要复习。",
                    phase: StudyPhase.recall.rawValue,
                    focusItemIDs: ["material-rates", "note-rates"],
                    turnCount: 6
                )
            ),
            language: .chinese,
            contextRevision: "native-baseline-\(sessionID.uuidString.lowercased())"
        )
    }

    private static func makeHostHandler(request: StudyAgentRequest) -> StudyAgentHostToolHandler {
        let items = request.courseContext.items
        return { toolRequest in
            switch toolRequest {
            case let .courseMap(itemID, offset, limit):
                let selected: [StudyAgentCourseItem]
                if let itemID {
                    selected = items.filter { $0.id == itemID }
                } else {
                    selected = Array(items.dropFirst(offset).prefix(limit))
                }
                return StudyAgentHostToolResult(
                    query: "",
                    items: selected.map { StudyAgentHostToolItem(item: $0, sourceRevision: "rev-1") },
                    total: itemID == nil ? items.count : selected.count
                )
            case let .courseSearch(query, limit):
                let hits = items.filter {
                    $0.searchText.localizedCaseInsensitiveContains(query)
                        || $0.title.localizedCaseInsensitiveContains(query)
                }
                .prefix(limit)
                return StudyAgentHostToolResult(
                    query: query,
                    items: hits.map { StudyAgentHostToolItem(item: $0, sourceRevision: "rev-1") },
                    total: hits.count
                )
            case let .courseRead(itemID, query, _, cursor, maximumCharacters):
                guard let item = items.first(where: { $0.id == itemID }) else {
                    throw NSError(
                        domain: "WeiBei.NativeBaseline",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "unknown item \(itemID)"]
                    )
                }
                var text = item.searchText
                if !query.isEmpty, let range = text.range(of: query, options: .caseInsensitive) {
                    let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
                    text = String(text[start...])
                }
                if cursor == "cursor-2" {
                    text = ""
                }
                let clipped = String(text.prefix(maximumCharacters))
                var resultItem = item
                resultItem.searchText = clipped
                return StudyAgentHostToolResult(
                    query: query,
                    items: [StudyAgentHostToolItem(item: resultItem, sourceRevision: "rev-1")],
                    total: 1,
                    nextCursor: cursor == nil && clipped.count >= maximumCharacters ? "cursor-2" : nil,
                    sourceRevision: "rev-1"
                )
            case .retryFailedPDFPages:
                return StudyAgentHostToolResult(query: "已开始重新索引失败页", items: [])
            case let .webOpen(url, maximumCharacters):
                return StudyAgentHostToolResult(
                    query: url,
                    items: [],
                    webPages: [
                        StudyAgentWebPage(
                            url: url,
                            title: "fixture",
                            text: String("fixture page for \(url)".prefix(maximumCharacters)),
                            isTruncated: false
                        ),
                    ]
                )
            }
        }
    }

    private static func progressLabel(_ event: StudyAgentProgress) -> String {
        switch event {
        case .preparing: return "preparing"
        case let .usingTool(name, detail):
            if let detail, !detail.isEmpty { return "tool:\(name):\(detail)" }
            return "tool:\(name)"
        case .text: return "text"
        case .visualization: return "visualization"
        }
    }

    private static func snapshot(
        scenario: Scenario,
        request: StudyAgentRequest,
        reply: StudyAgentReply?,
        progress: [String],
        error: Error?,
        elapsed: TimeInterval
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "id": scenario.id,
            "question": scenario.question,
            "elapsedSeconds": (elapsed * 10).rounded() / 10,
            "progress": progress,
            "contextRevision": request.contextRevision,
        ]
        if let reply {
            payload["backend"] = reply.backend.rawValue
            payload["text"] = reply.text
            payload["toolTrace"] = reply.toolTrace
            payload["sources"] = reply.sources.map { source -> [String: Any] in
                var row: [String: Any] = ["label": source.label, "title": source.title]
                if let itemID = source.itemID {
                    row["itemID"] = itemID
                }
                return row
            }
            payload["hasNoteProposal"] = reply.noteProposal != nil
            payload["hasRelationProposal"] = reply.relationProposal != nil
            payload["hasLearningUpdate"] = reply.learningUpdate != nil
            payload["hasCourseProfileUpdate"] = reply.courseProfileUpdate != nil
            payload["hasRichAnswer"] = false
            payload["readItemIDs"] = reply.readItemIDs
        }
        if let error {
            payload["error"] = error.localizedDescription
            payload["failureKind"] = AgentFailureKind.classify(error).rawValue
        }
        return payload
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func writeTinyPNG() throws -> URL {
        // 1x1 PNG
        let bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
            0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
            0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-baseline-asset.png")
        try Data(bytes).write(to: url, options: .atomic)
        return url
    }
}
