import Foundation

public struct OpenAIResponsesProvider: NativeLLMAdapter {
    public var family: String { chatgptBackend ? "openai-codex-responses" : "openai-responses" }

    public var baseURL: URL
    public var contextWindow: Int?
    public var accessToken: String
    public var accountID: String?
    public var chatgptBackend: Bool
    public var session: URLSession
    /// 供应商是否支持服务端 web_search 工具(OpenAI/ChatGPT 订阅/xAI/DeepSeek 等)。
    public var webSearchSupported: Bool
    /// Azure OpenAI uses `api-key` instead of Bearer.
    public var usesAzureAPIKey: Bool

    public init(
        baseURL: URL,
        accessToken: String,
        accountID: String? = nil,
        chatgptBackend: Bool = false,
        usesAzureAPIKey: Bool = false,
        webSearchSupported: Bool = true,
        session: URLSession = .shared,
        contextWindow: Int? = nil
    ) {
        self.baseURL = baseURL
        self.contextWindow = contextWindow
        self.accessToken = accessToken
        self.accountID = accountID
        self.chatgptBackend = chatgptBackend
        self.usesAzureAPIKey = usesAzureAPIKey
        self.webSearchSupported = webSearchSupported
        self.session = session
    }

    public func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        var completedItems: [Int: [String: Any]] = [:]
        return NativeHTTPByteStream.start(
            session: session,
            request: makeURLRequest(request),
            fallbackRequest: webSearchSupported ? makeURLOrURLRequestWithoutSearch(request) : nil,
            translate: { try Self.translate($0, completedItems: &completedItems) }
        )
    }

    private func makeURLOrURLRequestWithoutSearch(_ request: NativeLLMRequest) -> URLRequest {
        var urlRequest = makeURLRequest(request)
        if let body = try? JSONSerialization.data(
            withJSONObject: Self.payload(for: request, webSearchSupported: false), options: [.sortedKeys]
        ) {
            urlRequest.httpBody = body
        }
        return urlRequest
    }

    func makeURLRequest(_ request: NativeLLMRequest) -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("responses"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if usesAzureAPIKey {
            urlRequest.setValue(accessToken, forHTTPHeaderField: "api-key")
        } else {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue(NativeOpenAIOAuth.originator, forHTTPHeaderField: "originator")
        }
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let accountID, !accountID.isEmpty {
            urlRequest.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        if chatgptBackend, let key = request.promptCacheKey {
            urlRequest.setValue(key, forHTTPHeaderField: "session-id")
        }
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: Self.payload(for: request, webSearchSupported: webSearchSupported), options: [.sortedKeys])
        return urlRequest
    }

    private static func webActivityName(_ action: [String: Any]?) -> String {
        switch action?["type"] as? String {
        case "search": return "$web_search"
        case "open_page": return "$web_open"
        case "find_in_page": return "$web_find"
        default: return "$web_activity"
        }
    }

    private static func webActivity(_ item: [String: Any], id: String) -> AgentToolActivity {
        let action = item["action"] as? [String: Any]
        let queries = action?["queries"] as? [String]
        let pageDetail = [action?["pattern"] as? String, action?["url"] as? String].compactMap { $0 }.joined(separator: " · ")
        let detail = queries?.joined(separator: " · ") ?? action?["query"] as? String
            ?? (pageDetail.isEmpty ? nil : pageDetail)
        let urls = (action?["sources"] as? [[String: Any]])?.compactMap { $0["url"] as? String }
        let status = item["status"] as? String
        return .init(id: id, name: webActivityName(action),
                     state: status == "failed" ? .failed : status == "completed" ? .completed : .running,
                     detail: detail, sourceURLs: urls)
    }

    public static func payload(for request: NativeLLMRequest, webSearchSupported: Bool = true) -> [String: Any] {
        var tools: [[String: Any]] = request.tools.map { tool in
            [
                "type": "function",
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.schema.object,
                // Keep optional fields optional; Responses otherwise normalizes them into required fields.
                // NativeToolRegistry validates arguments and permissions before execution.
                "strict": false,
            ]
        }
        var include = ["reasoning.encrypted_content"]
        let enableSearch = request.enableNativeWebSearch
            || request.tools.contains(where: { $0.name == "weibei_course_map" })
        if enableSearch, webSearchSupported {
            if !tools.contains(where: { $0["type"] as? String == "web_search" }) {
                tools.append(["type": "web_search"])
            }
            include.append("web_search_call.action.sources")
        }
        let assembled = assembleInput(request.messages, purpose: request.purpose)
        var payload: [String: Any] = [
            "model": request.model,
            "stream": true,
            "input": assembled.input,
            "store": false,
        ]
        if let instructions = assembled.instructions { payload["instructions"] = instructions }
        if !tools.isEmpty { payload["tools"] = tools }
        if let key = request.promptCacheKey { payload["prompt_cache_key"] = key }
        payload["include"] = include
        if let effort = request.reasoningEffort, !effort.isEmpty {
            payload["reasoning"] = ["effort": effort]
        }
        if let maxTokens = request.maxTokens {
            payload["max_output_tokens"] = maxTokens
        }
        return payload
    }

    static func assembleInput(
        _ messages: [NativeModelMessage], purpose: NativeModelCallPurpose = .answer
    ) -> (instructions: String?, input: [[String: Any]]) {
        var instructions: String?
        var input: [[String: Any]] = []
        for message in messages {
            switch message.role {
            case .system:
                instructions = message.content
            case .user:
                input.append(["role": "user", "content": Self.userContent(message)])
            case .assistant:
                if purpose == .answer, let replay = message.replay,
                   ["openai-responses", "openai-codex-responses"].contains(replay.family),
                   let items = try? JSONSerialization.jsonObject(with: replay.items) as? [[String: Any]],
                   !items.isEmpty {
                    input.append(contentsOf: items)
                    continue
                }
                if let calls = message.toolCalls, !calls.isEmpty {
                    for call in calls {
                        input.append([
                            "type": "function_call",
                            "call_id": call.id,
                            "name": call.name,
                            "arguments": call.arguments,
                        ])
                    }
                    if !message.content.isEmpty {
                        input.append(["role": "assistant", "content": message.content])
                    }
                } else {
                    input.append(["role": "assistant", "content": message.content])
                }
            case .tool:
                input.append([
                    "type": "function_call_output",
                    "call_id": message.toolCallID ?? "",
                    "output": Self.toolOutput(message),
                ])
            }
        }
        return (instructions, input)
    }

    static func userContent(_ message: NativeModelMessage) -> Any {
        if message.images.isEmpty { return message.content }
        var parts: [[String: Any]] = []
        if !message.content.isEmpty {
            parts.append(["type": "input_text", "text": message.content])
        }
        for image in message.images {
            parts.append([
                "type": "input_image",
                "image_url": image.dataURL,
            ])
        }
        return parts
    }

    static func toolOutput(_ message: NativeModelMessage) -> Any {
        if message.images.isEmpty { return message.content }
        var parts: [[String: Any]] = []
        if !message.content.isEmpty {
            parts.append(["type": "input_text", "text": message.content])
        }
        for image in message.images {
            parts.append([
                "type": "input_image",
                "image_url": image.dataURL,
            ])
        }
        return parts
    }

    public static func translate(_ payload: String) throws -> [NativeStreamChunk] {
        var completedItems: [Int: [String: Any]] = [:]
        return try translate(payload, completedItems: &completedItems)
    }

    static func translate(_ payload: String, completedItems: inout [Int: [String: Any]]) throws -> [NativeStreamChunk] {
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeLLMFailure(code: "invalid_sse", message: "Responses SSE was not JSON")
        }
        if let error = object["error"] as? [String: Any] {
            throw NativeLLMFailure(
                code: error["code"] as? String ?? "server_error",
                message: error["message"] as? String ?? "Responses error"
            )
        }
        let type = object["type"] as? String ?? ""
        let index = object["output_index"] as? Int ?? 0
        switch type {
        case "response.output_text.delta":
            let text = object["delta"] as? String ?? ""
            return text.isEmpty ? [] : [.textDelta(index: index, text: text)]
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            let text = object["delta"] as? String ?? ""
            return text.isEmpty ? [] : [.reasoningDelta(index: index, text: text)]
        case "response.web_search_call.in_progress", "response.web_search_call.searching", "response.web_search_call.completed":
            guard let id = object["item_id"] as? String, !id.isEmpty else { return [] }
            return [.serverToolActivity(.init(id: id, name: "$web_activity",
                state: type == "response.web_search_call.completed" ? .completed : .running))]
        case "response.output_item.added":
            if let item = object["item"] as? [String: Any],
               item["type"] as? String == "web_search_call", let id = item["id"] as? String {
                return [.serverToolActivity(webActivity(item, id: id))]
            }
            guard let item = object["item"] as? [String: Any],
                  item["type"] as? String == "function_call" else { return [] }
            let id = (item["call_id"] as? String) ?? (item["id"] as? String) ?? ""
            let name = item["name"] as? String
            return [.toolCallDelta(index: index, id: id, name: name, argumentsDelta: "")]
        case "response.output_item.done":
            guard let item = object["item"] as? [String: Any] else { return [] }
            if let outputIndex = object["output_index"] as? Int, outputIndex >= 0 {
                completedItems[outputIndex] = item
            }
            guard item["type"] as? String == "web_search_call" else { return [] }
            var chunks: [NativeStreamChunk] = []
            let action = item["action"] as? [String: Any]
            if let id = item["id"] as? String {
                chunks.append(.serverToolActivity(webActivity(item, id: id)))
            }
            for source in action?["sources"] as? [[String: Any]] ?? [] {
                if let url = source["url"] as? String { chunks.append(.webSearchSource(url: url)) }
            }
            return chunks
        case "response.function_call_arguments.delta":
            let delta = object["delta"] as? String ?? ""
            let id = object["call_id"] as? String ?? ""
            return [.toolCallDelta(index: index, id: id, name: nil, argumentsDelta: delta)]
        case "response.completed", "response.incomplete":
            defer { completedItems.removeAll() }
            let response = object["response"] as? [String: Any]
            let status = response?["status"] as? String
            // Some streams finish with output: []; complete native items arrived in output_item.done.
            let finalOutput = response?["output"] as? [[String: Any]] ?? []
            let output = finalOutput.isEmpty ? completedItems.keys.sorted().compactMap { completedItems[$0] } : finalOutput
            let hasTools = output.contains {
                $0["type"] as? String == "function_call"
            }
            let incompleteReason = (response?["incomplete_details"] as? [String: Any])?["reason"] as? String
            let refused = output.contains { output in
                (output["content"] as? [[String: Any]] ?? []).contains { $0["type"] as? String == "refusal" }
            }
            let reason: NativeFinishReason
            if status == "incomplete" || type == "response.incomplete" {
                reason = incompleteReason == "content_filter" ? .refused : .length
            } else if refused {
                reason = .refused
            } else {
                reason = hasTools ? .toolCalls : .stop
            }
            var chunks: [NativeStreamChunk] = []
            if let usage = tokenUsage(response?["usage"]) {
                chunks.append(.usage(usage))
            }
            let replayState: Data?
            if type == "response.completed", status != "incomplete", !output.isEmpty {
                replayState = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
            } else {
                replayState = nil
            }
            chunks.append(.finish(reason: reason, replayState: replayState))
            return chunks
        case "response.failed", "error":
            let error = (object["response"] as? [String: Any])?["error"] as? [String: Any]
                ?? object["error"] as? [String: Any]
            throw NativeLLMFailure(
                code: error?["code"] as? String ?? "server_error",
                usage: tokenUsage((object["response"] as? [String: Any])?["usage"]),
                message: error?["message"] as? String ?? object["message"] as? String ?? type
            )
        default:
            return []
        }
    }

    private static func tokenUsage(_ value: Any?) -> NativeTokenUsage? {
        struct Usage: Decodable {
            struct Details: Decodable { var cached_tokens: Int? }
            var input_tokens: Int
            var output_tokens: Int
            var input_tokens_details: Details?
            var total_tokens: Int?
        }
        guard let value = value as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: value),
              let usage = try? JSONDecoder().decode(Usage.self, from: data),
              usage.input_tokens >= 0, usage.output_tokens >= 0,
              usage.input_tokens <= Int.max - usage.output_tokens,
              (usage.total_tokens ?? 0) >= 0 else { return nil }
        let cached = usage.input_tokens_details?.cached_tokens
        guard (cached ?? 0) >= 0, (cached ?? 0) <= usage.input_tokens else { return nil }
        return NativeTokenUsage(
            inputTokens: usage.input_tokens - (cached ?? 0),
            outputTokens: usage.output_tokens,
            cacheReadTokens: cached,
            totalTokens: usage.total_tokens
        )
    }

}
