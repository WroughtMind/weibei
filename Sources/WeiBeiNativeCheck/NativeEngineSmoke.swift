import Darwin
import Foundation
import WeiBeiCore

enum NativeEngineSmoke {
    static func runIfRequested(arguments: [String]) async -> Bool {
        if arguments.contains("--native-perf") {
            do {
                try await runDeepSeekPerf()
            } catch {
                fputs("native-perf failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return true
        }
        if arguments.contains("--native-deepseek-smoke") {
            do {
                try await runDeepSeekPlainQA()
                print("native-deepseek-smoke passed")
            } catch {
                fputs("native-deepseek-smoke failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return true
        }
        if arguments.contains("--native-provider-matrix") {
            printMatrix()
            return true
        }
        if arguments.contains("--native-codex-live") {
            do {
                try await runLive(provider: .openaiCodex)
                print("native-codex-live passed: plain-qa, tool-call, cancel")
            } catch {
                fputs("native-codex-live failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return true
        }
        if let index = arguments.firstIndex(of: "--native-live") {
            let token = arguments.dropFirst(index + 1).first ?? ""
            do {
                if token.isEmpty || token.hasPrefix("--") {
                    print("usage: WeiBeiNativeCheck --native-live <provider-id>|available")
                    return true
                }
                if token == "available" {
                    let providers = try availableLiveProviders()
                    guard !providers.isEmpty else {
                        throw NSError(domain: "WeiBei.NativeSmoke", code: 11, userInfo: [NSLocalizedDescriptionKey: "no API keys or ChatGPT subscription available for live three-loop"])
                    }
                    for provider in providers {
                        try await runLive(provider: provider)
                        print("native-live \(provider.rawValue) passed: plain-qa, tool-call, cancel")
                    }
                } else if let provider = AgentProviderID(rawValue: token) {
                    try await runLive(provider: provider)
                    print("native-live \(provider.rawValue) passed: plain-qa, tool-call, cancel")
                } else {
                    throw NSError(domain: "WeiBei.NativeSmoke", code: 12, userInfo: [NSLocalizedDescriptionKey: "unknown provider \(token)"])
                }
            } catch {
                fputs("native-live failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return true
        }
        guard arguments.contains("--native-engine-smoke") else { return false }
        do {
            try await run()
            print("native-engine-smoke passed: plain-qa, tool-call, cancel")
        } catch {
            fputs("native-engine-smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        return true
    }

    static func run() async throws {
        try await runPlainQA()
        try await runSearchThenAnswer()
        try await runCancel()
    }

    private static func runPlainQA() async throws {
        let adapter = ScriptedLLMAdapter(chunks: [
            [.textDelta(index: 0, text: "4"), .finish(reason: .stop, replayState: nil)],
        ])
        let reply = try await respond(question: "2+2 等于几？", adapter: adapter)
        guard reply.backend == .native, reply.text.contains("4"), reply.toolTrace.isEmpty else {
            throw NSError(domain: "WeiBei.NativeSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "plain QA failed"])
        }
    }

    private static func runSearchThenAnswer() async throws {
        let adapter = ScriptedLLMAdapter(chunks: [
            [
                .toolCallDelta(index: 0, id: "c1", name: "weibei_course_search", argumentsDelta: "{\"query\":\"利率\"}"),
                .finish(reason: .toolCalls, replayState: nil),
            ],
            [
                .textDelta(index: 0, text: "利率是资金使用价格。"),
                .finish(reason: .stop, replayState: nil),
            ],
        ])
        let reply = try await respond(
            question: "利率这一节讲了什么？",
            adapter: adapter,
            host: { request in
                guard case let .courseSearch(query, _, _) = request, query.contains("利率") else {
                    throw NSError(domain: "WeiBei.NativeSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "unexpected host request"])
                }
                return StudyAgentHostToolResult(
                    query: query,
                    items: [
                        StudyAgentHostToolItem(
                            item: StudyAgentCourseItem(
                                id: "material-rates",
                                title: "利率课程",
                                subtitle: "",
                                kind: "html",
                                role: "material",
                                searchText: "利率是资金使用价格的表达。"
                            ),
                            sourceRevision: "rev-1"
                        ),
                    ]
                )
            }
        )
        guard reply.text.contains("资金"), reply.toolTrace.contains("weibei_course_search") else {
            throw NSError(domain: "WeiBei.NativeSmoke", code: 3, userInfo: [NSLocalizedDescriptionKey: "search-then-answer failed"])
        }
    }

    private static func runCancel() async throws {
        let adapter = ScriptedLLMAdapter(chunks: [
            [.textDelta(index: 0, text: "很长的解释")],
        ], hangAfterFirstChunk: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-smoke-\(UUID().uuidString)")
        let runtime = NativeStudyAgentRuntime(
            model: "mock",
            adapter: adapter,
            ledgerRoot: root,
            systemPromptText: "test",
            hostToolHandler: nil
        )
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: "请详细解释",
            materialTitle: "",
            materialText: "",
            noteTitle: "",
            noteText: "",
            contextRevision: "smoke-cancel"
        )
        let task = Task {
            try await runtime.respond(to: request, progress: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await runtime.cancel()
        do {
            _ = try await task.value
            throw NSError(domain: "WeiBei.NativeSmoke", code: 4, userInfo: [NSLocalizedDescriptionKey: "cancel should throw"])
        } catch let failure as NativeLLMFailure {
            guard failure.code == "cancelled" else { throw failure }
        } catch {
            let kind = AgentFailureKind.classify(error)
            guard kind == .cancelled else { throw error }
        }
    }

    private static func printMatrix() {
        for provider in AgentProviderID.allCases {
            let route = NativeProviderRouting.route(provider)
            let host = route.baseURL?.host ?? "-"
            print(
                "native-provider \(provider.rawValue) family=\(route.family.rawValue) auth=\(route.auth.rawValue) host=\(host) model=\(route.defaultModel.isEmpty ? "-" : route.defaultModel)"
            )
        }
        let uncovered = NativeProviderRouting.uncoveredProviders.map(\.rawValue).joined(separator: ",")
        print("native-provider uncovered=\(uncovered)")
    }

    private static func availableLiveProviders() throws -> [AgentProviderID] {
        let store = try NativeAgentCredentialStore.defaultStore()
        return AgentProviderID.allCases.filter { provider in
            let route = NativeProviderRouting.route(provider)
            if route.family == .unsupported { return false }
            if provider == .openaiCodex {
                return (try? NativeOpenAIOAuth.leftoverCredentialExists(in: store)) == true
            }
            if let key = try? NativeAgentCredentialStore.apiKey(forProviderID: provider.rawValue), !key.isEmpty {
                return true
            }
            return false
        }
    }

    private static func runLive(provider: AgentProviderID) async throws {
        let route = NativeProviderRouting.route(provider)
        guard route.family != .unsupported else {
            throw NSError(domain: "WeiBei.NativeSmoke", code: 13, userInfo: [NSLocalizedDescriptionKey: route.note])
        }
        let endpoint = try AgentProviderEndpoint(provider: provider, baseURL: "")
        let model = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_LIVE_MODEL"]
            ?? ProcessInfo.processInfo.environment["WEIBEI_NATIVE_CODEX_MODEL"]
            ?? (route.defaultModel.isEmpty ? "default" : route.defaultModel)
        let adapter = try await NativeLLMAdapterFactory.make(
            provider: provider,
            model: model,
            endpoint: endpoint
        )
        let label = "native-live \(provider.rawValue)"
        try await runLivePlainQA(adapter: adapter, model: model, label: label)
        try await runLiveCourseTool(adapter: adapter, model: model, label: label)
        try await runLiveCancel(adapter: adapter, model: model, label: label)
    }

    private static func runLivePlainQA(adapter: NativeLLMAdapter, model: String, label: String) async throws {
        let reply = try await respond(
            question: "2+2 等于几？只回答一个数字，不要解释。",
            adapter: adapter,
            model: model
        )
        let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reply.backend == .native, !text.isEmpty else {
            throw NSError(domain: "WeiBei.NativeSmoke", code: 7, userInfo: [NSLocalizedDescriptionKey: "\(label) plain QA was empty"])
        }
        print("\(label) plain-qa prefix=\(text.prefix(40)) tools=\(reply.toolTrace.joined(separator: ","))")
    }

    private static func runLiveCourseTool(adapter: NativeLLMAdapter, model: String, label: String) async throws {
        let reply = try await respond(
            question: """
            必须先调用 weibei_course_search，参数 query 设为「利率」。
            禁止使用 web_search，禁止跳过工具直接回答。
            拿到工具结果后只用一句话作答。
            """,
            adapter: adapter,
            host: { request in
                guard case let .courseSearch(query, _, _) = request else {
                    throw NSError(domain: "WeiBei.NativeSmoke", code: 8, userInfo: [NSLocalizedDescriptionKey: "\(label) expected courseSearch"])
                }
                return StudyAgentHostToolResult(
                    query: query,
                    items: [
                        StudyAgentHostToolItem(
                            item: StudyAgentCourseItem(
                                id: "material-rates",
                                title: "利率课程",
                                subtitle: "",
                                kind: "html",
                                role: "material",
                                searchText: "利率是资金使用价格的表达。"
                            ),
                            sourceRevision: "rev-live-1"
                        ),
                    ]
                )
            },
            model: model
        )
        guard reply.toolTrace.contains("weibei_course_search") else {
            throw NSError(
                domain: "WeiBei.NativeSmoke",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "\(label) did not call weibei_course_search; trace=\(reply.toolTrace.joined(separator: ","))"]
            )
        }
        print("\(label) tool-call prefix=\(reply.text.prefix(40)) tools=\(reply.toolTrace.joined(separator: ","))")
    }

    private static func runLiveCancel(adapter: NativeLLMAdapter, model: String, label: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-live-\(UUID().uuidString)")
        let runtime = NativeStudyAgentRuntime(
            model: model,
            adapter: adapter,
            ledgerRoot: root,
            systemPromptText: "you are webi",
            hostToolHandler: nil
        )
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: "请从1连续写到200，每个数字单独一行，不要省略。",
            materialTitle: "",
            materialText: "",
            noteTitle: "",
            noteText: "",
            contextRevision: "native-live-cancel"
        )
        let started = CancelStartBox()
        let task = Task {
            try await runtime.respond(
                to: request,
                progress: { progress in
                    if case .text = progress {
                        await started.mark()
                    }
                }
            )
        }
        for _ in 0..<80 {
            if await started.didStart { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        await runtime.cancel()
        do {
            _ = try await task.value
            throw NSError(domain: "WeiBei.NativeSmoke", code: 10, userInfo: [NSLocalizedDescriptionKey: "\(label) cancel should throw"])
        } catch let failure as NativeLLMFailure {
            guard failure.code == "cancelled" else { throw failure }
        } catch {
            let kind = AgentFailureKind.classify(error)
            guard kind == .cancelled else { throw error }
        }
        print("\(label) cancel classified=cancelled")
    }

    private static func runDeepSeekPerf() async throws {
        let apiKey = try deepSeekKey()
        let model = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_BASELINE_MODEL"] ?? "deepseek-chat"
        let adapter = OpenAIChatCompletionsProvider(apiKey: apiKey)
        var walls: [Double] = []
        var ttfts: [Double] = []
        for index in 1...5 {
            let sample = try await timedRespond(
                question: "2+2 等于几？只回答一个数字。",
                adapter: adapter,
                model: model
            )
            walls.append(sample.wall)
            if let ttft = sample.ttft { ttfts.append(ttft) }
            print(
                "native-perf native \(index) wall=\(fmt(sample.wall))s ttft=\(fmt(sample.ttft))s chars=\(sample.chars)"
            )
        }
        print(
            "native-perf native wall-median=\(fmt(median(walls)))s ttft-median=\(fmt(median(ttfts)))s n=5 model=\(model)"
        )
        try await runLiveCourseTool(adapter: adapter, model: model, label: "native-perf native")
        print("native-perf native maxrss=\(maxRSSBytes())B after-tool-call")

    }

    private static func timedRespond(
        question: String,
        adapter: NativeLLMAdapter,
        model: String
    ) async throws -> (wall: Double, ttft: Double?, chars: Int) {
        let first = FirstTokenBox()
        let started = Date()
        let reply = try await respond(
            question: question,
            adapter: adapter,
            model: model,
            progress: { progress in
                if case .text = progress { await first.mark(since: started) }
            }
        )
        return (
            wall: Date().timeIntervalSince(started),
            ttft: await first.seconds,
            chars: reply.text.count
        )
    }

    private static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private static func fmt(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.3f", value)
    }

    private static func maxRSSBytes() -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss)
    }

    private static func deepSeekKey() throws -> String {
        guard let apiKey = try NativeAgentCredentialStore.apiKey(forProviderID: AgentProviderID.deepseek.credentialProviderID) else {
            throw NSError(domain: "WeiBei.NativeSmoke", code: 5, userInfo: [NSLocalizedDescriptionKey: "DeepSeek key not found in native credential store"])
        }
        return apiKey
    }

    private static func runDeepSeekPlainQA() async throws {
        let apiKey = try deepSeekKey()
        let model = ProcessInfo.processInfo.environment["WEIBEI_NATIVE_BASELINE_MODEL"] ?? "deepseek-chat"
        let adapter = OpenAIChatCompletionsProvider(apiKey: apiKey)
        let reply = try await respond(question: "2+2 等于几？只回答一个数字。", adapter: adapter, model: model)
        guard reply.backend == .native, !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "WeiBei.NativeSmoke", code: 6, userInfo: [NSLocalizedDescriptionKey: "DeepSeek native reply was empty"])
        }
        print("native-deepseek-smoke text-prefix=\(reply.text.prefix(40))")
    }

    private static func respond(
        question: String,
        adapter: NativeLLMAdapter,
        host: StudyAgentHostToolHandler? = nil,
        model: String = "mock",
        progress: StudyAgentProgressHandler? = nil
    ) async throws -> StudyAgentReply {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-smoke-\(UUID().uuidString)")
        let runtime = NativeStudyAgentRuntime(
            model: model,
            adapter: adapter,
            ledgerRoot: root,
            systemPromptText: "you are webi",
            hostToolHandler: host
        )
        return try await runtime.respond(
            to: StudyAgentRequest(
                purpose: .conversation,
                question: question,
                materialTitle: "利率课程",
                materialText: "利率是资金使用价格的表达。",
                noteTitle: "",
                noteText: "",
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
                    chatID: UUID().uuidString.lowercased(),
                    courseID: UUID().uuidString.lowercased()
                ),
                contextRevision: "smoke"
            ),
            progress: progress
        )
    }
}

private actor CancelStartBox {
    var didStart = false
    func mark() { didStart = true }
}

private actor FirstTokenBox {
    private(set) var seconds: Double?
    func mark(since started: Date) {
        if seconds == nil {
            seconds = Date().timeIntervalSince(started)
        }
    }
}

private final class ScriptedLLMAdapter: NativeLLMAdapter, @unchecked Sendable {
    var family: String { "scripted" }
    private let chunks: [[NativeStreamChunk]]
    private let hangAfterFirstChunk: Bool
    private var step = 0
    private let lock = NSLock()

    init(chunks: [[NativeStreamChunk]], hangAfterFirstChunk: Bool = false) {
        self.chunks = chunks
        self.hangAfterFirstChunk = hangAfterFirstChunk
    }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            let index = min(step, max(chunks.count - 1, 0))
            let current = chunks.isEmpty ? [] : chunks[index]
            step += 1
            lock.unlock()
            let hang = hangAfterFirstChunk
            let task = Task {
                do {
                    for chunk in current {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                        if hang {
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: NativeLLMFailure(code: "cancelled", message: "cancelled"))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
