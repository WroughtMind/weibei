import Foundation

public struct OpenAIChatCompletionsProvider: NativeLLMAdapter {
    public var family: String { "openai-chat-completions" }

    public var baseURL: URL
    public var apiKey: String
    public var session: URLSession
    public var idleTimeoutNanoseconds: UInt64

    public init(
        baseURL: URL = URL(string: "https://api.deepseek.com/v1")!,
        apiKey: String,
        session: URLSession = .shared,
        idleTimeoutNanoseconds: UInt64 = 45_000_000_000
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
    }

    public func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request)
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
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: NativeLLMFailure(code: "cancelled", message: "cancelled"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeURLRequest(_ request: NativeLLMRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let messages: [[String: Any]] = request.messages.map { message in
            var body: [String: Any] = [
                "role": message.role.rawValue,
                "content": message.content,
            ]
            if let toolCallID = message.toolCallID {
                body["tool_call_id"] = toolCallID
            }
            if let toolCalls = message.toolCalls {
                body["tool_calls"] = toolCalls.map {
                    [
                        "id": $0.id,
                        "type": "function",
                        "function": ["name": $0.name, "arguments": $0.arguments],
                    ]
                }
            }
            return body
        }
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
        if !tools.isEmpty { payload["tools"] = tools }
        if let temperature = request.temperature { payload["temperature"] = temperature }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return urlRequest
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
            throw NativeLLMFailure(code: "server_error", message: message)
        }
        guard let choices = object["choices"] as? [[String: Any]], let choice = choices.first else {
            return []
        }
        var chunks: [NativeStreamChunk] = []
        if let usage = object["usage"] as? [String: Any] {
            chunks.append(
                .usage(
                    NativeTokenUsage(
                        inputTokens: usage["prompt_tokens"] as? Int ?? 0,
                        outputTokens: usage["completion_tokens"] as? Int ?? 0
                    )
                )
            )
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
