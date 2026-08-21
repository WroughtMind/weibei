import Foundation
import WeiBeiCore

enum NativeEngineSmoke {
    static func runIfRequested(arguments: [String]) async -> Bool {
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
                guard case let .courseSearch(query, _) = request, query.contains("利率") else {
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

    private static func runDeepSeekPlainQA() async throws {
        let authURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.changfenhuang.weibei/PiAgent/auth.json")
        let data = try Data(contentsOf: authURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deepseek = object["deepseek"] as? [String: Any],
              let apiKey = deepseek["key"] as? String,
              !apiKey.isEmpty else {
            throw NSError(domain: "WeiBei.NativeSmoke", code: 5, userInfo: [NSLocalizedDescriptionKey: "DeepSeek key not found in Pi auth.json"])
        }
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
        model: String = "mock"
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
            progress: nil
        )
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
