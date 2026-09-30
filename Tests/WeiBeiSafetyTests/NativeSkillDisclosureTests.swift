import XCTest
@testable import WeiBeiCore

final class NativeSkillDisclosureTests: XCTestCase {
    private let taskIDs = [
        "web-research", "web-reading", "course-search", "close-reading", "source-synthesis",
        "note-writing", "discussion-recall", "learning-memory", "practice-feedback",
    ]

    func testBundledWorkflowsAndLinkedReferencesLoadIndependently() async throws {
        let packs = try NativeSkillRegistry.load(from: AgentResources.bundled().skillsURL)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let toolNames = await registry.resolved(scope: .global).map(\.name)
        let links = try NSRegularExpression(pattern: #"\]\((references/[^)]+\.md)\)"#)
        var context = NativeToolExecutionContext(request: request(), liveStores: NativeLiveStores(skillRegistry: packs))

        for id in taskIDs {
            let pack = try XCTUnwrap(packs.pack(named: id))
            XCTAssertTrue(packs.catalogSummary().contains(pack.manifest.description))
            XCTAssertFalse(packs.catalogSummary().contains(pack.body))
            let entry = try await load(id, context: context, registry: registry)
            XCTAssertEqual(entry.text, pack.body)
            context.loadedSkillIDs.insert(id)
            let repeatedEntry = try await load(id, context: context, registry: registry)
            XCTAssertEqual(repeatedEntry.details["alreadyLoaded"] as? Bool, true)

            let matches = links.matches(in: pack.body, range: NSRange(pack.body.startIndex..., in: pack.body))
            XCTAssertFalse(matches.isEmpty, "\(id) must route to its task-specific references")
            var referencedPaths: Set<String> = []
            for match in matches {
                let path = String(pack.body[try XCTUnwrap(Range(match.range(at: 1), in: pack.body))])
                referencedPaths.insert(path)
                let resource = try pack.reference(named: path)
                XCTAssertFalse(entry.text.contains(resource.body))
                XCTAssertFalse(packs.catalogSummary().contains(resource.body))
                let result = try await load(id, resource: path, context: context, registry: registry)
                XCTAssertEqual(result.text, resource.body)
                XCTAssertNotEqual(result.details["alreadyLoaded"] as? Bool, true)
                let metadata = try XCTUnwrap(result.details["loaded"] as? [String: Any])
                XCTAssertEqual(metadata["id"] as? String, resource.id)
                XCTAssertEqual(metadata["relativePath"] as? String, "skills/\(id)/\(path)")
                XCTAssertEqual(metadata["byteCount"] as? Int, result.text.utf8.count)
                XCTAssertEqual(metadata["sha256"] as? String, resource.sha256)
                XCTAssertNotEqual(resource.id, id)
                context.loadedSkillIDs.insert(resource.id)
                let repeated = try await load(id, resource: path, context: context, registry: registry)
                XCTAssertEqual(repeated.details["alreadyLoaded"] as? Bool, true)
                XCTAssertLessThan(repeated.text.count, result.text.count)
            }
            let files = try FileManager.default.contentsOfDirectory(
                at: try XCTUnwrap(pack.directoryURL).appendingPathComponent("references"),
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "md" }.map { "references/" + $0.lastPathComponent }
            XCTAssertEqual(Set(files), referencedPaths, "Every shipped reference must be discoverable from its workflow")
        }
        let after = await registry.resolved(scope: .global).map(\.name)
        XCTAssertEqual(after, toolNames, "Loading instructions must not add permissions or tools")
    }

    func testReferenceReaderRejectsTraversalAndSymlinkEscapesWithoutReturningTheEntrypoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skill-boundary-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = root.appendingPathComponent("example")
        let references = skill.appendingPathComponent("references")
        try FileManager.default.createDirectory(at: references, withIntermediateDirectories: true)
        try "# Local reference\nOnly this body".write(to: references.appendingPathComponent("valid.md"), atomically: true, encoding: .utf8)
        let outside = root.appendingPathComponent("outside.md")
        try "Never disclose this fixture".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: references.appendingPathComponent("escape.md"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: references.appendingPathComponent("linked"), withDestinationURL: root)
        let pack = NativeSkillPack(
            manifest: NativeSkillManifest(id: "example", name: "示例", version: "1", description: "示例用途"),
            body: "Entrypoint is not a substitute for a failed resource", relativePath: "skills/example/SKILL.md",
            sha256: "fixture", directoryURL: skill
        )
        XCTAssertEqual(try pack.reference(named: "references/valid.md").body, "# Local reference\nOnly this body")
        for path in ["../outside.md", outside.path, "references/../../outside.md", "references/./valid.md",
                     "references//valid.md", "references\\valid.md", "references/valid.txt", "references/escape.md",
                     "references/linked/outside.md", "SKILL.md"] {
            XCTAssertThrowsError(try pack.reference(named: path), path) { error in
                XCTAssertEqual((error as? NativeLLMFailure)?.code, "skill_resource_invalid", path)
            }
        }
        XCTAssertThrowsError(try pack.reference(named: "references/missing.md")) { error in
            XCTAssertEqual((error as? NativeLLMFailure)?.code, "skill_resource_missing")
        }
    }

    func testNativeLoopDisclosesOnlyRequestedStagesAndRecordsEachResource() async throws {
        let packs = try NativeSkillRegistry.load(from: AgentResources.bundled().skillsURL)
        let pack = try XCTUnwrap(packs.pack(named: "web-research"))
        let comparison = try pack.reference(named: "references/comparison.md")
        let events = try pack.reference(named: "references/current-events.md")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skill-loop-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let result = try await NativeAgentLoop().run(
            request: request(), ledger: ledger, registry: registry,
            adapter: DisclosureAdapter(entry: pack.body, comparison: comparison.body, events: events.body),
            model: "mock", hostToolHandler: nil, systemPrompt: packs.catalogSummary(),
            liveStores: NativeLiveStores(skillRegistry: packs), progress: nil
        )
        XCTAssertEqual(result.text, "完成")
        XCTAssertEqual(Set(result.loadedSkills.map(\.id)), [pack.id, comparison.id, events.id])
        let messages = await ledger.deriveMessages().filter { $0.role == .tool }
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0].content, pack.body)
        XCTAssertEqual(messages[1].content, comparison.body)
        XCTAssertEqual(messages[2].content, events.body)
        XCTAssertLessThan(messages[3].content.count, comparison.body.count)
    }

    private func request() -> StudyAgentRequest {
        StudyAgentRequest(purpose: .conversation, question: "核对公开统计的口径与时间", materialTitle: "",
            materialText: "", noteTitle: "", noteText: "", contextRevision: "skill-test")
    }

    func testCompressedReferenceCanBeLoadedAgain() async throws {
        let packs = try NativeSkillRegistry.load(from: AgentResources.bundled().skillsURL)
        let resource = try XCTUnwrap(packs.pack(named: "web-research")).reference(named: "references/comparison.md")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skill-compaction-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        _ = try await NativeAgentLoop().run(request: request(), ledger: ledger, registry: registry,
            adapter: CompressedSkillAdapter(reference: resource.body), model: "mock", hostToolHandler: nil,
            systemPrompt: packs.catalogSummary(), liveStores: NativeLiveStores(skillRegistry: packs), progress: nil)
        let events = await ledger.allEvents()
        XCTAssertTrue(events.contains { $0.type == .contextCompaction })
        let results = events.filter { $0.type == .toolResult }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.text), [resource.body, resource.body])
    }

    private func load(_ id: String, resource: String? = nil, context: NativeToolExecutionContext,
                      registry: NativeToolRegistry) async throws -> NativeToolExecutionResult {
        var arguments = ["id": id]
        if let resource { arguments["resource"] = resource }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
        return try await registry.execute(NativeToolCallRequest(name: "load_skill", argumentsJSON: json, callID: UUID().uuidString),
                                          context: context, scope: .global)
    }
}

private struct CompressedSkillAdapter: NativeLLMAdapter {
    let family = "mock"
    let contextWindow: Int? = 10_000
    let reference: String

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            if request.purpose == .compaction {
                continuation.yield(.textDelta(index: 0, text: "技能细节已压缩，需要时重新读取。"))
                continuation.yield(.finish(reason: .stop, replayState: nil))
            } else {
                let compressed = request.messages.contains { $0.content.contains("技能细节已压缩") }
                let results = request.messages.filter { $0.role == .tool }
                if compressed && !results.isEmpty {
                    XCTAssertEqual(results.last?.content, reference)
                    continuation.yield(.textDelta(index: 0, text: "完成"))
                    continuation.yield(.finish(reason: .stop, replayState: nil))
                } else {
                    if compressed { XCTAssertFalse(request.messages.contains { $0.content.contains(reference) }) }
                    continuation.yield(.toolCallDelta(index: 0, id: compressed ? "reload" : "first", name: "load_skill",
                        argumentsDelta: #"{"id":"web-research","resource":"references/comparison.md"}"#))
                    continuation.yield(.usage(NativeTokenUsage(inputTokens: compressed ? 1 : 9_000)))
                    continuation.yield(.finish(reason: .toolCalls, replayState: nil))
                }
            }
            continuation.finish()
        }
    }
}

private struct DisclosureAdapter: NativeLLMAdapter {
    let family = "mock"
    let entry: String
    let comparison: String
    let events: String

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        let results = request.messages.filter { $0.role == .tool }
        if results.isEmpty {
            XCTAssertFalse(request.messages.contains { $0.content.contains(entry) || $0.content.contains(comparison) || $0.content.contains(events) })
        } else if results.count == 1 {
            XCTAssertEqual(results[0].content, entry)
            XCTAssertFalse(request.messages.contains { $0.content.contains(comparison) || $0.content.contains(events) })
        } else if results.count == 2 {
            XCTAssertEqual(results[1].content, comparison)
            XCTAssertFalse(request.messages.contains { $0.content.contains(events) })
        }
        let calls = [
            #"{"id":"web-research"}"#,
            #"{"id":"web-research","resource":"references/comparison.md"}"#,
            #"{"id":"web-research","resource":"references/current-events.md"}"#,
            #"{"id":"web-research","resource":"references/comparison.md"}"#,
        ]
        return AsyncThrowingStream { continuation in
            if results.count < calls.count {
                continuation.yield(.toolCallDelta(index: 0, id: "skill-\(results.count)", name: "load_skill", argumentsDelta: calls[results.count]))
                continuation.yield(.finish(reason: .toolCalls, replayState: nil))
            } else {
                continuation.yield(.textDelta(index: 0, text: "完成"))
                continuation.yield(.finish(reason: .stop, replayState: nil))
            }
            continuation.finish()
        }
    }
}
