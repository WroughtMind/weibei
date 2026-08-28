import Foundation

public struct GoogleGenerativeAIProvider: NativeLLMAdapter {
    public var family: String { "google-generative-ai" }
    public var apiKey: String
    public var session: URLSession
    public var rootURL: URL
    /// 是否附加 google_search 接地(服务端联网搜索)。
    public var groundingSearch: Bool

    public init(
        apiKey: String,
        rootURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        groundingSearch: Bool = false,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.rootURL = rootURL
        self.groundingSearch = groundingSearch
        self.session = session
    }

    public func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        NativeHTTPByteStream.start(session: session, request: makeURLRequest(request), translate: Self.translate)
    }

    func makeURLRequest(_ request: NativeLLMRequest) -> URLRequest {
        let encodedModel = request.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.model
        let root = rootURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(root)/models/\(encodedModel):streamGenerateContent?alt=sse")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: Self.payload(for: request, groundingSearch: groundingSearch))
        return urlRequest
    }

    public static func payload(for request: NativeLLMRequest, groundingSearch: Bool = false) -> [String: Any] {
        var contents: [[String: Any]] = []
        var system: String?
        for message in request.messages {
            switch message.role {
            case .system:
                system = message.content
            case .user:
                contents.append(["role": "user", "parts": [["text": message.content]]])
            case .assistant:
                var parts: [[String: Any]] = []
                if !message.content.isEmpty { parts.append(["text": message.content]) }
                if let calls = message.toolCalls {
                    for call in calls {
                        let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) ?? [:]
                        parts.append(["functionCall": ["name": call.name, "args": args]])
                    }
                }
                contents.append(["role": "model", "parts": parts])
            case .tool:
                contents.append([
                    "role": "user",
                    "parts": [[
                        "functionResponse": [
                            "name": message.toolCallID ?? "tool",
                            "response": ["output": message.content],
                        ],
                    ]],
                ])
            }
        }
        var payload: [String: Any] = ["contents": contents]
        if let system {
            payload["systemInstruction"] = ["parts": [["text": system]]]
        }
        var tools: [[String: Any]] = []
        if !request.tools.isEmpty {
            tools.append([
                "functionDeclarations": request.tools.map { tool in
                    [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.schema.object,
                    ]
                },
            ])
        }
        if groundingSearch, request.enableNativeWebSearch
            || request.tools.contains(where: { $0.name == "weibei_course_map" }) {
            tools.append(["google_search": [:] as [String: Any]])
        }
        if !tools.isEmpty {
            payload["tools"] = tools
        }
        return payload
    }

    public static func translate(_ payload: String) throws -> [NativeStreamChunk] {
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeLLMFailure(code: "invalid_sse", message: "Gemini SSE was not JSON")
        }
        if let error = object["error"] as? [String: Any] {
            throw NativeLLMFailure(code: "server_error", message: error["message"] as? String ?? "Gemini error")
        }
        let candidates = object["candidates"] as? [[String: Any]] ?? []
        guard let candidate = candidates.first else {
            return []
        }
        var chunks: [NativeStreamChunk] = []
        // 接地来源:groundingMetadata.groundingChunks[].web.uri(可能单独出现,不带 content)
        if let grounding = candidate["groundingMetadata"] as? [String: Any],
           let groundChunks = grounding["groundingChunks"] as? [[String: Any]] {
            for ground in groundChunks {
                if let web = ground["web"] as? [String: Any], let uri = web["uri"] as? String, !uri.isEmpty {
                    chunks.append(.webSearchSource(url: uri))
                }
            }
        }
        guard let content = candidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return chunks
        }
        for (index, part) in parts.enumerated() {
            if let thought = part["thought"] as? Bool, thought, let text = part["text"] as? String, !text.isEmpty {
                chunks.append(.reasoningDelta(index: index, text: text))
                continue
            }
            if let text = part["text"] as? String, !text.isEmpty {
                chunks.append(.textDelta(index: index, text: text))
            }
            if let call = part["functionCall"] as? [String: Any] {
                let name = call["name"] as? String ?? ""
                let args = call["args"] ?? [:]
                let json = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                chunks.append(.toolCallDelta(index: index, id: name, name: name, argumentsDelta: json))
            }
        }
        if let finish = candidate["finishReason"] as? String, finish != "FINISH_REASON_UNSPECIFIED" {
            let reason: NativeFinishReason = finish == "STOP"
                ? (chunks.contains(where: {
                    if case .toolCallDelta = $0 { return true }
                    return false
                }) ? .toolCalls : .stop)
                : .stop
            chunks.append(.finish(reason: reason, replayState: nil))
        }
        return chunks
    }
}
