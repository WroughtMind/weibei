import Foundation

public struct OpenAIResponsesProvider: NativeLLMAdapter {
    public var family: String { chatgptBackend ? "openai-codex-responses" : "openai-responses" }

    public var baseURL: URL
    public var accessToken: String
    public var accountID: String?
    public var chatgptBackend: Bool
    public var session: URLSession
    /// 供应商是否支持服务端 web_search 工具(OpenAI/ChatGPT 订阅/xAI/DeepSeek 等)。
    public var webSearchSupported: Bool

    public init(
        baseURL: URL,
        accessToken: String,
        accountID: String? = nil,
        chatgptBackend: Bool = false,
        webSearchSupported: Bool = true,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.accountID = accountID
        self.chatgptBackend = chatgptBackend
        self.webSearchSupported = webSearchSupported
        self.session = session
    }

    public func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        NativeHTTPByteStream.start(
            session: session,
            request: makeURLRequest(request),
            fallbackRequest: webSearchSupported ? makeURLOrURLRequestWithoutSearch(request) : nil,
            translate: Self.translate
        )
    }

    private func makeURLOrURLRequestWithoutSearch(_ request: NativeLLMRequest) -> URLRequest {
        var urlRequest = makeURLRequest(request)
        if let body = try? JSONSerialization.data(
            withJSONObject: Self.payload(for: request, webSearchSupported: false)
        ) {
            urlRequest.httpBody = body
        }
        return urlRequest
    }

    func makeURLRequest(_ request: NativeLLMRequest) -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("responses"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(NativeOpenAIOAuth.originator, forHTTPHeaderField: "originator")
        if let accountID, !accountID.isEmpty {
            urlRequest.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: Self.payload(for: request, webSearchSupported: webSearchSupported))
        return urlRequest
    }

    public static func payload(for request: NativeLLMRequest, webSearchSupported: Bool = true) -> [String: Any] {
        var tools: [[String: Any]] = request.tools.map { tool in
            [
                "type": "function",
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.schema.object,
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
        let assembled = assembleInput(request.messages)
        var payload: [String: Any] = [
            "model": request.model,
            "stream": true,
            "input": assembled.input,
            "store": false,
        ]
        if let instructions = assembled.instructions { payload["instructions"] = instructions }
        if !tools.isEmpty { payload["tools"] = tools }
        payload["include"] = include
        if let effort = request.reasoningEffort, !effort.isEmpty {
            payload["reasoning"] = ["effort": effort]
        }
        return payload
    }

    static func assembleInput(_ messages: [NativeModelMessage]) -> (instructions: String?, input: [[String: Any]]) {
        var instructions: String?
        var input: [[String: Any]] = []
        for message in messages {
            switch message.role {
            case .system:
                instructions = message.content
            case .user:
                input.append(["role": "user", "content": message.content])
            case .assistant:
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
                    "output": message.content,
                ])
            }
        }
        return (instructions, input)
    }

    public static func translate(_ payload: String) throws -> [NativeStreamChunk] {
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeLLMFailure(code: "invalid_sse", message: "Responses SSE was not JSON")
        }
        if let error = object["error"] as? [String: Any] {
            throw NativeLLMFailure(
                code: "server_error",
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
        case "response.output_item.added":
            guard let item = object["item"] as? [String: Any],
                  item["type"] as? String == "function_call" else { return [] }
            let id = (item["call_id"] as? String) ?? (item["id"] as? String) ?? ""
            let name = item["name"] as? String
            return [.toolCallDelta(index: index, id: id, name: name, argumentsDelta: "")]
        case "response.output_item.done":
            guard let item = object["item"] as? [String: Any],
                  item["type"] as? String == "web_search_call",
                  let action = item["action"] as? [String: Any],
                  let sources = action["sources"] as? [[String: Any]] else { return [] }
            return sources.compactMap { source in
                (source["url"] as? String).map(NativeStreamChunk.webSearchSource(url:))
            }
        case "response.function_call_arguments.delta":
            let delta = object["delta"] as? String ?? ""
            let id = object["call_id"] as? String ?? ""
            return [.toolCallDelta(index: index, id: id, name: nil, argumentsDelta: delta)]
        case "response.completed":
            let response = object["response"] as? [String: Any]
            let status = response?["status"] as? String
            let hasTools = ((response?["output"] as? [[String: Any]]) ?? []).contains {
                $0["type"] as? String == "function_call"
            }
            let reason: NativeFinishReason = hasTools ? .toolCalls : (status == "incomplete" ? .length : .stop)
            return [.finish(reason: reason, replayState: nil)]
        case "response.failed", "error":
            throw NativeLLMFailure(code: "server_error", message: object["message"] as? String ?? type)
        default:
            return []
        }
    }
}
