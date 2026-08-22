import Foundation

enum NativeHTTPByteStream {
    static func start(
        session: URLSession,
        request: URLRequest,
        translate: @escaping (String) throws -> [NativeStreamChunk]
    ) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
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
