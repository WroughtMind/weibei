import Foundation
import WeiBeiCore

func runPiAgentSelfChecks() throws {
    try checkJSONLFraming()
    try checkRPCDecoding()
    try checkStudyAgentContext()
    try checkBundledAgentResources()
    try checkPiExecutableLocation()
}

private func piRequire(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw PiAgentSelfCheckError.failed(message) }
}

private func checkJSONLFraming() throws {
    let delta = "中文跨字节\u{2028}仍在同一条 JSON 记录"
    let first = #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"中文跨字节 仍在同一条 JSON 记录"}}"#
    let second = #"{"type":"tool_execution_start","toolCallId":"tool-1","toolName":"weibei_context"}"#
    var framer = PiJSONLFramer()
    var records: [Data] = []
    for byte in Data("\(first)\r\n\(second)\n".utf8) {
        records.append(contentsOf: try framer.append(Data([byte])))
    }
    _ = try framer.finish()
    try piRequire(records.count == 2, "PI JSONL keeps CRLF compatibility and emits two records")
    try piRequire(PiRPCMessageDecoder.decode(records[0]) == .textDelta(delta), "PI JSONL preserves split UTF-8 and U+2028")
    try piRequire(PiRPCMessageDecoder.decode(records[1]) == .toolStarted(id: "tool-1", name: "weibei_context"), "PI JSONL preserves tool ids")

    var incomplete = PiJSONLFramer()
    _ = try incomplete.append(Data("{\"type\":\"event\"}".utf8))
    do {
        _ = try incomplete.finish()
        throw PiAgentSelfCheckError.failed("PI JSONL accepted an unterminated record")
    } catch let error as PiRPCProtocolError {
        try piRequire(error == .incompleteLine, "PI JSONL rejects an unterminated record")
    }

    var bounded = PiJSONLFramer(maximumLineBytes: 3)
    do {
        _ = try bounded.append(Data("four".utf8))
        throw PiAgentSelfCheckError.failed("PI JSONL accepted an oversized record")
    } catch let error as PiRPCProtocolError {
        try piRequire(error == .lineTooLarge(4), "PI JSONL enforces its byte limit")
    }
}

private func checkRPCDecoding() throws {
    let state = try PiRPCMessageDecoder.decode(Data(#"{"id":"state-1","type":"response","command":"get_state","success":true,"data":{"isStreaming":false}}"#.utf8))
    guard case let .response(response) = state else {
        throw PiAgentSelfCheckError.failed("PI get_state response did not decode")
    }
    try piRequire(response.id == "state-1" && response.command == "get_state" && response.success && response.dataJSON != nil, "PI get_state keeps correlation and data")

    let rejection = try PiRPCMessageDecoder.decode(Data(#"{"id":"prompt-1","type":"response","command":"prompt","success":false,"error":"busy"}"#.utf8))
    try piRequire(rejection == .response(PiRPCResponse(id: "prompt-1", command: "prompt", success: false, error: "busy")), "PI rejected commands keep their errors")

    let failedTool = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-2","toolName":"weibei_context","isError":true,"result":{"content":[{"type":"text","text":"stale context"}]}}"#.utf8))
    try piRequire(failedTool == .toolFailed(id: "tool-2", name: "weibei_context", message: "stale context"), "PI tool failures keep ids and messages")

    let contextRead = try PiRPCMessageDecoder.decode(Data(#"{"type":"tool_execution_end","toolCallId":"tool-context","toolName":"weibei_context","isError":false,"result":{"details":{"kind":"weibei_context","contextRevision":"revision-7"}}}"#.utf8))
    try piRequire(contextRead == .contextRead(id: "tool-context", contextRevision: "revision-7"), "PI context reads preserve the validated revision")

    let proposalData = try JSONSerialization.data(withJSONObject: [
        "type": "tool_execution_end",
        "toolCallId": "tool-3",
        "toolName": "weibei_note_proposal",
        "isError": false,
        "result": [
            "content": [["type": "text", "text": "accepted"]],
            "details": [
                "kind": "note_proposal",
                "markdown": "## 核心要点\n- 利率是资金价格。",
                "evidence": ["[选区：利率定义]"],
                "contextRevision": "revision-7",
            ],
        ],
    ])
    let proposal = try PiRPCMessageDecoder.decode(proposalData)
    try piRequire(
        proposal == .noteProposal(
            id: "tool-3",
            StudyAgentNoteProposal(
                markdown: "## 核心要点\n- 利率是资金价格。",
                evidence: ["[选区：利率定义]"],
                contextRevision: "revision-7"
            )
        ),
        "PI note proposals preserve Markdown, evidence, and revision"
    )

    let ended = try PiRPCMessageDecoder.decode(Data(#"{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"第一轮"}],"stopReason":"toolUse"},{"role":"assistant","content":[{"type":"text","text":"最终回答"}],"stopReason":"stop"}]}"#.utf8))
    try piRequire(ended == .agentEnded(text: "最终回答", stopReason: "stop"), "PI agent_end selects the final assistant answer")
    try piRequire(try PiRPCMessageDecoder.decode(Data(#"{"type":"future_event"}"#.utf8)) == .event("future_event"), "PI decoder tolerates unknown future events")

    do {
        _ = try PiRPCMessageDecoder.decode(Data("not-json".utf8))
        throw PiAgentSelfCheckError.failed("PI decoder accepted invalid JSON")
    } catch let error as PiRPCProtocolError {
        try piRequire(error == .invalidJSON, "PI decoder rejects invalid JSON")
    }
}

private func checkStudyAgentContext() throws {
    let recentMessages = (0..<10).map { index in
        AgentMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: "message-\(index)" + String(repeating: "字", count: 1_300), source: "source-\(index)")
    }
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "请根据当前材料出题",
        materialTitle: String(repeating: "材", count: 320),
        materialText: String(repeating: "材", count: 18_100),
        noteTitle: String(repeating: "记", count: 320),
        noteText: String(repeating: "记", count: 6_100),
        selectionTitle: String(repeating: "选", count: 320),
        selectionText: String(repeating: "选", count: 2_100),
        recentMessages: recentMessages,
        language: .chinese,
        contextRevision: "revision-9"
    )
    try piRequire(request.resolvedWorkflow == .recallPractice, "study-agent automatic routing selects recall practice")
    let noteRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "整理成笔记",
        materialTitle: "材料",
        materialText: "正文",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-10"
    )
    try piRequire(noteRequest.resolvedWorkflow == .noteMaking, "study-agent automatic routing selects note making")
    let quietRequest = StudyAgentRequest(
        purpose: .quietInsight,
        question: "出题",
        materialTitle: "材料",
        materialText: "正文",
        noteTitle: "笔记",
        noteText: "",
        contextRevision: "revision-11"
    )
    try piRequire(quietRequest.resolvedWorkflow == .closeReading, "quiet insight stays on close reading")

    let envelope = StudyAgentContextEnvelope(request: request)
    try piRequire(envelope.schemaVersion == 1 && envelope.contextRevision == "revision-9", "study-agent context carries schema and revision")
    try piRequire(envelope.workflow == StudyAgentWorkflow.recallPractice.rawValue, "study-agent context carries resolved workflow")
    try piRequire(envelope.material?.text.count == 18_000 && envelope.note.text.count == 6_000 && envelope.selection?.text.count == 2_000, "study-agent context applies source limits")
    try piRequire(envelope.material?.title.count == 300 && envelope.note.title.count == 300 && envelope.selection?.title.count == 300, "study-agent context bounds source labels consistently")
    try piRequire(envelope.material?.isTruncated == true && envelope.note.isTruncated && envelope.selection?.isTruncated == true, "study-agent context marks every truncated source")
    try piRequire(envelope.recentMessages.count == 8 && envelope.recentMessages.first?.text.hasPrefix("message-2") == true, "study-agent context keeps the latest eight messages")
    try piRequire(envelope.recentMessages.allSatisfy { $0.text.count <= 1_200 }, "study-agent context bounds recent messages")

    let message = AgentMessage(role: .assistant, text: "PI answer", source: "材料", backend: .pi)
    let encoded = try JSONEncoder().encode(message)
    try piRequire(try JSONDecoder().decode(AgentMessage.self, from: encoded).backend == .pi, "agent backend round-trips")
    var legacyObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    legacyObject.removeValue(forKey: "backend")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    try piRequire(try JSONDecoder().decode(AgentMessage.self, from: legacyData).backend == nil, "legacy agent messages remain decodable")

    try piRequire(PiAgentRuntimeError.unavailable.permitsAutomaticFallback, "PI startup failures may use the existing fallback")
    try piRequire(!PiAgentRuntimeError.agentFailed("model error").permitsAutomaticFallback, "accepted PI runs are never replayed automatically")
    try piRequire(!PiAgentRuntimeError.commandTimedOut("prompt").permitsAutomaticFallback, "unknown prompt acceptance is never replayed automatically")

    let diagnostic = PiAgentDiagnosticSanitizer.sanitize(
        #"Authorization: Bearer abcdefghijklmnop api_key="sk-sensitive-token""#,
        secret: "sk-sensitive-token"
    )
    try piRequire(
        diagnostic.contains("[REDACTED]")
            && !diagnostic.contains("abcdefghijklmnop")
            && !diagnostic.contains("sk-sensitive-token"),
        "PI diagnostics redact provider credentials before reaching logs or UI"
    )
}

private func checkBundledAgentResources() throws {
    let resources = try PiAgentResources.bundled()
    try piRequire(resources.systemPrompt.contains("魏碑拥有材料、选区、笔记"), "PI system contract is bundled")
    let extensionSource = try String(contentsOf: resources.extensionURL, encoding: .utf8)
    try piRequire(extensionSource.contains("before_agent_start") && extensionSource.contains("tool_call") && extensionSource.contains("pi.on(\"context\""), "PI extension bundles source, permission, and stale-context hooks")
    try piRequire(extensionSource.contains("weibei_context") && extensionSource.contains("weibei_note_proposal"), "PI extension bundles only WeiBei-owned tools")

    for skillName in PiAgentResources.requiredSkillNames {
        let skillURL = resources.skillsURL.appendingPathComponent(skillName).appendingPathComponent("SKILL.md")
        let source = try String(contentsOf: skillURL, encoding: .utf8)
        try piRequire(source.contains("name: \(skillName)") && source.contains("description:"), "PI skill \(skillName) has valid frontmatter")
    }

    let runtimeSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/WeiBeiCore/PiAgentRuntime.swift")
    let runtimeSource = try String(contentsOf: runtimeSourceURL, encoding: .utf8)
    try piRequire(
        runtimeSource.contains("answeredBeforeContext")
            && runtimeSource.contains("allowedSourceLabels")
            && runtimeSource.contains("PI returned an answer without a current-source label")
            && runtimeSource.contains("binary.sha256")
            && runtimeSource.contains("SecStaticCodeCheckValidity"),
        "PI host enforces context-first answers, source labels, binary integrity, and code signatures"
    )
}

private func checkPiExecutableLocation() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("weibei-pi-locator-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    func makeExecutable(_ url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    let bundleURL = root.appendingPathComponent("WeiBei.app", isDirectory: true)
    let runtimeURL = bundleURL.appendingPathComponent("Contents/Resources/PiRuntime", isDirectory: true)
    let executableURL = runtimeURL.appendingPathComponent("bin/pi")
    try makeExecutable(executableURL)

    try piRequire(
        PiExecutableLocator.locate(
            bundleURL: bundleURL,
            fileManager: fileManager,
            validator: { candidate, _ in candidate.standardizedFileURL == executableURL.standardizedFileURL }
        )?.standardizedFileURL == executableURL.standardizedFileURL,
        "PI executable locator resolves the app-bundled runtime path"
    )
    try piRequire(
        PiExecutableLocator.locate(bundleURL: bundleURL, fileManager: fileManager) == nil,
        "PI executable locator rejects a bundled runtime that fails integrity validation"
    )

    let externalPi = root.appendingPathComponent(".nvm/versions/node/v24.13.0/bin/pi")
    try makeExecutable(externalPi)
    let emptyBundle = root.appendingPathComponent("Empty.app", isDirectory: true)
    try piRequire(
        PiExecutableLocator.locate(
            bundleURL: emptyBundle,
            fileManager: fileManager,
            validator: { _, _ in true }
        ) == nil,
        "PI executable locator never falls back to a user-installed runtime"
    )

    let preparedRuntime = ProcessInfo.processInfo.environment["WEIBEI_PI_EXECUTABLE"]?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !preparedRuntime.isEmpty {
        let manifest = try PiBundledRuntime.validate(executableURL: URL(fileURLWithPath: preparedRuntime))
        try piRequire(manifest.piVersion == PiBundledRuntime.requiredVersion, "PI runtime validation pins binary integrity and version")
    }
}

private enum PiAgentSelfCheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}
