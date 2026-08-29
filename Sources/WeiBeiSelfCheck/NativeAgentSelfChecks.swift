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
    try checkRetrievalPrompt()
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
    let uncovered = Set(NativeProviderRouting.uncoveredProviders)
    try nativeRequire(
        uncovered == [.googleVertex, .amazonBedrock],
        "uncovered families stay Vertex/Bedrock"
    )
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
    try nativeRequire(registry.pack(named: "visualize") != nil, "visualize skill pack exists")
    try nativeRequire(registry.pack(named: "socratic-questioning") != nil, "socratic skill pack exists")
    try nativeRequire(registry.catalogSummary().contains("visualize"), "catalog lists visualize")
    let before = registry.packs.map(\.id)
    let loaded = registry.pack(named: "socratic-questioning")
    try nativeRequire(loaded?.body.contains("苏格拉底") == true, "socratic body loads")
    try nativeRequire(registry.packs.map(\.id) == before, "load is instruction-only and does not change registration")
    try nativeRequire(NativeSkillRegistry.isSignedBuiltin("visualize"), "visualize is a signed builtin")
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
    let search = tools.first { $0.name == "weibei_course_search" }
    try nativeRequire(search?.description.contains("不要先反问") == true, "course_search description forbids clarifying questions")
    try nativeRequire(search?.description.contains("weibei_course_read") == true, "course_search description continues into course_read")
    try nativeRequire(search?.description.contains("网页搜索") == true, "course_search description still allows web search after a miss")
    try nativeRequire(search?.description.contains("闲聊") == true, "course_search description skips unrelated chat")
    let workspace = tools.first { $0.name == "weibei_search_workspace" }
    try nativeRequire(workspace != nil, "workspace search tool is registered")
    if let schema = jsonObject(workspace?.schema.object),
       let properties = jsonObject(schema["properties"]) {
        try nativeRequire(properties["query"] != nil, "workspace search requires query")
        try nativeRequire(properties["crossLibrary"] != nil, "workspace search exposes crossLibrary")
        let required = schema["required"] as? [String] ?? []
        try nativeRequire(required.contains("query"), "workspace search query is required")
        try nativeRequire(!required.contains("crossLibrary"), "workspace search defaults to current course")
    } else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 21, userInfo: [
            NSLocalizedDescriptionKey: "workspace search schema is incomplete",
        ])
    }
    let read = tools.first { $0.name == "weibei_course_read" }
    try nativeRequire(read?.description.contains("不要停下来反问") == true, "course_read description forbids interrupting to ask")
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
    let first = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(name: "load_skill", argumentsJSON: "{\"id\":\"socratic-questioning\"}", callID: "1"),
            context: context,
            scope: .global
        )
    }
    try nativeRequire(first.text.contains("苏格拉底"), "first load_skill injects the skill body")
    try nativeRequire(first.details["alreadyLoaded"] as? Bool != true, "first load is not marked alreadyLoaded")
    if let loaded = first.details["loaded"] as? [String: Any], let id = loaded["id"] as? String {
        context.loadedSkillIDs.insert(id)
    }
    let second = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(name: "load_skill", argumentsJSON: "{\"id\":\"socratic-questioning\"}", callID: "2"),
            context: context,
            scope: .global
        )
    }
    try nativeRequire(second.text.contains("已加载"), "second load_skill returns a short already-loaded hint")
    try nativeRequire(second.text.count < first.text.count, "second load_skill does not re-inject the full body")
    try nativeRequire(second.details["alreadyLoaded"] as? Bool == true, "second load is marked alreadyLoaded")
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

private func checkRetrievalPrompt() throws {
    let prompt = NativePromptAssembler.webiSystemPrompt(
        bundledText: "you are webi",
        tools: []
    )
    try nativeRequire(prompt.contains("检索策略"), "native system prompt includes retrieval strategy")
    try nativeRequire(prompt.contains("不要用反问打断心流"), "retrieval strategy forbids interrupting with a clarifying question")
    try nativeRequire(prompt.contains("weibei_course_search"), "retrieval strategy names course_search")
    try nativeRequire(prompt.contains("weibei_search_workspace"), "retrieval strategy names workspace search")
    try nativeRequire(
        !prompt.contains("本轮还没有工作区文件检索工具"),
        "retired skip-workspace-search instruction stays gone"
    )
    try nativeRequire(prompt.contains("闲聊"), "retrieval strategy skips unrelated chat")
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
    let revision = "12:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    let prompt = NativePromptAssembler.webiSystemPrompt(
        bundledText: "you are webi",
        tools: [],
        contextRevision: revision
    )
    try nativeRequire(prompt.contains(revision), "system prompt includes this turn's contextRevision")
    try nativeRequire(prompt.contains("必须原样回传"), "system prompt tells the model to echo contextRevision")
    let confirmedPrompt = NativePromptAssembler.webiSystemPrompt(
        bundledText: "you are webi",
        tools: [],
        contextRevision: revision,
        confirmedNotes: [
            StudyAgentPersistedNoteRef(itemID: "note-rates", title: "利率是资金使用价格 2"),
        ]
    )
    try nativeRequire(confirmedPrompt.contains("note-rates"), "confirmed notes expose the persisted noteItemID")
    try nativeRequire(confirmedPrompt.contains("已经落库"), "confirmed notes tell the model not to treat them as pending")

    let registry = NativeToolRegistry()
    _ = try waitFor { await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil) }
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "记下复利进度",
        materialTitle: "",
        materialText: "",
        noteTitle: "",
        noteText: "",
        projectScope: StudyAgentProjectScope(
            kind: .course,
            chatID: UUID().uuidString.lowercased(),
            courseID: UUID().uuidString.lowercased()
        ),
        contextRevision: revision
    )
    let context = NativeToolExecutionContext(request: request)
    let memory = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(name: "weibei_read_learning_memory", argumentsJSON: "{}", callID: "m1"),
            context: context,
            scope: .global
        )
    }
    try nativeRequire(memory.text.contains(revision), "learning_memory returns the live contextRevision")
    do {
        _ = try waitFor {
            try await registry.execute(
                NativeToolCallRequest(
                    name: "weibei_update_learning_memory",
                    argumentsJSON: "{\"entries\":[]}",
                    callID: "u1"
                ),
                context: context,
                scope: .global
            )
        }
    } catch {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 9, userInfo: [
            NSLocalizedDescriptionKey: "empty entries should run without revision echo",
        ])
    }
    do {
        _ = try waitFor {
            try await registry.execute(
                NativeToolCallRequest(
                    name: "weibei_update_learning_memory",
                    argumentsJSON: "{\"entries\":[{\"kind\":\"progress\"}]}",
                    callID: "u2"
                ),
                context: context,
                scope: .global
            )
        }
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 9, userInfo: [
            NSLocalizedDescriptionKey: "entry without text should fail type validation",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "invalid_arguments", "missing entry text is invalid_arguments")
        try nativeRequire(failure.message.contains("text"), "type error names text")
    }
    let accepted = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_note_proposal",
                argumentsJSON: "{\"markdown\":\"利率是资金使用价格。\",\"evidence\":[\"[材料：利率] 利率是资金使用价格。\"],\"contextRevision\":\"\(revision)\"}",
                callID: "n1"
            ),
            context: context,
            scope: .global
        )
    }
    try nativeRequire(accepted.text.contains("待确认"), "array evidence is accepted for a note proposal")
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

private func checkNativeProductContract() throws {
    let revision = "12:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    let question = "我已掌握单利，复利还不熟。"
    let registry = NativeToolRegistry()
    _ = try waitFor { await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil) }
    let tools = try waitFor { await registry.resolved(scope: .global) }
    for name in [
        "weibei_update_learning_memory",
        "weibei_course_profile_update",
        "weibei_note_proposal",
        "weibei_relation_proposal",
        "weibei_course_search",
        "weibei_search_workspace",
        "weibei_course_read",
    ] {
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "missing tool \(name)",
            ])
        }
        try nativeRequire(tool.schema.object["properties"] is [String: Any], "\(name) schema includes properties")
    }
    if let profileTool = tools.first(where: { $0.name == "weibei_course_profile_update" }),
       let schema = jsonObject(profileTool.schema.object),
       let properties = jsonObject(schema["properties"]),
       let entries = jsonObject(properties["entries"]),
       let items = jsonObject(entries["items"]),
       let entryProperties = jsonObject(items["properties"]),
       let kind = jsonObject(entryProperties["kind"]),
        let kindEnum = ((kind["enum"] as? [String]) ?? (kind["enum"] as? [Any])?.compactMap({ $0 as? String })) {
        try nativeRequire(
            Set(kindEnum) == Set(["concept"]),
            "profile entry kind keeps only the self-reported concept set"
        )
        try nativeRequire(entryProperties["text"] != nil, "profile entries expose text")
        try nativeRequire(entryProperties["entryID"] != nil, "profile entries expose optional entryID")
        try nativeRequire(entryProperties["sources"] == nil, "profile entries no longer expose sources")
        try nativeRequire(
            profileTool.description.contains("用户自述：")
                && profileTool.description.contains("kind=concept"),
            "profile tool describes self-report shape"
        )
    } else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 20, userInfo: [
            NSLocalizedDescriptionKey: "course_profile_update entries schema is incomplete",
        ])
    }

    let request = StudyAgentRequest(
        purpose: .conversation,
        question: question,
        materialTitle: "利率课程",
        materialText: "利率是资金使用价格的表达。",
        noteTitle: "",
        noteText: "",
        projectScope: StudyAgentProjectScope(
            kind: .course,
            chatID: UUID().uuidString.lowercased(),
            courseID: UUID().uuidString.lowercased()
        ),
        learningContext: StudyAgentLearningContext(memoryRevision: 3),
        courseProfile: StudyAgentCourseProfileContext(revision: 2),
        contextRevision: revision
    )
    let context = NativeToolExecutionContext(request: request)

    do {
        _ = try waitFor {
            try await registry.execute(
                NativeToolCallRequest(
                    name: "weibei_note_proposal",
                    argumentsJSON: "{\"markdown\":\"利率是资金使用价格。\",\"evidence\":\"原文\",\"contextRevision\":\"\(revision)\"}",
                    callID: "type-1"
                ),
                context: context,
                scope: .global
            )
        }
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 11, userInfo: [
            NSLocalizedDescriptionKey: "string evidence should fail type validation",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "invalid_arguments", "wrong evidence type is invalid_arguments")
        try nativeRequire(failure.message.contains("evidence"), "type error names evidence")
    }

    let liveContext = NativeToolExecutionContext(
        request: request,
        liveStores: NativeLiveStores(
            profile: {
                StudyAgentCourseProfileContext(revision: 7)
            }
        )
    )
    let liveProfileResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_course_profile_update",
                argumentsJSON: "{\"contextRevision\":\"\(revision)\",\"profileRevision\":7,\"checkpoint\":\"userRequested\",\"entries\":[{\"kind\":\"concept\",\"text\":\"用户自述：已掌握单利，复利还不熟。\"}]}",
                callID: "profile-live"
            ),
            context: liveContext,
            scope: .global
        )
    }
    try nativeRequire(
        StudyAgentProposalDecoding.courseProfileUpdate(from: liveProfileResult.details)?.profileRevision == 7,
        "profile live store supplies the current revision"
    )

    let learningJSON = """
    {"entries":[{"kind":"progress","text":"刚搞懂复利"}],"resolutions":[]}
    """
    let learningResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_update_learning_memory",
                argumentsJSON: learningJSON,
                callID: "learn-1"
            ),
            context: context,
            scope: .global
        )
    }
    guard let learning = StudyAgentProposalDecoding.learningUpdate(from: learningResult.details) else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "learning_update details did not decode",
        ])
    }
    try nativeRequire(learning.entries.count == 1, "learning_update keeps entries")
    try nativeRequire(learning.entries[0].text == "刚搞懂复利", "learning_update entry text is preserved")
    try nativeRequire(learning.entries[0].origin == .userStatement, "host fills userStatement origin")
    try nativeRequire(learning.suggestedNext.isEmpty, "host supplies suggestedNext without the model")
    try nativeRequire(
        learning.entries[0].evidence == "[用户：本轮] \(question)",
        "host fills this turn's evidence without the model"
    )

    let blankIDJSON = """
    {"entries":[{"memoryID":"","kind":"understood","text":"用户自述：刚搞懂了复利。"}],"resolutions":[]}
    """
    let blankIDResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_update_learning_memory",
                argumentsJSON: blankIDJSON,
                callID: "learn-blank-id"
            ),
            context: context,
            scope: .global
        )
    }
    guard let blankDecoded = StudyAgentProposalDecoding.learningUpdate(from: blankIDResult.details) else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 23, userInfo: [
            NSLocalizedDescriptionKey: "empty memoryID should still decode after omit",
        ])
    }
    try nativeRequire(blankDecoded.entries[0].memoryID == nil, "empty memoryID is omitted as a new entry")

    let blankEntryJSON = """
    {"contextRevision":"\(revision)","profileRevision":2,"checkpoint":"userRequested","entries":[{"entryID":"","kind":"concept","text":"用户自述：刚搞懂了复利。"}]}
    """
    let blankEntryResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_course_profile_update",
                argumentsJSON: blankEntryJSON,
                callID: "profile-blank-id"
            ),
            context: context,
            scope: .global
        )
    }
    guard let blankProfile = StudyAgentProposalDecoding.courseProfileUpdate(from: blankEntryResult.details) else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 24, userInfo: [
            NSLocalizedDescriptionKey: "empty entryID should still decode after omit",
        ])
    }
    try nativeRequire(blankProfile.entries[0].entryID == nil, "empty entryID is omitted as a new entry")

    let assignedMemoryID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let persistProbe = NativePersistProbe()
    let persistContext = NativeToolExecutionContext(
        request: request,
        liveStores: NativeLiveStores(
            persistLearningUpdate: { update in
                persistProbe.append(update)
                return NativeStorePersistReceipt(
                    accepted: true,
                    message: "ok",
                    memoryUpdate: AgentReplyMemoryUpdate(
                        memoryIDs: [assignedMemoryID],
                        summary: update.entries[0].text
                    )
                )
            },
            persistCourseProfileUpdate: { _ in
                NativeStorePersistReceipt.rejected("档案保存失败，请省略空的 entryID")
            }
        )
    )
    let persisted = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_update_learning_memory",
                argumentsJSON: blankIDJSON,
                callID: "learn-persist"
            ),
            context: persistContext,
            scope: .global
        )
    }
    try nativeRequire(persistProbe.updates.count == 1, "Store persist runs inside the tool loop")
    try nativeRequire(persistProbe.updates[0].entries[0].memoryID == nil, "Store persist sees omitted memoryID")
    try nativeRequire(
        persisted.text.contains(assignedMemoryID.uuidString.lowercased()),
        "write receipt returns the system-assigned memoryID"
    )
    try nativeRequire(
        persisted.details["appliedMemoryUpdate"] != nil,
        "write details carry the Store receipt"
    )

    do {
        _ = try waitFor {
            try await registry.execute(
                NativeToolCallRequest(
                    name: "weibei_course_profile_update",
                    argumentsJSON: blankEntryJSON,
                    callID: "profile-persist-reject"
                ),
                context: persistContext,
                scope: .global
            )
        }
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 25, userInfo: [
            NSLocalizedDescriptionKey: "Store rejection must fail the tool instead of reporting success",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "store_rejected", "Store rejection is store_rejected")
        try nativeRequire(failure.message.contains("entryID"), "Store rejection names the ID contract")
    }

    let memoryID = UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!
    let readContext = NativeToolExecutionContext(
        request: {
            var next = request
            next.learningContext = StudyAgentLearningContext(
                memoryRevision: 3,
                memories: [
                    LearningMemoryEntry(
                        id: memoryID,
                        kind: .understood,
                        text: "用户自述：刚搞懂了复利。",
                        evidence: "[用户：本轮] 我刚搞懂了复利。",
                        origin: .userStatement
                    )
                ]
            )
            return next
        }(),
        liveStores: NativeLiveStores(
            learning: {
                StudyAgentLearningContext(
                    memoryRevision: 3,
                    memories: [
                        LearningMemoryEntry(
                            id: memoryID,
                            kind: .understood,
                            text: "用户自述：刚搞懂了复利。",
                            evidence: "[用户：本轮] 我刚搞懂了复利。",
                            origin: .userStatement
                        )
                    ]
                )
            }
        )
    )
    let readResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_read_learning_memory",
                argumentsJSON: "{}",
                callID: "read-memory-id"
            ),
            context: readContext,
            scope: .global
        )
    }
    try nativeRequire(
        readResult.text.contains("\"memoryID\"")
            && readResult.text.lowercased().contains(memoryID.uuidString.lowercased()),
        "read result exposes memoryID for the model to copy"
    )

    let profileResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_course_profile_update",
                argumentsJSON: "{\"contextRevision\":\"\(revision)\",\"profileRevision\":2,\"checkpoint\":\"userRequested\",\"entries\":[{\"kind\":\"concept\",\"text\":\"用户自述：已掌握单利，复利还不熟。\"}]}",
                callID: "profile-1"
            ),
            context: context,
            scope: .global
        )
    }
    guard let profile = StudyAgentProposalDecoding.courseProfileUpdate(from: profileResult.details) else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 13, userInfo: [
            NSLocalizedDescriptionKey: "course_profile_update details did not decode",
        ])
    }
    try nativeRequire(profile.checkpoint == "userRequested", "profile checkpoint is preserved")
    try nativeRequire(profile.entries.count == 1, "profile entries are preserved")

    do {
        _ = try waitFor {
            try await registry.execute(
                NativeToolCallRequest(
                    name: "weibei_course_profile_update",
                    argumentsJSON: """
                    {"contextRevision":"\(revision)","profileRevision":2,"checkpoint":"userRequested","entries":[{"kind":"userStatement","text":"用户自述：已掌握单利"}]}
                    """,
                    callID: "profile-bad-kind"
                ),
                context: context,
                scope: .global
            )
        }
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 21, userInfo: [
            NSLocalizedDescriptionKey: "invented profile kind userStatement should fail before success text",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "invalid_arguments", "invented profile kind is invalid_arguments")
        try nativeRequire(failure.message.contains("kind"), "profile shape error names kind")
    }

    do {
        _ = try waitFor {
            try await registry.execute(
                NativeToolCallRequest(
                    name: "weibei_update_learning_memory",
                    argumentsJSON: """
                    {"entries":[],"resolutions":[{"memoryID":"","text":"搞懂了复利"}]}
                    """,
                    callID: "learn-blank-resolution-id"
                ),
                context: context,
                scope: .global
            )
        }
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 22, userInfo: [
            NSLocalizedDescriptionKey: "resolution with blank memoryID should fail before success text",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "invalid_arguments", "blank resolution memoryID is invalid_arguments")
        try nativeRequire(failure.message.contains("memoryID"), "learning shape error names memoryID")
    }

    let noteResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_note_proposal",
                argumentsJSON: "{\"markdown\":\"## 利率\\n利率是资金使用价格。\",\"evidence\":[\"[材料：利率课程] 利率是资金使用价格的表达。\"],\"contextRevision\":\"\(revision)\"}",
                callID: "note-1"
            ),
            context: context,
            scope: .global
        )
    }
    guard let note = StudyAgentProposalDecoding.noteProposal(from: noteResult.details) else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 14, userInfo: [
            NSLocalizedDescriptionKey: "note_proposal details did not decode",
        ])
    }
    try nativeRequire(note.markdown.contains("利率是资金使用价格"), "note markdown is preserved")
    try nativeRequire(note.evidence.count == 1, "note evidence is preserved as an array")
    try nativeRequire(!note.userRequested, "note proposal without userRequested stays a suggestion")

    let directWriteResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_note_proposal",
                argumentsJSON: "{\"markdown\":\"## 复利\\n复利是利息再计息。\",\"evidence\":[\"[材料：利率课程] 复利定义。\"],\"contextRevision\":\"\(revision)\",\"userRequested\":true}",
                callID: "note-2"
            ),
            context: context,
            scope: .global
        )
    }
    guard let directWrite = StudyAgentProposalDecoding.noteProposal(from: directWriteResult.details) else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 16, userInfo: [
            NSLocalizedDescriptionKey: "direct write note_proposal details did not decode",
        ])
    }
    try nativeRequire(directWrite.userRequested, "userRequested=true marks a direct note write")
    try nativeRequire(directWriteResult.text.contains("直接写入"), "direct write result tells the model WeiBei writes immediately")

    let relationResult = try waitFor {
        try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_relation_proposal",
                argumentsJSON: "{\"noteItemID\":\"note-1\",\"sourceItemID\":\"material-rates\",\"contextRevision\":\"\(revision)\"}",
                callID: "rel-1"
            ),
            context: context,
            scope: .global
        )
    }
    guard let relation = StudyAgentProposalDecoding.relationProposal(from: relationResult.details) else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 15, userInfo: [
            NSLocalizedDescriptionKey: "relation_proposal details did not decode",
        ])
    }
    try nativeRequire(relation.noteItemID == "note-1", "relation noteItemID is preserved")
    try nativeRequire(relation.sourceItemID == "material-rates", "relation sourceItemID is preserved")
    try nativeRequire(relation.contextRevision == revision, "relation contextRevision is preserved")
    try checkAgentActionFlushDoesNotSpinRunLoop()
}

private func checkAgentActionFlushDoesNotSpinRunLoop() throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/WeiBei/Stores/WorkspaceStore.swift")
    let source = try String(contentsOf: url, encoding: .utf8)
    let names = [
        "cancelAgentReplyAction",
        "confirmAgentNoteAction",
        "markAgentNewCourseNoteExecuted",
        "undoAgentNoteAction",
        "confirmAgentRelationAction",
        "undoAgentRelationAction",
        "failAgentReplyAction",
        "persistAgentActionNote",
    ]
    for name in names {
        guard let body = topLevelFunctionBody(source, named: name) else {
            throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 16, userInfo: [
                NSLocalizedDescriptionKey: "missing \(name) while checking MainActor flush contract",
            ])
        }
        try nativeRequire(
            !containsSyncWorkspaceFlushCall(body),
            "SAFETY:agent-action-no-mainactor-runloop-flush \(name) must await flushPendingWorkspaceSaveAsync; sync flush or flushPendingNotePersistence() spins RunLoop on MainActor and times out after 写入"
        )
        try nativeRequire(
            body.contains("flushPendingWorkspaceSaveAsync"),
            "SAFETY:agent-action-no-mainactor-runloop-flush \(name) must persist with flushPendingWorkspaceSaveAsync"
        )
    }
    guard let persistNoteBody = topLevelFunctionBody(source, named: "persistAgentActionNote") else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 18, userInfo: [
            NSLocalizedDescriptionKey: "missing persistAgentActionNote while checking existing-note flush",
        ])
    }
    try nativeRequire(
        persistNoteBody.contains("flushPendingNotePersistence(flushWorkspace: false)"),
        "SAFETY:agent-action-no-mainactor-runloop-flush persistAgentActionNote must flush notes without the sync workspace wait; writing an existing note otherwise hits the 60s file-operation banner"
    )
    guard let newNoteBody = topLevelFunctionBody(source, named: "confirmAgentNewCourseNoteAction") else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 17, userInfo: [
            NSLocalizedDescriptionKey: "missing confirmAgentNewCourseNoteAction while checking same-name retry",
        ])
    }
    try nativeRequire(
        newNoteBody.contains("courseNoteMatchingFileStem")
            && newNoteBody.contains("keepBoth"),
        "SAFETY:agent-new-note-same-name-retry confirm after a leftover same-named note must reuse matching content or keep both, not surface targetConflict"
    )
}

private func topLevelFunctionBody(_ source: String, named name: String) -> String? {
    let signatures = ["    func \(name)(", "    private func \(name)("]
    guard let start = signatures.compactMap({ source.range(of: $0)?.lowerBound }).min() else {
        return nil
    }
    let fromStart = source[start...]
    let rest = fromStart.dropFirst()
    let markers = ["\n    func ", "\n    private func ", "\n    @discardableResult", "\n    nonisolated ", "\n    static "]
    var end = fromStart.endIndex
    for marker in markers {
        if let range = rest.range(of: marker), range.lowerBound < end {
            end = range.lowerBound
        }
    }
    return String(fromStart[..<end])
}

private func containsSyncWorkspaceFlushCall(_ body: String) -> Bool {
    for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let code: Substring
        if trimmed.hasPrefix("//") {
            continue
        } else if let comment = trimmed.range(of: "//") {
            code = trimmed[..<comment.lowerBound]
        } else {
            code = Substring(trimmed)
        }
        if code.contains("flushPendingWorkspaceSave()") {
            return true
        }
        if code.contains("waitForCourseFileOperation") {
            return true
        }
        if code.contains("flushPendingNotePersistenceAsync") {
            continue
        }
        if code.contains("flushPendingNotePersistence(flushWorkspace: false)")
            || code.contains("flushPendingNotePersistence(for:") {
            continue
        }
        if code.contains("flushPendingNotePersistence") {
            return true
        }
    }
    return false
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
            && !NativeSessionTitle.shouldPropose(completedTurnCount: 2),
        "semantic titles only run after the first completed turn"
    )

    let request = NativeLLMRequest(
        model: "mock",
        messages: [NativeModelMessage(role: .user, content: "q")],
        maxTokens: NativeSessionTitle.maxTokens
    )
    let anthropic = AnthropicMessagesProvider.payload(for: request)
    try nativeRequire(
        anthropic["max_tokens"] as? Int == NativeSessionTitle.maxTokens,
        "title request caps Anthropic max_tokens"
    )
    let responses = OpenAIResponsesProvider.payload(for: request, webSearchSupported: false)
    try nativeRequire(
        responses["max_output_tokens"] as? Int == NativeSessionTitle.maxTokens,
        "title request caps Responses max_output_tokens"
    )
    let gemini = GoogleGenerativeAIProvider.payload(for: request)
    let config = gemini["generationConfig"] as? [String: Any]
    try nativeRequire(
        config?["maxOutputTokens"] as? Int == NativeSessionTitle.maxTokens,
        "title request caps Gemini maxOutputTokens"
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
    var messages = [NativeModelMessage(role: .user, content: "这段什么意思")]
    NativeTurnLocation.applying(to: &messages, request: request)
    try nativeRequire(messages[0].content.contains("12"), "outgoing user message receives the facing page")
    try nativeRequire(messages[0].content.contains("这段什么意思"), "outgoing user message keeps the question")
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
        ) == nil,
        "unwired providers do not pretend to have a live catalog"
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
