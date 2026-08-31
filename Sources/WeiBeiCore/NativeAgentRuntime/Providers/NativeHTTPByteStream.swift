import Foundation

enum NativeHTTPByteStream {
    static func start(
        session: URLSession,
        request: URLRequest,
        fallbackRequest: URLRequest? = nil,
        translate: @escaping (String) throws -> [NativeStreamChunk]
    ) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                func pump(_ request: URLRequest) async throws {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 800 { break }
                        }
                        throw httpFailure(http.statusCode, body: body)
                    }
                    var framer = NativeSSEFramer()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        let payloads = try framer.append(Data((line + "\n").utf8))
                        for payload in payloads {
                            for chunk in try translate(payload) {
                                continuation.yield(chunk)
                            }
                        }
                    }
                    for payload in try framer.finish() {
                        for chunk in try translate(payload) {
                            continuation.yield(chunk)
                        }
                    }
                }
                do {
                    do {
                        try await pump(request)
                        continuation.finish()
                    } catch let failure as NativeLLMFailure
                        where failure.status == 400
                            && !failure.isContextOverflow
                            && fallbackRequest != nil {
                        // 端点不认服务端搜索工具(如网关未透传):去掉搜索重试一次,
                        // 本次回答退化为不联网,不让整轮对话失败。
                        try await pump(fallbackRequest!)
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

    static func httpFailure(_ status: Int, body: String) -> NativeLLMFailure {
        let code: String
        switch status {
        case 401, 403: code = "unauthorized"
        case 429: code = "rate_limited"
        case 408, 504: code = "timeout"
        default: code = "server_error"
        }
        return NativeLLMFailure(code: code, status: status, message: "HTTP \(status) \(body)")
    }
}
