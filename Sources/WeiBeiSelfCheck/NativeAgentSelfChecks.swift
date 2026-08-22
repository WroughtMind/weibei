import Foundation
import WeiBeiCore

func runNativeAgentSelfChecks() throws {
    try checkSSEFraming()
    try checkToolCallAssembly()
    try checkIncompleteArgumentsRejected()
    try checkLedgerRoundTrip()
    try checkCrashCloser()
    try checkCredentialFile()
    try checkFailureMapping()
    try checkOAuthPKCEAndAuthorizeURL()
    try checkResponsesWebSearchPayload()
    try checkResponsesTranslation()
    try checkAnthropicTranslation()
    try checkGeminiTranslation()
    try checkOAuthLogoutLeavesNoCredential()
    try checkProviderRouting()
    try checkSkillCatalogAndLoad()
    try checkCreateDocumentSandbox()
    try checkDelegateCapabilities()
    try checkEvalSetLunaLow()
}

private func nativeRequire(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }
}

private func checkSSEFraming() throws {
    var framer = NativeSSEFramer()
    let split = "data: {\"id\":\"".data(using: .utf8)! + Data([0xE6]) // split UTF-8 lead
    let first = try framer.append(split)
    try nativeRequire(first.isEmpty, "incomplete UTF-8 stays buffered")
    let rest = Data([0xB1, 0x89]) + "\"}\n".data(using: .utf8)!
    let second = try framer.append(rest)
    try nativeRequire(second.count == 1 && second[0].contains("id"), "UTF-8 split SSE line reassembles")

    var crlf = NativeSSEFramer()
    let lines = try crlf.append(Data("data: {\"a\":1}\r\ndata: {\"b\":2}\n".utf8))
    try nativeRequire(lines == ["{\"a\":1}", "{\"b\":2}"], "CRLF SSE lines parse")

    var capped = NativeSSEFramer(maximumLineBytes: 16)
    do {
        _ = try capped.append(Data(repeating: 0x61, count: 32))
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "oversize SSE line should throw",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "sse_line_too_large", "oversize SSE line maps to sse_line_too_large")
    }
}

private func checkToolCallAssembly() throws {
    var assembler = NativeToolCallAssembler()
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: "weibei_course_search", argumentsDelta: "{\"query\":"))
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: nil, argumentsDelta: "\"利率\"}"))
    let calls = try assembler.completedCalls()
    try nativeRequire(calls.count == 1 && calls[0].name == "weibei_course_search", "tool call fragments assemble")
}

private func checkIncompleteArgumentsRejected() throws {
    var assembler = NativeToolCallAssembler()
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: "weibei_course_search", argumentsDelta: "{\"query\":\"利率\""))
    do {
        _ = try assembler.completedCalls()
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "incomplete JSON should refuse execution",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "incomplete_tool_arguments", "incomplete tool JSON is refused")
    }
}

private func checkLedgerRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-ledger-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let ledger = try NativeAgentLedger(fileURL: url)
    _ = try waitFor { try await ledger.append { seq, time in
        NativeSessionEvent(type: .turnStart, seq: seq, timeMS: time, turn: 1)
    } }
    _ = try waitFor { try await ledger.append { seq, time in
        NativeSessionEvent(type: .userMessage, seq: seq, timeMS: time, turn: 1, text: "利率是什么")
    } }
    _ = try waitFor { try await ledger.append { seq, time in
        NativeSessionEvent(type: .assistantMessage, seq: seq, timeMS: time, turn: 1, text: "资金的价格")
    } }
    try waitFor { try await ledger.closeTurn(turn: 1, reason: .completed) }
    let reloaded = try NativeAgentLedger(fileURL: url)
    let messages = try waitFor { await reloaded.deriveMessages() }
    try nativeRequire(messages.count == 2, "ledger round-trip keeps user and assistant")
    try nativeRequire(messages[0].content == "利率是什么", "user message survives reload")
}

private func checkCrashCloser() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-closer-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let ledger = try NativeAgentLedger(fileURL: url)
    _ = try waitFor { try await ledger.append { seq, time in
        NativeSessionEvent(type: .userMessage, seq: seq, timeMS: time, turn: 1, text: "hi")
    } }
    try waitFor { try await ledger.synthesizeCloserIfNeeded() }
    let events = try waitFor { await ledger.allEvents() }
    try nativeRequire(events.last?.type == .closer, "crash closer is synthesized")
    try nativeRequire(events.last?.timeMS == events.first?.timeMS, "closer reuses last real timestamp")
}

private func checkCredentialFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-cred-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
    }
    let store = NativeAgentCredentialStore(fileURL: url)
    try store.upsert(NativeAgentCredentialRecord(provider: "deepseek", apiKey: "sk-test"))
    try store.upsert(NativeAgentCredentialRecord(provider: "deepseek", apiKey: "sk-test"))
    try nativeRequire(try store.posixPermissions() == 0o600, "credential file is 0600")
    try Data("{".utf8).write(to: url, options: .atomic)
    let restored = try store.load()
    try nativeRequire(restored["deepseek"]?.apiKey == "sk-test", "corrupt credential file restores from backup")
}

private func checkOAuthPKCEAndAuthorizeURL() throws {
    let pkce = NativeOpenAIOAuth.makePKCE(entropy: Data(repeating: 7, count: 64))
    try nativeRequire(pkce.verifier.count >= 43 && pkce.challenge.count >= 43, "PKCE verifier/challenge are long enough")
    try nativeRequire(pkce.verifier != pkce.challenge, "PKCE challenge is not the verifier")
    let url = NativeOpenAIOAuth.authorizeURL(
        redirectURI: "http://localhost:1455/auth/callback",
        pkce: pkce,
        state: "abc"
    )
    let query = url.query ?? ""
    try nativeRequire(query.contains("code_challenge="), "authorize URL includes PKCE challenge")
    try nativeRequire(query.contains("client_id=\(NativeOpenAIOAuth.clientID)") || query.contains("client_id=app_"), "authorize URL includes Codex client id")
    try nativeRequire(url.host == "auth.openai.com", "authorize host is auth.openai.com")
    let code = NativeOpenAIOAuth.parseCallbackCode(
        fromHTTP: "GET /auth/callback?code=tok&state=abc HTTP/1.1\r\n",
        expectedState: "abc"
    )
    try nativeRequire(code == "tok", "callback parser reads code when state matches")
    try nativeRequire(
        NativeOpenAIOAuth.parseCallbackCode(
            fromHTTP: "GET /auth/callback?code=tok&state=nope HTTP/1.1\r\n",
            expectedState: "abc"
        ) == nil,
        "callback parser rejects state mismatch"
    )
}

private func checkResponsesWebSearchPayload() throws {
    let tools = [
        NativeToolDefinition(
            name: "weibei_course_map",
            description: "map",
            permission: .read,
            schema: NativeJSONSchema(["type": "object"]),
            execute: { _, _ in NativeToolExecutionResult(text: "") }
        ),
    ]
    let payload = OpenAIResponsesProvider.payload(
        for: NativeLLMRequest(model: "gpt-5.6-luna", messages: [
            NativeModelMessage(role: .user, content: "利率"),
        ], tools: tools, enableNativeWebSearch: true)
    )
    let encoded = payload["tools"] as? [[String: Any]] ?? []
    try nativeRequire(encoded.contains(where: { $0["type"] as? String == "web_search" }), "Responses payload adds web_search")
    let include = payload["include"] as? [String] ?? []
    try nativeRequire(include.contains("web_search_call.action.sources"), "Responses payload asks for search sources")
    try nativeRequire(include.contains("reasoning.encrypted_content"), "Responses payload keeps reasoning include")
}

private func checkResponsesTranslation() throws {
    let text = try OpenAIResponsesProvider.translate(
        #"{"type":"response.output_text.delta","output_index":0,"delta":"利率"}"#
    )
    try nativeRequire(text.first == .textDelta(index: 0, text: "利率"), "Responses text delta maps")
    let tool = try OpenAIResponsesProvider.translate(
        #"{"type":"response.output_item.added","output_index":1,"item":{"type":"function_call","call_id":"c1","name":"weibei_course_search"}}"#
    )
    try nativeRequire(tool.first == .toolCallDelta(index: 1, id: "c1", name: "weibei_course_search", argumentsDelta: ""), "Responses tool start maps")
}

private func checkAnthropicTranslation() throws {
    let text = try AnthropicMessagesProvider.translate(
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}}"#
    )
    try nativeRequire(text.first == .textDelta(index: 0, text: "hi"), "Anthropic text delta maps")
    let thinking = try AnthropicMessagesProvider.translate(
        #"{"type":"content_block_delta","index":1,"delta":{"type":"thinking_delta","thinking":"...","signature":"sig-1"}}"#
    )
    try nativeRequire(
        thinking.contains(where: { if case .reasoningDelta = $0 { return true }; return false }),
        "Anthropic thinking delta maps to reasoning"
    )
}

private func checkGeminiTranslation() throws {
    let chunks = try GoogleGenerativeAIProvider.translate(
        #"{"candidates":[{"content":{"parts":[{"text":"4"}]},"finishReason":"STOP"}]}"#
    )
    try nativeRequire(chunks.contains(.textDelta(index: 0, text: "4")), "Gemini text maps")
    try nativeRequire(chunks.contains(.finish(reason: .stop, replayState: nil)), "Gemini STOP finishes")
}

private func checkOAuthLogoutLeavesNoCredential() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-oauth-\(UUID().uuidString).json")
    let backup = url.appendingPathExtension("bak")
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: backup)
    }
    let store = NativeAgentCredentialStore(fileURL: url)
    try store.upsert(NativeAgentCredentialRecord(provider: "openai-codex", accessToken: "tok", refreshToken: "ref"))
    try store.upsert(NativeAgentCredentialRecord(provider: "openai-codex", accessToken: "tok-2", refreshToken: "ref-2"))
    try nativeRequire(FileManager.default.fileExists(atPath: backup.path), "second upsert keeps a bak")
    try waitFor {
        try await NativeOpenAIOAuth.logout(from: store)
    }
    try nativeRequire(try NativeOpenAIOAuth.leftoverCredentialExists(in: store) == false, "logout removes openai-codex")
    try nativeRequire(!FileManager.default.fileExists(atPath: backup.path), "logout scrubs bak leftover")
}

private func checkProviderRouting() throws {
    try nativeRequire(AgentProviderID.allCases.count == 40, "provider catalog stays at 40 unique cases")
    try nativeRequire(NativeProviderRouting.route(.deepseek).family == .openaiChatCompletions, "deepseek is chat completions")
    try nativeRequire(NativeProviderRouting.route(.openai).family == .openaiResponses, "openai API is Responses")
    try nativeRequire(NativeProviderRouting.route(.xai).family == .openaiResponses, "xAI is Responses")
    try nativeRequire(NativeProviderRouting.route(.anthropic).family == .anthropicMessages, "anthropic is Messages")
    try nativeRequire(NativeProviderRouting.route(.google).family == .googleGenerativeAI, "google is Gemini")
    try nativeRequire(NativeProviderRouting.route(.minimax).family == .anthropicMessages, "minimax follows Pi anthropic baseUrl")
    try nativeRequire(NativeProviderRouting.route(.moonshotaiCN).baseURL?.host == "api.moonshot.cn", "moonshot CN host")
    let uncovered = Set(NativeProviderRouting.uncoveredProviders)
    try nativeRequire(
        uncovered == [.azureOpenAI, .googleVertex, .amazonBedrock, .cloudflareAIGateway, .cloudflareWorkersAI],
        "uncovered families stay Azure/Vertex/Bedrock/Cloudflare"
    )
    for provider in AgentProviderID.allCases {
        let route = NativeProviderRouting.route(provider)
        if route.family == .unsupported {
            try nativeRequire(!route.note.isEmpty, "\(provider.rawValue) uncovered note")
        } else if route.auth != .userBaseURL {
            try nativeRequire(route.baseURL != nil, "\(provider.rawValue) has a base URL")
        }
    }
}

private func checkSkillCatalogAndLoad() throws {
    let root = try PiAgentResources.bundled().skillsURL
    let registry = try NativeSkillRegistry.load(from: root)
    try nativeRequire(registry.pack(named: "visualize") != nil, "visualize skill pack exists")
    try nativeRequire(registry.pack(named: "socratic-questioning") != nil, "socratic skill pack exists")
    try nativeRequire(registry.catalogSummary().contains("visualize"), "catalog lists visualize")
    let before = registry.packs.map(\.id)
    let loaded = registry.pack(named: "socratic-questioning")
    try nativeRequire(loaded?.body.contains("苏格拉底") == true, "socratic body loads")
    try nativeRequire(registry.packs.map(\.id) == before, "load is instruction-only and does not change registration")
    try nativeRequire(NativeSkillRegistry.isSignedBuiltin("visualize"), "visualize is a signed builtin")
}

private func checkCreateDocumentSandbox() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-doc-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let created = try NativeDocumentSandbox.write(
        title: "利率",
        format: .html,
        content: "<p>利率是资金使用价格。</p>",
        documentsRoot: root
    )
    let html = try String(contentsOf: created.viewerURL, encoding: .utf8)
    try nativeRequire(html.contains("Content-Security-Policy"), "viewer has CSP")
    try nativeRequire(html.contains("script-src 'none'"), "viewer denies script")
    try nativeRequire(FileManager.default.fileExists(atPath: created.fileURL.path), "source file exists")
}

private func checkDelegateCapabilities() throws {
    let unsupported = NativeSubagentCapabilities.parse(["nestedDelegate"])
    try nativeRequire(!NativeSubagentCapabilities.supported.contains(unsupported), "nestedDelegate is not silently allowed")
    try nativeRequire(NativeSubagentRunner.maximumDepth == 2, "delegate depth constant is 2")
    let result = try waitFor {
        await NativeSubagentRunner.start(
            NativeSubagentRequest(task: "x", capabilities: .nestedDelegate, depth: 1),
            adapter: OpenAIChatCompletionsProvider(apiKey: "invalid"),
            model: "mock",
            systemPrompt: "x",
            ledgerRoot: FileManager.default.temporaryDirectory,
            hostToolHandler: nil,
            liveStores: .empty
        )
    }
    try nativeRequire(result.ok == false, "unsupported capability fails as a value")
    try nativeRequire(result.text.contains("不受支持"), "capability failure is explained")
}

private func checkEvalSetLunaLow() throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Docs/audit/2026-08-22-native-agent-runtime-评测集.json")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    try nativeRequire(object?["model"] as? String == "gpt-5.6-luna", "eval set model is gpt-5.6-luna")
    try nativeRequire(object?["reasoningEffort"] as? String == "low", "eval set effort is low")
    let items = object?["items"] as? [[String: Any]] ?? []
    try nativeRequire(items.count >= 40, "eval set has at least 40 items")
}

private func checkFailureMapping() throws {
    try nativeRequire(NativeLLMFailure(code: "unauthorized", status: 401, message: "no").asAgentFailureKind == .unauthorized, "401 maps unauthorized")
    try nativeRequire(NativeLLMFailure(code: "rate_limited", status: 429, message: "slow").asAgentFailureKind == .rateLimited, "429 maps rateLimited")
    try nativeRequire(NativeLLMFailure(code: "timeout", message: "idle").asAgentFailureKind == .timedOut, "timeout maps timedOut")
    try nativeRequire(NativeLLMFailure(code: "cancelled", message: "stop").asAgentFailureKind == .cancelled, "cancel maps cancelled")
    let mapped = NSError(
        domain: "WeiBei.NativeAgent",
        code: 401,
        userInfo: [NSLocalizedDescriptionKey: "请求失败：认证已失效"]
    )
    try nativeRequire(AgentFailureKind.classify(mapped) == .unauthorized, "NativeAgent 401 + 认证已失效 maps unauthorized")
    let revision = NativeLLMFailure(code: "revision_mismatch", message: "课程知识档案版本已变化")
    try nativeRequire(revision.localizedDescription.contains("课程知识档案"), "tool errors surface the real message, not a generic NSError")
}

private func waitFor<T>(_ body: @escaping () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            box.value = .success(try await body())
        } catch {
            box.value = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    switch box.value! {
    case let .success(value): return value
    case let .failure(error): throw error
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}
