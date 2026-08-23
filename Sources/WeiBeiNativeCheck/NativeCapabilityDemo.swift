import Foundation
import WeiBeiCore

enum NativeCapabilityDemo {
    static func runIfRequested(arguments: [String]) async -> Bool {
        guard arguments.contains("--native-capability-demo") else { return false }
        do {
            try await run()
            print("native-capability-demo passed: skills, create_document, delegate")
        } catch {
            fputs("native-capability-demo failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        return true
    }

    static func run() async throws {
        let skillRoot = try AgentResources.bundled().skillsURL
        let registry = try NativeSkillRegistry.load(from: skillRoot)
        let before = registry.catalogSummary()
        guard registry.pack(named: "visualize") != nil, registry.pack(named: "socratic-questioning") != nil else {
            throw NSError(domain: "WeiBei.NativeDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected visualize and socratic-questioning"])
        }
        print("native-capability-demo catalog-before=\(registry.packs.map(\.id).joined(separator: ","))")

        let documents = FileManager.default.temporaryDirectory.appendingPathComponent("native-docs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let adapter = CapabilityScriptedAdapter(chunks: [
            [
                .toolCallDelta(index: 0, id: "s1", name: "load_skill", argumentsDelta: "{\"id\":\"socratic-questioning\"}"),
                .finish(reason: .toolCalls, replayState: nil),
            ],
            [
                .textDelta(index: 0, text: "只问一个问题：利息和利率差在哪？"),
                .finish(reason: .stop, replayState: nil),
            ],
        ])
        let skillReply = try await respond(
            question: "请加载苏格拉底追问技能，然后问我一个问题。",
            adapter: adapter,
            mode: .assistant,
            liveStores: NativeLiveStores(documentsRoot: documents, skillRegistry: registry)
        )
        guard skillReply.loadedSkills.contains(where: { $0.id == "socratic-questioning" }) else {
            throw NSError(domain: "WeiBei.NativeDemo", code: 2, userInfo: [NSLocalizedDescriptionKey: "load_skill did not record the skill"])
        }
        let after = try NativeSkillRegistry.load(from: skillRoot).catalogSummary()
        guard before == after else {
            throw NSError(domain: "WeiBei.NativeDemo", code: 3, userInfo: [NSLocalizedDescriptionKey: "load_skill changed the catalog"])
        }
        print("native-capability-demo skill-style-prefix=\(skillReply.text.prefix(40))")

        let created = try NativeDocumentSandbox.write(
            title: "利率笔记",
            format: .markdown,
            content: "# 利率\n利率是资金使用价格。",
            documentsRoot: documents
        )
        guard FileManager.default.fileExists(atPath: created.fileURL.path),
              FileManager.default.fileExists(atPath: created.viewerURL.path),
              try String(contentsOf: created.viewerURL, encoding: .utf8).contains("Content-Security-Policy") else {
            throw NSError(domain: "WeiBei.NativeDemo", code: 4, userInfo: [NSLocalizedDescriptionKey: "document viewer missing sandbox"])
        }
        print("native-capability-demo document=\(created.fileURL.lastPathComponent)")

        let delegateAdapter = CapabilityScriptedAdapter(chunks: [
            [
                .textDelta(index: 0, text: "子任务完成：先定义，再举一例。"),
                .finish(reason: .stop, replayState: nil),
            ],
        ])
        let child = await NativeSubagentRunner.start(
            NativeSubagentRequest(task: "用一句话说明利率。", capabilities: [.hostTools], depth: 1),
            adapter: delegateAdapter,
            model: "mock",
            systemPrompt: "you are webi",
            ledgerRoot: documents.appendingPathComponent("ledgers", isDirectory: true),
            hostToolHandler: nil,
            liveStores: NativeLiveStores(skillRegistry: registry)
        )
        guard child.ok, child.text.contains("利率") || child.text.contains("子任务") else {
            throw NSError(domain: "WeiBei.NativeDemo", code: 5, userInfo: [NSLocalizedDescriptionKey: "delegate round failed"])
        }
        print("native-capability-demo delegate-prefix=\(child.text.prefix(40))")

        let hidden = try await respond(
            question: "请把讲义写成文稿。",
            adapter: CapabilityScriptedAdapter(chunks: [
                [
                    .toolCallDelta(index: 0, id: "d1", name: "create_document", argumentsDelta: "{\"title\":\"x\",\"format\":\"markdown\",\"content\":\"hi\"}"),
                    .finish(reason: .toolCalls, replayState: nil),
                ],
                [.textDelta(index: 0, text: "Assistant 模式不能写文稿。"), .finish(reason: .stop, replayState: nil)],
            ]),
            mode: .assistant,
            liveStores: NativeLiveStores(documentsRoot: documents, skillRegistry: registry)
        )
        guard !hidden.toolTrace.contains("create_document") || hidden.text.contains("不能") else {
            throw NSError(domain: "WeiBei.NativeDemo", code: 6, userInfo: [NSLocalizedDescriptionKey: "assistant mode must hide create_document"])
        }
    }

    private static func respond(
        question: String,
        adapter: NativeLLMAdapter,
        mode: NativeAgentMode,
        liveStores: NativeLiveStores
    ) async throws -> StudyAgentReply {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-cap-\(UUID().uuidString)")
        let runtime = NativeStudyAgentRuntime(
            model: "mock",
            adapter: adapter,
            ledgerRoot: root,
            systemPromptText: "you are webi",
            hostToolHandler: nil,
            liveStores: liveStores,
            mode: mode
        )
        return try await runtime.respond(
            to: StudyAgentRequest(
                purpose: .conversation,
                question: question,
                materialTitle: "",
                materialText: "",
                noteTitle: "",
                noteText: "",
                contextRevision: "capability-demo"
            ),
            progress: nil
        )
    }
}

private final class CapabilityScriptedAdapter: NativeLLMAdapter, @unchecked Sendable {
    var family: String { "scripted" }
    private let chunks: [[NativeStreamChunk]]
    private var step = 0
    private let lock = NSLock()

    init(chunks: [[NativeStreamChunk]]) {
        self.chunks = chunks
    }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            let index = min(step, max(chunks.count - 1, 0))
            let current = chunks.isEmpty ? [] : chunks[index]
            step += 1
            lock.unlock()
            for chunk in current {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
