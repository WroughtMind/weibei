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
    try checkWebSearchPayloadInjection()
    try checkProviderRouting()
    try checkSkillCatalogAndLoad()
    try checkLoadSkillIdempotent()
    try checkCreateDocumentSandbox()
    try checkCreateDocumentUserConfirmation()
    try checkDelegateCapabilities()
    try checkEvalSetLunaLow()
    try checkBackendSelection()
    try checkContextRevisionEcho()
    try checkNativeProductContract()
    try checkSessionTitleGeneration()
    try checkVisualAssetAndTurnLocation()
    try checkLiveModelListHelpers()
}

private func nativeRequire(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }
}

private final class NativePersistProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [StudyAgentLearningUpdate] = []

    func append(_ update: StudyAgentLearningUpdate) {
        lock.lock()
        stored.append(update)
        lock.unlock()
    }

    var updates: [StudyAgentLearningUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private func jsonObject(_ raw: Any?) -> [String: Any]? {
    if let object = raw as? [String: Any] { return object }
    if let object = raw as? [String: String] {
        return object.mapValues { $0 as Any }
    }
    guard let raw, JSONSerialization.isValidJSONObject(raw),
          let data = try? JSONSerialization.data(withJSONObject: raw),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return object
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
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: "weibei_search_workspace", argumentsDelta: "{\"query\":"))
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: nil, argumentsDelta: "\"利率\"}"))
    let calls = try assembler.completedCalls()
    try nativeRequire(calls.count == 1 && calls[0].name == "weibei_search_workspace", "tool call fragments assemble")
}

private func checkIncompleteArgumentsRejected() throws {
    var assembler = NativeToolCallAssembler()
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: "weibei_search_workspace", argumentsDelta: "{\"query\":\"利率\""))
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
        #"{"type":"response.output_item.added","output_index":1,"item":{"type":"function_call","call_id":"c1","name":"weibei_search_workspace"}}"#
    )
    try nativeRequire(tool.first == .toolCallDelta(index: 1, id: "c1", name: "weibei_search_workspace", argumentsDelta: ""), "Responses tool start maps")
    let searchSources = try OpenAIResponsesProvider.translate(
        #"{"type":"response.output_item.done","output_index":2,"item":{"type":"web_search_call","action":{"type":"search","sources":[{"type":"url","url":"https://example.com/fresh"}]}}}"#
    )
    try nativeRequire(
        searchSources == [.webSearchSource(url: "https://example.com/fresh")],
        "Responses search source maps"
    )
    let currentRunSourceURLs = ["https://example.com/fresh"]
    try nativeRequire(
        WeiBeiWebResearchURLPolicy.isAvailableInCurrentRun(
            "https://EXAMPLE.com:443/fresh#section",
            in: "搜索后继续核对",
            currentRunSourceURLs: currentRunSourceURLs
        ),
        "exact searched HTTPS URL is available in the current run"
    )
    try nativeRequire(
        !WeiBeiWebResearchURLPolicy.isAvailableInCurrentRun(
            "https://example.com/other",
            in: "搜索后继续核对",
            currentRunSourceURLs: currentRunSourceURLs
        ),
        "same-host different path is rejected"
    )
    try nativeRequire(
        WeiBeiWebResearchURLPolicy.isAvailableInCurrentRun(
            "https://example.com/fresh",
            in: "搜索后继续核对",
            currentRunSourceURLs: currentRunSourceURLs
        ),
        "searched URL remains available in the current run"
    )
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

private func checkWebSearchPayloadInjection() throws {
    let courseMap = NativeToolDefinition(
        name: "weibei_course_map",
        description: "map",
        schema: NativeJSONSchema(["type": "object"]),
        execute: { _, _ in NativeToolExecutionResult(text: "") }
    )
    let request = NativeLLMRequest(model: "test", messages: [], tools: [courseMap])

    let responsesOn = OpenAIResponsesProvider.payload(for: request, webSearchSupported: true)
    try nativeRequire(
        (responsesOn["tools"] as? [[String: Any]])?.contains { $0["type"] as? String == "web_search" } == true,
        "responses payload appends web_search when supported"
    )
    let responsesOff = OpenAIResponsesProvider.payload(for: request, webSearchSupported: false)
    try nativeRequire(
        (responsesOff["tools"] as? [[String: Any]])?.contains { $0["type"] as? String == "web_search" } != true,
        "responses payload omits web_search when unsupported"
    )

    let anthropicOn = AnthropicMessagesProvider.payload(for: request, webSearchTool: true)
    try nativeRequire(
        (anthropicOn["tools"] as? [[String: Any]])?.contains { $0["type"] as? String == "web_search_20250305" } == true,
        "anthropic payload appends web_search_20250305"
    )
    let anthropicOff = AnthropicMessagesProvider.payload(for: request, webSearchTool: false)
    try nativeRequire(
        (anthropicOff["tools"] as? [[String: Any]])?.contains { $0["type"] as? String == "web_search_20250305" } != true,
        "anthropic payload omits web search for gateways without it"
    )

    let googleOn = GoogleGenerativeAIProvider.payload(for: request, groundingSearch: true)
    try nativeRequire(
        (googleOn["tools"] as? [[String: Any]])?.contains { $0["google_search"] != nil } == true,
        "google payload appends google_search grounding"
    )

    // ChatCompletions:构造 provider 才带 style,payload 组装在实例方法内;用工厂构造的
    // 形态由路由断言覆盖,这里直接验证 translate 的通用来源解析。
    let zaiSSE = #"{"web_search":[{"link":"https://example.com/a"},{"link":"https://example.com/b"}],"choices":[{"delta":{"content":"hi"}}]}"#
    var textIndex = 0
    let zaiChunks = try OpenAIChatCompletionsProvider.translate(payload: zaiSSE, textIndex: &textIndex)
    try nativeRequire(
        zaiChunks.contains { if case .webSearchSource(let url) = $0 { return url == "https://example.com/a" } else { return false } },
        "chat completions translate reads zai web_search links"
    )
    let qwenSSE = #"{"search_info":{"search_results":[{"url":"https://example.com/q"}]},"choices":[{"delta":{"content":"hi"}}]}"#
    textIndex = 0
    let qwenChunks = try OpenAIChatCompletionsProvider.translate(payload: qwenSSE, textIndex: &textIndex)
    try nativeRequire(
        qwenChunks.contains { if case .webSearchSource(let url) = $0 { return url == "https://example.com/q" } else { return false } },
        "chat completions translate reads qwen search_info urls"
    )
    let annotationSSE = #"{"choices":[{"delta":{"content":"hi","annotations":[{"type":"url_citation","url":"https://example.com/cite"}]}}]}"#
    textIndex = 0
    let annotationChunks = try OpenAIChatCompletionsProvider.translate(payload: annotationSSE, textIndex: &textIndex)
    try nativeRequire(
        annotationChunks.contains { if case .webSearchSource(let url) = $0 { return url == "https://example.com/cite" } else { return false } },
        "chat completions translate reads url_citation annotations"
    )
    let openRouterSSE = #"{"choices":[{"delta":{"content":"hi","annotations":[{"type":"url_citation","url_citation":{"url":"https://example.com/nested"}}]}}]}"#
    textIndex = 0
    let openRouterChunks = try OpenAIChatCompletionsProvider.translate(payload: openRouterSSE, textIndex: &textIndex)
    try nativeRequire(
        openRouterChunks.contains { if case .webSearchSource(let url) = $0 { return url == "https://example.com/nested" } else { return false } },
        "chat completions translate reads nested url_citation annotations"
    )
    let anthropicResultSSE = #"{"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","content":[{"url":"https://example.com/anthropic"}]}}"#
    let anthropicChunks = try AnthropicMessagesProvider.translate(anthropicResultSSE)
    try nativeRequire(
        anthropicChunks.contains { if case .webSearchSource(let url) = $0 { return url == "https://example.com/anthropic" } else { return false } },
        "anthropic translate reads web_search_tool_result urls"
    )
    let googleSSE = #"{"candidates":[{"content":{"parts":[{"text":"hi"}]},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com/gemini"}}]}}]}"#
    let googleChunks = try GoogleGenerativeAIProvider.translate(googleSSE)
    try nativeRequire(
        googleChunks.contains { if case .webSearchSource(let url) = $0 { return url == "https://example.com/gemini" } else { return false } },
        "google translate reads grounding chunk uris"
    )
}

private func checkProviderRouting() throws {
    try nativeRequire(NativeProviderRouting.route(.deepseek).family == .openaiResponses, "deepseek moved to Responses for web search")
    try nativeRequire(NativeProviderRouting.route(.deepseek).webSearch == .responsesTool, "deepseek carries server web search")
    try nativeRequire(NativeProviderRouting.route(.xai).webSearch == .responsesTool, "xai carries server web search")
    try nativeRequire(NativeProviderRouting.route(.anthropic).webSearch == .anthropicTool, "anthropic carries server web search")
    try nativeRequire(NativeProviderRouting.route(.google).webSearch == .googleGrounding, "google carries grounding search")
    try nativeRequire(NativeProviderRouting.route(.zaiCodingCN).webSearch == .zaiChatTool, "zai CN carries chat web search")
    try nativeRequire(NativeProviderRouting.route(.xiaomi).webSearch == .xiaomiChatTool, "xiaomi carries chat web search")
    try nativeRequire(NativeProviderRouting.route(.qwenTokenPlanCN).webSearch == .qwenEnableSearch, "qwen CN carries enable_search")
    try nativeRequire(NativeProviderRouting.route(.openrouter).webSearch == .openrouterPlugin, "openrouter carries web plugin")
    try nativeRequire(NativeProviderRouting.route(.moonshotaiCN).webSearch == .kimiBuiltin, "moonshot CN carries builtin web search")
    try nativeRequire(NativeProviderRouting.route(.nvidia).webSearch == .none, "nvidia has no web search")
    try nativeRequire(NativeProviderRouting.route(.amazonBedrock).webSearch == .none, "bedrock has no web search")
    try nativeRequire(NativeProviderRouting.route(.openai).family == .openaiResponses, "openai API is Responses")
    try nativeRequire(NativeProviderRouting.route(.xai).family == .openaiResponses, "xAI is Responses")
    try nativeRequire(NativeProviderRouting.route(.anthropic).family == .anthropicMessages, "anthropic is Messages")
    try nativeRequire(NativeProviderRouting.route(.google).family == .googleGenerativeAI, "google is Gemini")
    try nativeRequire(NativeProviderRouting.route(.minimax).family == .anthropicMessages, "minimax uses the Anthropic-compatible route")
    try nativeRequire(NativeProviderRouting.route(.moonshotaiCN).baseURL?.host == "api.moonshot.cn", "moonshot CN host")
    try nativeRequire(
        NativeProviderRouting.uncoveredProviders.isEmpty,
        "all catalog providers are on a native family"
    )
    try nativeRequire(
        NativeProviderRouting.route(.githubCopilot).family == .openaiChatCompletions,
        "copilot is chat completions"
    )
    try nativeRequire(
        NativeProviderRouting.route(.githubCopilot).auth == .apiKey,
        "copilot uses a pasted token"
    )
    try nativeRequire(NativeProviderRouting.route(.radius).auth == .apiKey, "radius uses a pasted key")
    try nativeRequire(
        NativeProviderRouting.route(.googleVertex).family == .googleGenerativeAI,
        "vertex reuses the Gemini generate surface"
    )
    try nativeRequire(
        NativeProviderRouting.route(.amazonBedrock).family == .openaiChatCompletions,
        "bedrock uses the OpenAI-compatible chat completions surface"
    )
    try nativeRequire(AgentProviderID.githubCopilot.kind == .apiKey, "copilot is not a fake OAuth subscription")
    try nativeRequire(AgentProviderID.radius.kind == .apiKey, "radius is not a fake OAuth subscription")
    try nativeRequire(
        NativeProviderRouting.route(.azureOpenAI).family == .openaiResponses,
        "azure OpenAI is Responses"
    )
    try nativeRequire(
        NativeProviderRouting.route(.cloudflareAIGateway).family == .openaiChatCompletions,
        "cloudflare AI Gateway is chat completions"
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
    let root = try AgentResources.bundled().skillsURL
    let registry = try NativeSkillRegistry.load(from: root)
    try nativeRequire(registry.pack(named: "genui") != nil, "genui skill pack exists")
    try nativeRequire(registry.pack(named: "genui-advanced") != nil, "genui advanced skill pack exists")
    try nativeRequire(registry.pack(named: "socratic-questioning") != nil, "socratic skill pack exists")
    try nativeRequire(registry.catalogSummary().contains("genui"), "catalog lists genui")
    try nativeRequire(registry.catalogSummary().contains("genui-advanced"), "catalog lists genui advanced")
    let before = registry.packs.map(\.id)
    let loaded = registry.pack(named: "socratic-questioning")
    try nativeRequire(loaded?.body.contains("苏格拉底") == true, "socratic body loads")
    try nativeRequire(registry.packs.map(\.id) == before, "load is instruction-only and does not change registration")
    try nativeRequire(NativeSkillRegistry.isSignedBuiltin("genui"), "genui is a signed builtin")
    try nativeRequire(NativeSkillRegistry.isSignedBuiltin("genui-advanced"), "genui advanced is a signed builtin")
    let toolRegistry = NativeToolRegistry()
    _ = try waitFor { await NativeBuiltinTools.registerAll(into: toolRegistry, skillRoot: root) }
    let tools = try waitFor { await toolRegistry.resolved(scope: .global) }
    try nativeRequire(tools.contains { $0.name == "load_skill" }, "load_skill is the only registered skill loader")
    try nativeRequire(!tools.contains { $0.name == "read" }, "retired read alias is not registered")
    do {
        _ = try waitFor {
            try await toolRegistry.execute(
                NativeToolCallRequest(name: "read", argumentsJSON: "{\"path\":\"skill://visualize\"}", callID: "retired-read"),
                context: NativeToolExecutionContext(
                    request: StudyAgentRequest(
                        purpose: .conversation,
                        question: "加载技能",
                        materialTitle: "",
                        materialText: "",
                        noteTitle: "",
                        noteText: "",
                        contextRevision: "retired-read"
                    ),
                    liveStores: NativeLiveStores(skillRegistry: registry)
                ),
                scope: .global
            )
        }
        try nativeRequire(false, "retired read alias must be unknown")
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "unknown_tool", "retired read alias fails as unknown_tool")
    }
    let workspace = tools.first { $0.name == "weibei_search_workspace" }
    try nativeRequire(workspace != nil, "workspace search tool is registered")
    if let schema = jsonObject(workspace?.schema.object),
       let properties = jsonObject(schema["properties"]) {
        try nativeRequire(properties["query"] != nil, "workspace search requires query")
        try nativeRequire(properties["cursor"] != nil, "workspace search exposes pagination cursor")
        try nativeRequire(properties["scope"] != nil, "workspace search exposes scope")
        let required = schema["required"] as? [String] ?? []
        try nativeRequire(required.contains("query"), "workspace search query is required")
        try nativeRequire(required.contains("scope"), "workspace search requires an explicit scope")
    } else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 21, userInfo: [
            NSLocalizedDescriptionKey: "workspace search schema is incomplete",
        ])
    }

}

private func checkLoadSkillIdempotent() throws {
    let root = try AgentResources.bundled().skillsURL
    let packs = try NativeSkillRegistry.load(from: root)
    let registry = NativeToolRegistry()
    _ = try waitFor { await NativeBuiltinTools.registerAll(into: registry, skillRoot: root) }
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "加载技能",
        materialTitle: "",
        materialText: "",
        noteTitle: "",
        noteText: "",
        contextRevision: "skill-idempotent"
    )
    var context = NativeToolExecutionContext(
        request: request,
        liveStores: NativeLiveStores(skillRegistry: packs)
    )
    for (id, marker) in [
        ("genui", "魏碑常用界面规范"),
        ("genui-advanced", "魏碑高级界面规范"),
        ("socratic-questioning", "苏格拉底"),
    ] {
        let first = try waitFor {
            try await registry.execute(
                NativeToolCallRequest(name: "load_skill", argumentsJSON: "{\"id\":\"\(id)\"}", callID: "\(id)-1"),
                context: context,
                scope: .global
            )
        }
        try nativeRequire(first.text.contains(marker), "first load_skill injects \(id) body")
        try nativeRequire(first.details["alreadyLoaded"] as? Bool != true, "first \(id) load is not marked alreadyLoaded")
        if let loaded = first.details["loaded"] as? [String: Any], let loadedID = loaded["id"] as? String {
            context.loadedSkillIDs.insert(loadedID)
        }
        let second = try waitFor {
            try await registry.execute(
                NativeToolCallRequest(name: "load_skill", argumentsJSON: "{\"id\":\"\(id)\"}", callID: "\(id)-2"),
                context: context,
                scope: .global
            )
        }
        try nativeRequire(second.text.contains("已加载"), "second \(id) load returns a short already-loaded hint")
        try nativeRequire(second.text.count < first.text.count, "second \(id) load does not re-inject the full body")
        try nativeRequire(second.details["alreadyLoaded"] as? Bool == true, "second \(id) load is marked alreadyLoaded")
    }
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

private func checkCreateDocumentUserConfirmation() throws {
    let revision = "12:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    let registry = NativeToolRegistry()
    _ = try waitFor { await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil) }
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "帮我把这段整理成文稿",
        materialTitle: "",
        materialText: "",
        noteTitle: "",
        noteText: "",
        contextRevision: revision
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-doc-confirm-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let argumentsJSON = "{\"title\":\"复利笔记\",\"format\":\"markdown\",\"content\":\"# 复利\\n\\n利率是资金使用价格。\"}"

    let deniedContext = NativeToolExecutionContext(
        request: request,
        mode: .tutor,
        liveStores: NativeLiveStores(
            documentsRoot: root,
            confirmDocumentCreation: { _, _ in false }
        )
    )
    let denied = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(name: "create_document", argumentsJSON: argumentsJSON, callID: "doc-deny"),
            context: deniedContext,
            scope: .global
        )
    }
    try nativeRequire(
        denied.details["cancelled"] as? Bool == true,
        "denied creation reports cancelled in details"
    )
    try nativeRequire(denied.text.contains("没有写入任何文件"), "denied creation tells the Agent nothing was written")
    var files = [URL]()
    if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
        files = (enumerator.allObjects as? [URL]) ?? []
    }
    try nativeRequire(files.isEmpty, "denied creation writes nothing to disk")

    let approvedContext = NativeToolExecutionContext(
        request: request,
        mode: .tutor,
        liveStores: NativeLiveStores(
            documentsRoot: root,
            confirmDocumentCreation: { title, summary in
                title == "复利笔记"
                    && summary.contains("利率是资金使用价格")
            }
        )
    )
    let approved = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(name: "create_document", argumentsJSON: argumentsJSON, callID: "doc-approve"),
            context: approvedContext,
            scope: .global
        )
    }
    try nativeRequire(
        approved.details["cancelled"] as? Bool == false,
        "approved creation is not marked cancelled"
    )
    try nativeRequire(approved.text.contains("已写入文稿"), "approved creation reports the written document")
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
    let item16 = items.first { $0["id"] as? String == "16" }
    try nativeRequire(
        (item16?["expect"] as? String)?.contains("不反问") == true,
        "eval item 16 requires course_search then course_read without a clarifying question"
    )
}

private func checkBackendSelection() throws {
    // Pi retired 2026-08: native is the only backend. "pi" must stay
    // undecodable so legacy archives hit the lossy-decode marker instead.
    try nativeRequire(
        StudyAgentBackend(rawValue: "native") != nil,
        "native backend stays decodable"
    )
    try nativeRequire(
        StudyAgentBackend(rawValue: "pi") == nil,
        "pi backend stays retired"
    )
}

private func checkContextRevisionEcho() throws {
    let request = StudyAgentRequest(purpose: .conversation, question: "讲解风险资产组合",
        materialTitle: "", materialText: "", noteTitle: "", noteText: "", contextRevision: "internal-only",
        confirmedNotes: [StudyAgentPersistedNoteRef(itemID: "saved-note", title: "组合笔记")])
    let context = try NativePromptAssembler.turnContext(for: request)
    try nativeRequire(!context.contains(request.contextRevision), "internal revision stays out of the model input")
    try nativeRequire(context.contains("n1") && !context.contains("saved-note"), "saved notes expose only short aliases")
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
    try nativeRequire(revision.localizedDescription == revision.message, "tool errors surface the real message, not a generic NSError")
}

private func checkNativeProductContract() throws {
    let registry = NativeToolRegistry()
    _ = try waitFor { await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil) }
    let question = "我能解释单利，但复利还不熟。"
    let entryID = UUID().uuidString.lowercased()
    let probe = NativePersistProbe()
    let stores = NativeLiveStores(
        profile: { StudyAgentCourseProfileContext(revision: 7,
            entries: [StudyAgentCourseProfileEntry(id: entryID, kind: "concept", text: "用户自述：单利不熟")]) },
        persistLearningUpdate: { update in
            probe.append(update)
            return NativeStorePersistReceipt(status: .saved, message: "已保存",
                memoryUpdate: AgentReplyMemoryUpdate(memoryIDs: [UUID()], summary: update.entries[0].text))
        },
        persistCourseProfileUpdate: { update in
            guard update.profileRevision == 7, update.entries.first?.entryID == entryID else {
                return .rejected("条目或版本不正确")
            }
            return NativeStorePersistReceipt(status: .saved, message: "已保存",
                profileUpdate: AgentReplyProfileUpdate(entryIDs: [UUID(uuidString: entryID)!], summary: "单利", texts: ["用户自述：能解释单利"]))
        },
        performNoteProposal: { proposal in
            guard proposal.contextRevision == "internal-only" else { return .rejected("版本未绑定") }
            return NativeStorePersistReceipt(status: proposal.userRequested ? .saved : .pending,
                message: proposal.userRequested ? "已保存到目标笔记" : "待采用",
                action: AgentReplyAction(kind: .writeNote,
                    state: proposal.userRequested ? .executed : .pending, targetItemID: "note-1",
                    proposedMarkdown: proposal.markdown))
        }
    )
    let request = StudyAgentRequest(purpose: .conversation, question: question,
        materialTitle: "", materialText: "", noteTitle: "", noteText: "",
        projectScope: StudyAgentProjectScope(kind: .course, chatID: "check", courseID: UUID().uuidString),
        learningContext: StudyAgentLearningContext(memoryRevision: 3), contextRevision: "internal-only")
    let context = NativeToolExecutionContext(request: request, liveStores: stores)
    let tools = try waitFor { await registry.resolved(scope: .global) }
    for name in [
        "weibei_update_learning_memory",
        "weibei_course_profile_update",
        "weibei_note_proposal",
        "weibei_relation_proposal",
        "weibei_search_workspace",
        "weibei_course_read",
    ] {
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "missing tool \(name)",
            ])
        }
        try nativeRequire(tool.schema.object["properties"] is [String: Any], "\(name) schema includes properties")
        if [
            "weibei_update_learning_memory",
            "weibei_course_profile_update",
            "weibei_note_proposal",
            "weibei_relation_proposal",
        ].contains(name), let properties = tool.schema.object["properties"] as? [String: Any] {
            try nativeRequire(properties["contextRevision"] == nil, "\(name) hides contextRevision from new calls")
            try nativeRequire(properties["memoryRevision"] == nil, "\(name) hides memoryRevision from new calls")
            try nativeRequire(properties["profileRevision"] == nil, "\(name) hides profileRevision from new calls")
        }
    }
    let memory = try waitFor {
        try await registry.execute(NativeToolCallRequest(name: "weibei_read_learning_memory", argumentsJSON: "{}", callID: "read"), context: context, scope: .global)
    }
    let writable = NativeToolExecutionContext(request: request,
        lastReadMemoryRevision: (memory.details["memoryRevision"] as? NSNumber)?.uint64Value, liveStores: stores)
    let memoryJSON = """
    {"entries":[{"kind":"confusion","text":"复利还需练习","origin":"agentInference","evidence":"[用户：本轮] 复利还不熟。"}]}
    """
    let saved = try waitFor {
        try await registry.execute(NativeToolCallRequest(name: "weibei_update_learning_memory", argumentsJSON: memoryJSON, callID: "write"), context: writable, scope: .global)
    }
    try nativeRequire(saved.details["appliedMemoryUpdate"] != nil && probe.updates.count == 1, "memory runs before its receipt")
    try nativeRequire(probe.updates[0].entries[0].origin == .agentInference, "inference keeps its real origin")
    try nativeRequire(probe.updates[0].entries[0].evidence == "[用户：本轮] 复利还不熟。", "real quote stays intact")
    do {
        _ = try waitFor {
            try await registry.execute(NativeToolCallRequest(name: "weibei_update_learning_memory",
                argumentsJSON: memoryJSON.replacingOccurrences(of: "复利还不熟。", with: "我从来没说过的句子"), callID: "bad-evidence"), context: writable, scope: .global)
        }
        try nativeRequire(false, "fabricated evidence must fail")
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "invalid_evidence", "fabricated evidence is rejected")
    }
    let profile = try waitFor {
        try await registry.execute(NativeToolCallRequest(name: "weibei_read_learning_memory", argumentsJSON: "{}", callID: "profile-read"), context: context, scope: .global)
    }
    let read = try JSONSerialization.jsonObject(with: Data(profile.text.utf8)) as! [String: Any]
    let entries = read["courseProfile"] as! [String: Any]
    let entry = (entries["entries"] as! [[String: Any]])[0]
    let update = try JSONSerialization.data(withJSONObject: ["checkpoint": "userRequested",
        "entries": [["entryID": entry["entryID"]!, "kind": "concept", "text": "用户自述：能解释单利"]]])
    let profileSaved = try waitFor {
        try await registry.execute(NativeToolCallRequest(name: "weibei_course_profile_update", argumentsJSON: String(decoding: update, as: UTF8.self), callID: "profile-write"), context: context, scope: .global)
    }
    try nativeRequire(profileSaved.details["appliedProfileUpdate"] != nil, "profile updates use identifiers obtained through the read tool")
    for direct in [false, true] {
        let arguments = try JSONSerialization.data(withJSONObject: ["markdown": "笔记正文", "evidence": ["用户要求整理"], "userRequested": direct])
        let result = try waitFor {
            try await registry.execute(NativeToolCallRequest(name: "weibei_note_proposal", argumentsJSON: String(decoding: arguments, as: UTF8.self), callID: "note"), context: context, scope: .global)
        }
        try nativeRequire(result.text.contains(direct ? "executed" : "pending"), "note receipts distinguish executed and pending")
        try nativeRequire(!result.text.contains("internal-only"), "receipts expose targets, not internal revisions")
    }
}

private func checkSessionTitleGeneration() throws {
    try nativeRequire(
        NativeSessionTitle.normalizedTitle("  利率变化机制。") == "利率变化机制",
        "session title strips trailing punctuation"
    )
    try nativeRequire(
        NativeSessionTitle.normalizedTitle("# 标题：利率变化机制") == "利率变化机制",
        "session title strips markdown and 标题 prefix"
    )
    try nativeRequire(
        NativeSessionTitle.normalizedTitle("新对话") == nil,
        "generic session titles are rejected"
    )
    try nativeRequire(
        NativeSessionTitle.shouldPropose(completedTurnCount: 1)
            && NativeSessionTitle.shouldPropose(completedTurnCount: 2),
        "semantic titles can retry after a completed turn"
    )

    let generated = try waitFor {
        await NativeSessionTitle.generate(
            adapter: SessionTitleMockAdapter(),
            model: "mock",
            question: "请帮我解释利率为什么变化",
            answer: "利率是资金的价格。"
        )
    }
    try nativeRequire(generated == "利率变化机制", "session title generate returns the model title")
}

private func checkVisualAssetAndTurnLocation() throws {
    let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
    try nativeRequire(NativeVisualAssetMagic.matches(png, mediaType: "image/png"), "png magic matches")
    try nativeRequire(!NativeVisualAssetMagic.matches(png, mediaType: "image/jpeg"), "png is not jpeg")
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "这段什么意思",
        materialTitle: "利率讲义",
        materialText: "",
        noteTitle: "",
        noteText: "",
        focus: StudyAgentFocus(
            chatID: "chat",
            courseID: nil,
            materialItemID: "material-rates",
            materialTitle: "利率讲义",
            pageIndex: 11,
            sectionTitle: nil,
            sectionLocationID: nil,
            sectionOrdinal: nil,
            selectionText: nil,
            actionSource: "reader"
        ),
        contextRevision: "r1"
    )
    try nativeRequire(
        NativeTurnLocation.displayPage(11) == 12,
        "zero-based page index becomes the facing page"
    )
    try nativeRequire(
        NativeTurnLocation.block(for: request)?.contains("12") == true,
        "turn location includes the facing page"
    )
    try nativeRequire(
        NativeTurnLocation.block(for: request)?.contains("利率讲义") == true,
        "turn location names the open material"
    )
}

private func checkLiveModelListHelpers() throws {
    try nativeRequire(
        try AgentModelListService.resolvedModelsURL(base: "https://api.deepseek.com").absoluteString
            == "https://api.deepseek.com/v1/models",
        "openai-compatible list URL appends /v1/models"
    )
    try nativeRequire(
        try AgentModelListService.resolvedModelsURL(base: "https://api.groq.com/openai/v1").absoluteString
            == "https://api.groq.com/openai/v1/models",
        "bases that already end in /v1 only append /models"
    )
    try nativeRequire(
        NativeProviderRouting.modelListStrategy(
            provider: .deepseek,
            baseURL: NativeProviderRouting.route(.deepseek).baseURL
        ) == .openAICompatible(base: "https://api.deepseek.com"),
        "deepseek lists models from the live OpenAI-compatible catalog"
    )
    try nativeRequire(
        NativeProviderRouting.modelListStrategy(
            provider: .githubCopilot,
            baseURL: NativeProviderRouting.route(.githubCopilot).baseURL
        ) == .githubCopilot,
        "copilot lists models from the Copilot catalog"
    )
    try nativeRequire(
        NativeProviderRouting.modelListStrategy(
            provider: .googleVertex,
            baseURL: URL(string: "https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google")
        ) == .googlePublisherModels(
            base: "https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google"
        ),
        "vertex lists publisher models from the user-supplied root"
    )
}

private struct SessionTitleMockAdapter: NativeLLMAdapter {
    var family: String { "mock" }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(index: 0, text: "利率变化机制"))
            continuation.yield(.finish(reason: .stop, replayState: nil))
            continuation.finish()
        }
    }
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
