import Foundation
import WeiBeiCore

enum NativeScenarioPair {
    static func runIfRequested(arguments: [String]) async -> Bool {
        guard arguments.contains("--native-scenario-pair") else { return false }
        do {
            try await run()
            print("native-scenario-pair passed")
        } catch {
            fputs("native-scenario-pair failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        return true
    }

    static func run() async throws {
        var rows: [[String: Any]] = []
        rows.append(try await row(id: "01-plain-qa", tools: [], textMustContain: "4", chunks: [
            [.textDelta(index: 0, text: "4"), .finish(reason: .stop, replayState: nil)],
        ]))
        rows.append(try await row(id: "02-course-search", tools: ["weibei_course_search"], textMustContain: "资金", chunks: [
            [
                .toolCallDelta(index: 0, id: "c1", name: "weibei_course_search", argumentsDelta: "{\"query\":\"利率\"}"),
                .finish(reason: .toolCalls, replayState: nil),
            ],
            [.textDelta(index: 0, text: "利率是资金使用价格。"), .finish(reason: .stop, replayState: nil)],
        ], host: courseHost))
        rows.append(try await row(id: "03-course-read", tools: ["weibei_course_read"], textMustContain: "资金", chunks: [
            [
                .toolCallDelta(index: 0, id: "c1", name: "weibei_course_read", argumentsDelta: "{\"itemID\":\"material-rates\",\"query\":\"利率\"}"),
                .finish(reason: .toolCalls, replayState: nil),
            ],
            [.textDelta(index: 0, text: "原文：利率是资金使用价格的表达。"), .finish(reason: .stop, replayState: nil)],
        ], host: courseHost))
        rows.append(try await row(id: "04-learning-memory", tools: ["weibei_learning_memory"], textMustContain: "记忆", chunks: [
            [.toolCallDelta(index: 0, id: "c1", name: "weibei_learning_memory", argumentsDelta: "{}"), .finish(reason: .toolCalls, replayState: nil)],
            [.textDelta(index: 0, text: "学习记忆已读取，上次停在利率定义。"), .finish(reason: .stop, replayState: nil)],
        ]))
        rows.append(try await row(id: "05-course-profile", tools: ["weibei_course_profile_update"], expectProfile: true, chunks: [
            [
                .toolCallDelta(index: 0, id: "c1", name: "weibei_course_profile_update", argumentsDelta: "{\"contextRevision\":\"pair\",\"profileRevision\":0,\"checkpoint\":\"利率定义\"}"),
                .finish(reason: .toolCalls, replayState: nil),
            ],
            [.textDelta(index: 0, text: "档案建议已提交，尚未落库。"), .finish(reason: .stop, replayState: nil)],
        ]))
        rows.append(try await row(
            id: "06-note-relation",
            tools: ["weibei_note_proposal", "weibei_relation_proposal"],
            expectNote: true,
            expectRelation: true,
            chunks: [
                [
                    .toolCallDelta(index: 0, id: "n1", name: "weibei_note_proposal", argumentsDelta: "{\"markdown\":\"利率是资金使用价格。\",\"evidence\":[\"利率课程\"],\"contextRevision\":\"pair\"}"),
                    .toolCallDelta(index: 1, id: "r1", name: "weibei_relation_proposal", argumentsDelta: "{\"noteItemID\":\"note-1\",\"sourceItemID\":\"material-rates\",\"contextRevision\":\"pair\"}"),
                    .finish(reason: .toolCalls, replayState: nil),
                ],
                [.textDelta(index: 0, text: "笔记和关系都是待确认建议。"), .finish(reason: .stop, replayState: nil)],
            ]
        ))
        rows.append(try await row(id: "07-visualize", tools: ["weibei_visualize"], chunks: [
            [
                .toolCallDelta(index: 0, id: "v1", name: "weibei_visualize", argumentsDelta: "{\"id\":\"real-rate\",\"spec\":{\"items\":[{\"type\":\"text\",\"content\":\"实际利率\"}]}}"),
                .finish(reason: .toolCalls, replayState: nil),
            ],
            [.textDelta(index: 0, text: "互动界面已显示。"), .finish(reason: .stop, replayState: nil)],
        ]))
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("pair-asset.png")
        try Data([137, 80, 78, 71, 13, 10, 26, 10]).write(to: png)
        rows.append(try await row(
            id: "08-visual-asset",
            tools: ["weibei_visual_asset"],
            chunks: [
                [
                    .toolCallDelta(index: 0, id: "a1", name: "weibei_visual_asset", argumentsDelta: "{\"assetID\":\"asset-1\"}"),
                    .finish(reason: .toolCalls, replayState: nil),
                ],
                [.textDelta(index: 0, text: "图里没有可读文字。"), .finish(reason: .stop, replayState: nil)],
            ],
            visualURL: png
        ))
        rows.append(try await cancelRow())
        rows.append(try await unauthorizedRow())
        let session = UUID().uuidString.lowercased()
        rows.append(try await row(
            id: "11-resume-a",
            tools: ["weibei_course_search"],
            textMustContain: "资金",
            chunks: [
                [
                    .toolCallDelta(index: 0, id: "c1", name: "weibei_course_search", argumentsDelta: "{\"query\":\"资金价格\"}"),
                    .finish(reason: .toolCalls, replayState: nil),
                ],
                [.textDelta(index: 0, text: "已记住关键词是资金价格。"), .finish(reason: .stop, replayState: nil)],
            ],
            host: courseHost,
            chatID: session
        ))
        rows.append(try await row(
            id: "12-resume-b",
            tools: [],
            textMustContain: "资金价格",
            chunks: [
                [.textDelta(index: 0, text: "刚才记住的课程关键词是资金价格。"), .finish(reason: .stop, replayState: nil)],
            ],
            chatID: session
        ))
        rows.append(try await row(
            id: "13-multi-tool",
            tools: ["weibei_course_search", "weibei_course_read"],
            chunks: [
                [
                    .toolCallDelta(index: 0, id: "s1", name: "weibei_course_search", argumentsDelta: "{\"query\":\"通货膨胀\"}"),
                    .toolCallDelta(index: 1, id: "r1", name: "weibei_course_read", argumentsDelta: "{\"itemID\":\"material-rates\",\"query\":\"通胀\"}"),
                    .finish(reason: .toolCalls, replayState: nil),
                ],
                [.textDelta(index: 0, text: "用了搜索和正文读取。"), .finish(reason: .stop, replayState: nil)],
            ],
            host: courseHost
        ))

        let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Docs/audit/2026-08-22-native-runtime-12场景对拍.json")
        let payload: [String: Any] = [
            "native": rows,
            "piFixture": "Docs/audit/2026-08-22-native-agent-runtime-Pi行为夹具/summary.json",
            "note": "Native 侧为确定性脚本夹具，核对工具序列与提案结构；Pi 夹具是 DeepSeek live 基线。",
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: out)
        print("native-scenario-pair wrote \(rows.count) rows to \(out.path)")
    }

    private static func courseHost(_ request: StudyAgentHostToolRequest) async throws -> StudyAgentHostToolResult {
        _ = request
        let item = StudyAgentCourseItem(
            id: "material-rates",
            title: "利率课程",
            subtitle: "",
            kind: "html",
            role: "material",
            searchText: "利率是资金使用价格的表达。"
        )
        return StudyAgentHostToolResult(
            query: "利率",
            items: [StudyAgentHostToolItem(item: item, sourceRevision: "rev-1")]
        )
    }

    private static func row(
        id: String,
        tools: [String],
        textMustContain: String? = nil,
        expectNote: Bool = false,
        expectRelation: Bool = false,
        expectProfile: Bool = false,
        chunks: [[NativeStreamChunk]],
        host: StudyAgentHostToolHandler? = nil,
        visualURL: URL? = nil,
        chatID: String = UUID().uuidString.lowercased()
    ) async throws -> [String: Any] {
        let reply = try await respond(
            question: id,
            chunks: chunks,
            host: host,
            visualURL: visualURL,
            chatID: chatID
        )
        for name in tools {
            guard reply.toolTrace.contains(name) else {
                throw NSError(domain: "WeiBei.Pair", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(id) missing \(name)"])
            }
        }
        if let needle = textMustContain, !reply.text.contains(needle) {
            throw NSError(domain: "WeiBei.Pair", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(id) missing text \(needle)"])
        }
        if expectNote, reply.noteProposal == nil {
            throw NSError(domain: "WeiBei.Pair", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(id) missing note proposal"])
        }
        if expectRelation, reply.relationProposal == nil {
            throw NSError(domain: "WeiBei.Pair", code: 4, userInfo: [NSLocalizedDescriptionKey: "\(id) missing relation proposal"])
        }
        if expectProfile, reply.courseProfileUpdate == nil {
            throw NSError(domain: "WeiBei.Pair", code: 5, userInfo: [NSLocalizedDescriptionKey: "\(id) missing profile proposal"])
        }
        print("native-scenario-pair \(id) tools=\(reply.toolTrace.joined(separator: ","))")
        return [
            "id": id,
            "tools": reply.toolTrace,
            "note": reply.noteProposal != nil,
            "relation": reply.relationProposal != nil,
            "profile": reply.courseProfileUpdate != nil,
            "backend": reply.backend.rawValue,
        ]
    }

    private static func cancelRow() async throws -> [String: Any] {
        let adapter = PairScriptedAdapter(chunks: [
            [.textDelta(index: 0, text: "很长的解释")],
        ], hangAfterFirstChunk: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pair-\(UUID().uuidString)")
        let runtime = NativeStudyAgentRuntime(model: "mock", adapter: adapter, ledgerRoot: root, systemPromptText: "you are webi")
        let task = Task {
            try await runtime.respond(
                to: StudyAgentRequest(
                    purpose: .conversation,
                    question: "请详细解释",
                    materialTitle: "",
                    materialText: "",
                    noteTitle: "",
                    noteText: "",
                    contextRevision: "pair"
                ),
                progress: nil
            )
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        await runtime.cancel()
        do {
            _ = try await task.value
            throw NSError(domain: "WeiBei.Pair", code: 6, userInfo: [NSLocalizedDescriptionKey: "09-cancel should throw"])
        } catch {
            let kind = AgentFailureKind.classify(error)
            guard kind == .cancelled else { throw error }
        }
        print("native-scenario-pair 09-cancel cancelled=true")
        return ["id": "09-cancel", "tools": [], "cancelled": true]
    }

    private static func unauthorizedRow() async throws -> [String: Any] {
        let adapter = PairFailingAdapter()
        do {
            _ = try await respond(question: "hi", chunks: [], adapter: adapter)
            throw NSError(domain: "WeiBei.Pair", code: 7, userInfo: [NSLocalizedDescriptionKey: "10-unauthorized should throw"])
        } catch {
            let kind = AgentFailureKind.classify(error)
            let text = error.localizedDescription
            guard kind == .unauthorized || text.contains("认证") || text.contains("401") else { throw error }
            print("native-scenario-pair 10-unauthorized kind=\(kind.rawValue)")
            return ["id": "10-unauthorized", "failureKind": kind.rawValue]
        }
    }

    private static func respond(
        question: String,
        chunks: [[NativeStreamChunk]],
        host: StudyAgentHostToolHandler? = nil,
        visualURL: URL? = nil,
        chatID: String = UUID().uuidString.lowercased(),
        adapter: NativeLLMAdapter? = nil
    ) async throws -> StudyAgentReply {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pair-\(chatID)", isDirectory: true)
        let runtime = NativeStudyAgentRuntime(
            model: "mock",
            adapter: adapter ?? PairScriptedAdapter(chunks: chunks),
            ledgerRoot: root,
            systemPromptText: "you are webi",
            hostToolHandler: host
        )
        var assets: [StudyAgentVisualAsset] = []
        if let visualURL {
            assets = [StudyAgentVisualAsset(id: "asset-1", filePath: visualURL.path, mediaType: "image/png")]
        }
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
                    chatID: chatID,
                    courseID: UUID().uuidString.lowercased()
                ),
                visualAssets: assets,
                contextRevision: "pair"
            ),
            progress: nil
        )
    }
}

private final class PairScriptedAdapter: NativeLLMAdapter, @unchecked Sendable {
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

private struct PairFailingAdapter: NativeLLMAdapter {
    var family: String { "scripted" }
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: NativeLLMFailure(code: "unauthorized", status: 401, message: "invalid"))
        }
    }
}
