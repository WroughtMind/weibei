import Foundation

/// 聊天补全协议下各家的服务端联网搜索注入形态。
public enum ChatWebSearchStyle: String, Sendable {
    case none
    /// 智谱系:tools 追加 {"type":"web_search","web_search":{"enable":true}}。
    case zai
    /// 小米系:tools 追加 {"type":"web_search"}。
    case xiaomi
    /// 通义:请求体追加 enable_search=true。
    case qwen
    /// OpenRouter:请求体追加 plugins=[{"id":"web"}]。
    case openrouter
    /// Kimi:tools 追加 builtin_function $web_search,模型发起后由客户端原样回传。
    case kimi
}

public struct OpenAIChatCompletionsProvider: NativeLLMAdapter {
    public var family: String { "openai-chat-completions" }

    public var baseURL: URL
    public var apiKey: String
    public var session: URLSession
    public var idleTimeoutNanoseconds: UInt64
    public var extraHeaders: [String: String]
    public var webSearchStyle: ChatWebSearchStyle
    public var includesStreamUsage: Bool

    public init(
        baseURL: URL = URL(string: "https://api.deepseek.com/v1")!,
        apiKey: String,
        extraHeaders: [String: String] = [:],
        webSearchStyle: ChatWebSearchStyle = .none,
        includesStreamUsage: Bool = false,
        session: URLSession = .shared,
        idleTimeoutNanoseconds: UInt64 = 45_000_000_000
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
        self.webSearchStyle = webSearchStyle
        self.includesStreamUsage = includesStreamUsage
        self.session = session
        self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
    }

    public func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                func run(_ style: ChatWebSearchStyle) async throws {
                    let urlRequest = try makeURLRequest(request, webSearchStyle: style)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 800 { break }
                        }
                        throw Self.httpFailure(http.statusCode, body: body)
                    }
                    var framer = NativeSSEFramer()
                    var assembler = NativeToolCallAssembler()
                    var textIndex = 0
                    var lastEvent = Date()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        lastEvent = Date()
                        let payloads = try framer.append(Data((line + "\n").utf8))
                        for payload in payloads {
                            for chunk in try Self.translate(payload: payload, textIndex: &textIndex) {
                                assembler.apply(chunk)
                                continuation.yield(chunk)
                            }
                        }
                        if Date().timeIntervalSince(lastEvent) * 1_000_000_000 > Double(idleTimeoutNanoseconds) {
                            throw NativeLLMFailure(code: "timeout", message: "stream idle timeout")
                        }
                    }
                    for payload in try framer.finish() {
                        for chunk in try Self.translate(payload: payload, textIndex: &textIndex) {
                            continuation.yield(chunk)
                        }
                    }
                }
                do {
                    do {
                        try await run(webSearchStyle)
                        continuation.finish()
                    } catch let failure as NativeLLMFailure
                        where failure.status == 400
                            && !failure.isContextOverflow
                            && webSearchStyle != .none {
                        // 端点不认服务端搜索注入:去掉注入重试一次,本轮退化为不联网。
                        try await run(.none)
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: NativeLLMFailure(code: "cancelled", message: "cancelled"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeURLRequest(_ request: NativeLLMRequest) throws -> URLRequest {
        try makeURLRequest(request, webSearchStyle: webSearchStyle)
    }

    func makeURLRequest(_ request: NativeLLMRequest, webSearchStyle style: ChatWebSearchStyle) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in extraHeaders where name.caseInsensitiveCompare("Authorization") != .orderedSame {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let messages: [[String: Any]] = {
            var encoded: [[String: Any]] = []
            for message in request.messages {
                var body: [String: Any] = [
                    "role": message.role.rawValue,
                    "content": Self.contentValue(message),
                ]
                if let toolCallID = message.toolCallID {
                    body["tool_call_id"] = toolCallID
                }
                if let toolCalls = message.toolCalls {
                    body["tool_calls"] = toolCalls.map { call in
                        let type = call.name.hasPrefix("$") ? "builtin_function" : "function"
                        let id = call.id.isEmpty ? "call_\(call.name)" : call.id
                        return [
                            "id": id,
                            "type": type,
                            "function": ["name": call.name, "arguments": call.arguments],
                        ]
                    }
                }
                encoded.append(body)
                if message.role == .tool, !message.images.isEmpty {
                    encoded.append([
                        "role": "user",
                        "content": Self.imageParts(message.images, caption: ""),
                    ])
                }
            }
            return encoded
        }()
        let tools: [[String: Any]] = request.tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.schema.object,
                ],
            ]
        }
        var payload: [String: Any] = [
            "model": request.model,
            "stream": true,
            "messages": messages,
        ]
        if includesStreamUsage {
            payload["stream_options"] = ["include_usage": true]
        }
        var allTools = tools
        let enableSearch = request.enableNativeWebSearch
            || request.tools.contains(where: { $0.name == "weibei_course_map" })
        if enableSearch {
            switch style {
            case .none:
                break
            case .zai:
                if !allTools.contains(where: { $0["type"] as? String == "web_search" }) {
                    allTools.append([
                        "type": "web_search",
                        "web_search": ["enable": true],
                    ])
                }
            case .xiaomi:
                if !allTools.contains(where: { $0["type"] as? String == "web_search" }) {
                    allTools.append(["type": "web_search"])
                }
            case .qwen:
                payload["enable_search"] = true
            case .openrouter:
                payload["plugins"] = [["id": "web"]]
            case .kimi:
                if !allTools.contains(where: { ($0["type"] as? String) == "builtin_function" }) {
                    allTools.append([
                        "type": "builtin_function",
                        "function": ["name": "$web_search"],
                    ])
                }
            }
        }
        if !allTools.isEmpty { payload["tools"] = allTools }
        if let temperature = request.temperature { payload["temperature"] = temperature }
        if let maxTokens = request.maxTokens { payload["max_tokens"] = maxTokens }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return urlRequest
    }

    private static func contentValue(_ message: NativeModelMessage) -> Any {
        if message.role == .tool || message.images.isEmpty {
            return message.content
        }
        return imageParts(message.images, caption: message.content)
    }

    static func imageParts(_ images: [NativeImagePart], caption: String) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        if !caption.isEmpty {
            parts.append(["type": "text", "text": caption])
        }
        for image in images {
            parts.append([
                "type": "image_url",
                "image_url": ["url": image.dataURL],
            ])
        }
        return parts
    }

    private static func httpFailure(_ status: Int, body: String) -> NativeLLMFailure {
        let code: String
        switch status {
        case 401, 403: code = "unauthorized"
        case 429: code = "rate_limited"
        case 408, 504: code = "timeout"
        default: code = "server_error"
        }
        return NativeLLMFailure(code: code, status: status, message: "HTTP \(status) \(body)")
    }

    public static func translate(payload: String, textIndex: inout Int) throws -> [NativeStreamChunk] {
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeLLMFailure(code: "invalid_sse", message: "provider returned non-JSON SSE data")
        }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "provider error"
            throw NativeLLMFailure(code: error["code"] as? String ?? "server_error", message: message)
        }
        var chunks: [NativeStreamChunk] = []
        if let usage = object["usage"] as? [String: Any] {
            let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
            let cacheRead = promptDetails?["cached_tokens"] as? Int
            let promptTokens = usage["prompt_tokens"] as? Int ?? 0
            chunks.append(
                .usage(
                    NativeTokenUsage(
                        inputTokens: max(0, promptTokens - (cacheRead ?? 0)),
                        outputTokens: usage["completion_tokens"] as? Int ?? 0,
                        cacheReadTokens: cacheRead,
                        totalTokens: usage["total_tokens"] as? Int
                    )
                )
            )
        }
        guard let choices = object["choices"] as? [[String: Any]], let choice = choices.first else {
            return chunks
        }
        // 智谱系:顶层 web_search 数组,每条 link 为来源。
        if let searchResults = object["web_search"] as? [[String: Any]] {
            for result in searchResults {
                if let link = result["link"] as? String, !link.isEmpty {
                    chunks.append(.webSearchSource(url: link))
                }
            }
        }
        // 通义:顶层 search_info.search_results[].url。
        if let searchInfo = object["search_info"] as? [String: Any],
           let results = searchInfo["search_results"] as? [[String: Any]] {
            for result in results {
                if let url = result["url"] as? String, !url.isEmpty {
                    chunks.append(.webSearchSource(url: url))
                }
            }
        }
        // 小米/OpenRouter:消息 annotations 里的 url_citation(delta 或整条 message)。
        for annotated in [choice["delta"] as? [String: Any], choice["message"] as? [String: Any]] {
            guard let annotated, let annotations = annotated["annotations"] as? [[String: Any]] else { continue }
            for annotation in annotations {
                // 小米为顶层 url;OpenRouter 为嵌套 url_citation.url。
                let flat = annotation["url"] as? String
                let nested = (annotation["url_citation"] as? [String: Any])?["url"] as? String
                if let url = flat ?? nested, !url.isEmpty {
                    chunks.append(.webSearchSource(url: url))
                }
            }
        }
        if let finish = choice["finish_reason"] as? String, finish != "null" {
            let reason: NativeFinishReason
            switch finish {
            case "stop": reason = .stop
            case "tool_calls": reason = .toolCalls
            case "length": reason = .length
            default: reason = .stop
            }
            chunks.append(.finish(reason: reason, replayState: nil))
            return chunks
        }
        let delta = choice["delta"] as? [String: Any] ?? [:]
        if let text = delta["content"] as? String, !text.isEmpty {
            chunks.append(.textDelta(index: textIndex, text: text))
        }
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                let index = call["index"] as? Int ?? 0
                let id = call["id"] as? String ?? ""
                let function = call["function"] as? [String: Any] ?? [:]
                let name = function["name"] as? String
                let arguments = function["arguments"] as? String ?? ""
                chunks.append(.toolCallDelta(index: index, id: id, name: name, argumentsDelta: arguments))
            }
        }
        return chunks
    }
}
