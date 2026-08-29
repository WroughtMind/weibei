import Foundation

public struct AnthropicMessagesProvider: NativeLLMAdapter {
    public var family: String { "anthropic-messages" }
    public var apiKey: String
    public var session: URLSession
    public var apiURL: URL
    /// 供应商是否支持 Anthropic 服务端 web_search 工具(官方/Vercel 网关/MiniMax 兼容端点)。
    public var webSearchTool: Bool

    public init(
        apiKey: String,
        apiURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        webSearchTool: Bool = false,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.apiURL = apiURL
        self.webSearchTool = webSearchTool
        self.session = session
    }

    public func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        NativeHTTPByteStream.start(
            session: session,
            request: makeURLRequest(request),
            fallbackRequest: webSearchTool ? makeURLRequestWithoutSearch(request) : nil,
            translate: Self.translate
        )
    }

    private func makeURLRequestWithoutSearch(_ request: NativeLLMRequest) -> URLRequest {
        var urlRequest = makeURLRequest(request)
        if let body = try? JSONSerialization.data(
            withJSONObject: Self.payload(for: request, webSearchTool: false)
        ) {
            urlRequest.httpBody = body
        }
        return urlRequest
    }

    func makeURLRequest(_ request: NativeLLMRequest) -> URLRequest {
        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: Self.payload(for: request, webSearchTool: webSearchTool))
        return urlRequest
    }

    public static func payload(for request: NativeLLMRequest, webSearchTool: Bool = false) -> [String: Any] {
        var system: String?
        var messages: [[String: Any]] = []
        for message in request.messages {
            switch message.role {
            case .system:
                system = message.content
            case .user:
                messages.append(["role": "user", "content": Self.userContent(message)])
            case .assistant:
                var content: [Any] = []
                if !message.content.isEmpty {
                    content.append(["type": "text", "text": message.content])
                }
                if let replay = request.replayState,
                   let blocks = try? JSONSerialization.jsonObject(with: replay) as? [[String: Any]] {
                    content.insert(contentsOf: blocks, at: 0)
                }
                if let calls = message.toolCalls {
                    for call in calls {
                        let input = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) ?? [:]
                        content.append([
                            "type": "tool_use",
                            "id": call.id,
                            "name": call.name,
                            "input": input,
                        ])
                    }
                }
                messages.append(["role": "assistant", "content": content])
            case .tool:
                messages.append([
                    "role": "user",
                    "content": [[
                        "type": "tool_result",
                        "tool_use_id": message.toolCallID ?? "",
                        "content": Self.toolResultContent(message),
                    ]],
                ])
            }
        }
        var payload: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens ?? 16_384,
            "stream": true,
            "messages": messages,
        ]
        if let system { payload["system"] = system }
        var tools: [[String: Any]] = request.tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.schema.object,
            ]
        }
        if webSearchTool, request.enableNativeWebSearch
            || request.tools.contains(where: { $0.name == "weibei_course_map" }) {
            if !tools.contains(where: { $0["type"] as? String == "web_search_20250305" }) {
                tools.append([
                    "type": "web_search_20250305",
                    "name": "web_search",
                ])
            }
        }
        if !tools.isEmpty {
            payload["tools"] = tools
        }
        return payload
    }

    static func userContent(_ message: NativeModelMessage) -> Any {
        if message.images.isEmpty { return message.content }
        var parts: [[String: Any]] = []
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        parts.append(contentsOf: imageBlocks(message.images))
        return parts
    }

    static func toolResultContent(_ message: NativeModelMessage) -> Any {
        if message.images.isEmpty { return message.content }
        var parts: [[String: Any]] = []
        if !message.content.isEmpty {
            parts.append(["type": "text", "text": message.content])
        }
        parts.append(contentsOf: imageBlocks(message.images))
        return parts
    }

    private static func imageBlocks(_ images: [NativeImagePart]) -> [[String: Any]] {
        images.map { image in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mediaType,
                    "data": image.base64,
                ],
            ]
        }
    }

    public static func translate(_ payload: String) throws -> [NativeStreamChunk] {
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeLLMFailure(code: "invalid_sse", message: "Anthropic SSE was not JSON")
        }
        let type = object["type"] as? String ?? ""
        let index = object["index"] as? Int ?? 0
        switch type {
        case "message_start":
            guard let usage = (object["message"] as? [String: Any])?["usage"] as? [String: Any] else {
                return []
            }
            return [
                .usage(
                    NativeTokenUsage(
                        inputTokens: usage["input_tokens"] as? Int ?? 0,
                        cacheReadTokens: usage["cache_read_input_tokens"] as? Int,
                        cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int
                    )
                ),
            ]
        case "content_block_delta":
            let delta = object["delta"] as? [String: Any] ?? [:]
            let deltaType = delta["type"] as? String ?? ""
            if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                return [.textDelta(index: index, text: text)]
            }
            if deltaType == "thinking_delta", let text = delta["thinking"] as? String, !text.isEmpty {
                return [.reasoningDelta(index: index, text: text)]
            }
            if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                return [.toolCallDelta(index: index, id: "", name: nil, argumentsDelta: partial)]
            }
            return []
        case "content_block_start":
            let block = object["content_block"] as? [String: Any] ?? [:]
            if block["type"] as? String == "tool_use" {
                let id = block["id"] as? String ?? ""
                let name = block["name"] as? String
                return [.toolCallDelta(index: index, id: id, name: name, argumentsDelta: "")]
            }
            // 服务端 web_search 结果块:content 里每条 web_search_result 带来源 url。
            if block["type"] as? String == "web_search_tool_result",
               let results = block["content"] as? [[String: Any]] {
                return results.compactMap { result in
                    (result["url"] as? String).map(NativeStreamChunk.webSearchSource(url:))
                }
            }
            return []
        case "content_block_stop":
            return []
        case "message_delta":
            let delta = object["delta"] as? [String: Any] ?? [:]
            var chunks: [NativeStreamChunk] = []
            if let usage = object["usage"] as? [String: Any] {
                chunks.append(
                    .usage(
                        NativeTokenUsage(
                            inputTokens: usage["input_tokens"] as? Int ?? 0,
                            outputTokens: usage["output_tokens"] as? Int ?? 0,
                            cacheReadTokens: usage["cache_read_input_tokens"] as? Int,
                            cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int
                        )
                    )
                )
            }
            if delta["stop_reason"] as? String == "tool_use" {
                chunks.append(.finish(reason: .toolCalls, replayState: replayState(from: object)))
                return chunks
            }
            if delta["stop_reason"] != nil {
                chunks.append(.finish(reason: .stop, replayState: replayState(from: object)))
            }
            return chunks
        case "message_stop":
            return [.finish(reason: .stop, replayState: nil)]
        case "error":
            let error = object["error"] as? [String: Any]
            throw NativeLLMFailure(
                code: error?["type"] as? String ?? "server_error",
                message: error?["message"] as? String ?? "Anthropic error"
            )
        default:
            return []
        }
    }

    static func replayState(from object: [String: Any]) -> Data? {
        let signature = (object["delta"] as? [String: Any])?["signature"] as? String
            ?? (object["content_block"] as? [String: Any])?["signature"] as? String
        guard let signature else { return nil }
        return try? JSONSerialization.data(withJSONObject: [
            ["type": "thinking", "signature": signature],
        ])
    }
}
