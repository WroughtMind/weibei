import Darwin
import Foundation
import WeiBeiCore

enum NativeEvalCLI {
    static func runIfRequested(arguments: [String]) async -> Bool {
        guard arguments.contains("--native-eval") || arguments.contains("--native-eval-self-check") else { return false }
        do {
            try await run(arguments: arguments)
        } catch {
            fputs("native-eval failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        return true
    }

    static func run(arguments: [String]) async throws {
        let model = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_EVAL_MODEL"] ?? "gpt-5.6-luna"
        let effort = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_EVAL_EFFORT"] ?? "low"
        if arguments.contains("--native-eval-self-check") {
            try await checkOffline(model: model, effort: effort)
            return
        }
        let backend: String
        if let index = arguments.firstIndex(of: "--backend"),
           let raw = arguments.dropFirst(index + 1).first,
           !raw.hasPrefix("--") {
            backend = raw
        } else {
            backend = "native"
        }
        let setURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Docs/audit/2026-08-22-native-agent-runtime-评测集.json")
        let data = try Data(contentsOf: setURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else {
            throw NSError(domain: "WeiBei.NativeEval", code: 1, userInfo: [NSLocalizedDescriptionKey: "eval set JSON missing items"])
        }
        let selected: [[String: Any]]
        if let index = arguments.firstIndex(of: "--ids"),
           let raw = arguments.dropFirst(index + 1).first,
           !raw.hasPrefix("--") {
            let wanted = Set(
                raw.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
            )
            selected = items.filter { wanted.contains($0["id"] as? String ?? "") }
            let found = Set(selected.compactMap { $0["id"] as? String })
            let missing = wanted.subtracting(found)
            guard missing.isEmpty else {
                throw NSError(
                    domain: "WeiBei.NativeEval",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "unknown eval ids: \(missing.sorted().joined(separator: ","))"]
                )
            }
        } else {
            let limit: Int
            if let index = arguments.firstIndex(of: "--limit"),
               let raw = arguments.dropFirst(index + 1).first,
               let parsed = Int(raw) {
                limit = parsed
            } else {
                limit = items.count
            }
            selected = Array(items.prefix(limit))
        }
        print("native-eval backend=\(backend) model=\(model) effort=\(effort) items=\(selected.count)")
        fflush()
        switch backend {
        case "native":
            try await runNative(items: selected, model: model, effort: effort)
        default:
            throw NSError(domain: "WeiBei.NativeEval", code: 2, userInfo: [NSLocalizedDescriptionKey: "backend must be native"])
        }
    }

    private static func fflush() {
        Darwin.fflush(stdout)
    }

    private static func runNative(items: [[String: Any]], model: String, effort: String) async throws {
        let store = try NativeAgentCredentialStore.defaultStore()
        let signedIn = try NativeOpenAIOAuth.leftoverCredentialExists(in: store)
        print("native-eval signed-in=\(signedIn)")
        fflush()
        guard signedIn else {
            print("native-eval skipped live ChatGPT run: native oauth is signed-out. Re-login then rerun --native-eval.")
            return
        }
        let endpoint = try AgentProviderEndpoint(provider: .openaiCodex, baseURL: "")
        let adapter = try await NativeLLMAdapterFactory.make(
            provider: .openaiCodex,
            model: model,
            endpoint: endpoint
        )
        let outputRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Docs/audit/native-eval-\(UUID().uuidString.lowercased())", isDirectory: true)
        try await runItems(items, model: model, effort: effort, adapter: adapter, outputRoot: outputRoot)
        print("native-eval results=\(outputRoot.path)")
    }

    private static func runItems(
        _ items: [[String: Any]], model: String, effort: String, adapter: NativeLLMAdapter, outputRoot: URL
    ) async throws {
        let resources = try AgentResources.bundled()
        let liveStores = NativeLiveStores(
            skillRegistry: try NativeSkillRegistry.load(from: resources.skillsURL)
        )
        var ran = 0
        for item in items {
            let id = item["id"] as? String ?? "?"
            let scene = item["scene"] as? String ?? ""
            let turns: [String]
            if let value = item["turns"] {
                guard let questions = value as? [String], !questions.isEmpty,
                      questions.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw NSError(domain: "WeiBei.NativeEval", code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "\(id): turns must contain nonempty questions"])
                }
                turns = questions
            } else {
                turns = [item["question"] as? String ?? ""]
            }
            if scene == "cancel" || scene == "error" {
                print("native-eval \(id) skipped scene=\(scene)")
                fflush()
                continue
            }
            let root = outputRoot.appendingPathComponent("ledgers/\(id)", isDirectory: true)
            let sessionID = UUID()
            let capture = NativeEvalCaptureAdapter(base: adapter)
            let runtime = NativeStudyAgentRuntime(
                model: model,
                adapter: capture,
                providerID: AgentProviderID.openaiCodex.rawValue,
                ledgerRoot: root,
                systemPromptText: resources.systemPrompt,
                hostToolHandler: evalHost,
                liveStores: liveStores
            )
            for (index, question) in turns.enumerated() {
                let turnID = turns.count == 1 ? id : "\(id).turn-\(index + 1)"
                let request = evalRequest(id: id, question: question, sessionID: sessionID, effort: effort,
                    context: item["context"] as? String)
                do {
                    let reply = try await runtime.respond(to: request, progress: nil)
                    try recordAnswer(root: outputRoot, id: turnID, scene: scene, question: question,
                        text: reply.text, tools: reply.toolTrace, requests: capture.drain(),
                        sessionID: sessionID, turn: index + 1)
                    ran += 1
                } catch {
                    try recordAnswer(root: outputRoot, id: turnID, scene: scene, question: question,
                        text: "", tools: [], requests: capture.drain(), sessionID: sessionID, turn: index + 1,
                        error: error.localizedDescription)
                    throw error
                }
            }
        }
        print("native-eval turns-ran=\(ran) model=\(model) effort=\(effort)")
        fflush()
    }

    private static func recordAnswer(
        root: URL,
        id: String,
        scene: String,
        question: String,
        text: String,
        tools: [String],
        requests: [NativeLLMRequest],
        sessionID: UUID,
        turn: Int,
        error: String? = nil
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var body = """
        # \(id) · \(scene)

        ## 问题

        \(question)

        ## 工具

        \(tools.isEmpty ? "（无）" : tools.joined(separator: ", "))

        """
        if let error {
            body += "## 错误\n\n\(error)\n\n"
        }
        body += "## 完整回答\n\n\(text)\n"
        body += "\n## 人工审阅\n\n| 事实 | 来源支持 | 时点与口径 | 前文回忆 |\n|---|---|---|---|\n| 未判分 | 未判分 | 未判分 | 未判分 |\n"
        try Data(body.utf8).write(to: root.appendingPathComponent("\(id).md"), options: .atomic)
        var record: [String: Any] = [
            "id": id,
            "scene": scene,
            "question": question,
            "tools": tools,
            "text": text,
            "chars": (text as NSString).length,
            "sessionID": sessionID.uuidString.lowercased(),
            "turn": turn,
            "requests": requests.map { request -> [String: Any] in
                let payload = OpenAIResponsesProvider.payload(for: request)
                return [
                    "model": request.model,
                    "purpose": request.purpose.rawValue,
                    "requestEffort": request.reasoningEffort as Any? ?? NSNull(),
                    "payloadEffort": (payload["reasoning"] as? [String: Any])?["effort"] ?? NSNull(),
                    "messageCount": request.messages.count,
                ]
            },
            "serviceEffort": NSNull(),
            "serviceEffortStatus": "未采集",
            "review": ["事实": "未判分", "来源支持": "未判分", "时点与口径": "未判分", "前文回忆": "未判分"],
        ]
        if let error { record["error"] = error }
        let line = try JSONSerialization.data(withJSONObject: record)
        try upsertJSONL(root.appendingPathComponent("answers.jsonl"), id: id, line: line)
        let shown = error == nil ? "chars=\((text as NSString).length)" : "failed"
        print("native-eval \(id) scene=\(scene) \(shown) tools=\(tools.joined(separator: ","))")
        fflush()
    }

    private static func upsertJSONL(_ url: URL, id: String, line: Data) throws {
        var records: [Data] = []
        var replaced = false
        if FileManager.default.fileExists(atPath: url.path),
           let existing = try? String(contentsOf: url, encoding: .utf8) {
            for raw in existing.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(raw).data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if object["id"] as? String == id {
                    records.append(line)
                    replaced = true
                } else {
                    records.append(data)
                }
            }
        }
        if !replaced {
            records.append(line)
        }
        var payload = Data()
        for record in records {
            payload.append(record)
            payload.append(Data("\n".utf8))
        }
        try payload.write(to: url, options: .atomic)
    }

    private static func evalRequest(id: String, question: String, sessionID: UUID, effort: String, context: String?) -> StudyAgentRequest {
        StudyAgentRequest(
            purpose: .conversation,
            question: question,
            materialTitle: "利率课程",
            materialText: "利率是资金使用价格的表达。",
            noteTitle: "",
            noteText: "",
            selectionTitle: context == nil ? nil : "评测背景",
            selectionText: context,
            courseContext: StudyAgentCourseContext(
                title: "货币金融学",
                items: [
                    StudyAgentCourseItem(
                        id: "material-rates",
                        title: "利率课程",
                        subtitle: "",
                        kind: "html",
                        role: "material",
                        searchText: "利率是资金使用价格的表达。"
                    ),
                ]
            ),
            projectScope: StudyAgentProjectScope(
                kind: .course,
                chatID: sessionID.uuidString.lowercased(),
                courseID: sessionID.uuidString.lowercased()
            ),
            contextRevision: "eval-\(id)",
            reasoningEffort: effort
        )
    }

    /// Exercises the real evaluator without credentials, network access, or an existing user session.
    private static func checkOffline(model: String, effort: String) async throws {
        struct OfflineAdapter: NativeLLMAdapter {
            let family = "openai-codex-responses"
            func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta(index: 0, text: "离线回答"))
                    continuation.yield(.finish(reason: .stop, replayState: nil))
                    continuation.finish()
                }
            }
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "WeiBei.NativeEval", code: 7,
                userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let capture = NativeEvalCaptureAdapter(base: OfflineAdapter())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-eval-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = "本案例统计截止日期为 2026-09-17。"
        try await runItems([["id": "offline", "scene": "multi-turn", "context": context, "turns": ["第一问", "接着问"]]],
            model: model, effort: effort, adapter: capture, outputRoot: root)
        let requests = capture.drain()
        try require(requests.count == 2, "expected two model requests")
        for request in requests {
            try require(request.reasoningEffort == effort, "request effort does not match configuration")
            let payloadEffort = (OpenAIResponsesProvider.payload(for: request)["reasoning"] as? [String: String])?["effort"]
            try require(payloadEffort == effort, "payload effort does not match configuration")
        }
        let first = requests[0].messages
        let second = requests[1].messages
        try require(first.contains { $0.role == .user && $0.content == "第一问" }, "original question changed")
        try require(first.contains { $0.content.contains(context) }, "case context never reached the model")
        try require(second.count > first.count && Array(second.prefix(first.count)) == first, "multi-turn prefix was lost")
        try require(requests[0].promptCacheKey == requests[1].promptCacheKey, "session changed between turns")
        let lines = try String(contentsOf: root.appendingPathComponent("answers.jsonl")).split(separator: "\n")
        let records = try lines.compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        try require(records.count == 2 && Set(records.compactMap { $0["sessionID"] as? String }).count == 1, "turn records lost")
        try require(records.compactMap { $0["turn"] as? Int } == [1, 2], "turn order lost")
        for record in records {
            let captured = (record["requests"] as? [[String: Any]])?.first
            try require(captured?["requestEffort"] as? String == effort && captured?["payloadEffort"] as? String == effort,
                "saved configuration does not match request")
            try require(record["serviceEffortStatus"] as? String == "未采集", "request must not be labeled as service confirmation")
        }
        print("native-eval-self-check passed model=\(model) effort=\(effort) turns=2 (offline)")
    }

    private static let evalHost: StudyAgentHostToolHandler = { request in
        let item = StudyAgentCourseItem(
            id: "material-rates",
            title: "利率课程",
            subtitle: "",
            kind: "html",
            role: "material",
            searchText: "利率是资金使用价格的表达。"
        )
        _ = request
        return StudyAgentHostToolResult(
            query: "利率",
            items: [StudyAgentHostToolItem(item: item, sourceRevision: "rev-eval")]
        )
    }
}

private final class NativeEvalCaptureAdapter: NativeLLMAdapter, @unchecked Sendable {
    let base: NativeLLMAdapter
    private let lock = NSLock()
    private var requests: [NativeLLMRequest] = []
    var family: String { base.family }
    var contextWindow: Int? { base.contextWindow }

    init(base: NativeLLMAdapter) { self.base = base }

    func drain() -> [NativeLLMRequest] {
        lock.withLock {
            defer { requests.removeAll() }
            return requests
        }
    }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        lock.withLock { requests.append(request) }
        return base.stream(request)
    }
}
