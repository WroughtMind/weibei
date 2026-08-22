import Foundation

public struct AnthropicMessagesProvider: NativeLLMAdapter {
    public var family: String { "anthropic-messages" }
    public var apiKey: String
    public var session: URLSession
    public var apiURL: URL

    public init(
        apiKey: String,
        apiURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.apiURL = apiURL
        self.session = session
    }

    public func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        NativeHTTPByteStream.start(session: session, request: makeURLRequest(request), translate: Self.translate)
    }

    func makeURLRequest(_ request: NativeLLMRequest) -> URLRequest {
        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: Self.payload(for: request))
        return urlRequest
    }

    static func payload(for request: NativeLLMRequest) -> [String: Any] {
        var system: String?
        var messages: [[String: Any]] = []
        for message in request.messages {
            switch message.role {
            case .system:
                system = message.content
            case .user:
                messages.append(["role": "user", "content": message.content])
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
                        "content": message.content,
                    ]],
                ])
            }
        }
        var payload: [String: Any] = [
            "model": request.model,
            "max_tokens": 16_384,
            "stream": true,
            "messages": messages,
        ]
        if let system { payload["system"] = system }
        if !request.tools.isEmpty {
            payload["tools"] = request.tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.schema.object,
                ]
            }
        }
        return payload
    }

    public static func translate(_ payload: String) throws -> [NativeStreamChunk] {
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeLLMFailure(code: "invalid_sse", message: "Anthropic SSE was not JSON")
        }
        let type = object["type"] as? String ?? ""
        let index = object["index"] as? Int ?? 0
        switch type {
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
            return []
        case "content_block_stop":
            return []
        case "message_delta":
            let delta = object["delta"] as? [String: Any] ?? [:]
            if delta["stop_reason"] as? String == "tool_use" {
                return [.finish(reason: .toolCalls, replayState: replayState(from: object))]
            }
            if delta["stop_reason"] != nil {
                return [.finish(reason: .stop, replayState: replayState(from: object))]
            }
            return []
        case "message_stop":
            return [.finish(reason: .stop, replayState: nil)]
        case "error":
            let error = object["error"] as? [String: Any]
            throw NativeLLMFailure(code: "server_error", message: error?["message"] as? String ?? "Anthropic error")
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
