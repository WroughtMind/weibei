import Foundation

enum NativeHTTPByteStream {
    /// 等到响应头的上限。首字若在响应头之后才出现，计入空闲超时。
    static let connectionTimeout: TimeInterval = 30
    /// 响应开始后，连续没有新字节的上限。推理模型常见首字在数十秒内，90 秒不再按各家放宽。
    static let idleTimeout: TimeInterval = 90

    static func start(
        session: URLSession,
        request: URLRequest,
        translate: @escaping (String) throws -> [NativeStreamChunk]
    ) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = request
                    request.timeoutInterval = idleTimeout
                    let (bytes, response) = try await bytesForRequest(session: session, request: request)
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
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: NativeLLMFailure(code: "timeout", message: "stream idle timeout"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 连接阶段单独计时。URLSession 的 timeoutInterval 在收到数据后会重置，不能同时表达「建连 30 秒」和「空闲 90 秒」。
    private static func bytesForRequest(
        session: URLSession,
        request: URLRequest
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let gate = ConnectionTimeoutGate()
        let fetch = Task { try await session.bytes(for: request) }
        let watchdog = Task {
            try await Task.sleep(nanoseconds: UInt64(connectionTimeout * 1_000_000_000))
            gate.fire()
            fetch.cancel()
        }
        do {
            let value = try await fetch.value
            watchdog.cancel()
            return value
        } catch {
            watchdog.cancel()
            if gate.fired {
                throw NativeLLMFailure(code: "timeout", message: "connection timeout")
            }
            throw error
        }
    }

    static func httpFailure(_ status: Int, body: String) -> NativeLLMFailure {
        let parsed = ProviderErrorBody.parse(body)
        let code = failureCode(status: status, body: body, parsed: parsed)
        return NativeLLMFailure(code: code, status: status, message: "HTTP \(status) \(body)")
    }

    /// 流式正文里的错误对象与 HTTP 错误体使用同一套 code，不按某一家的字段名单独分类。
    static func providerFailure(
        status: Int? = nil,
        code: String? = nil,
        type: String? = nil,
        statusName: String? = nil,
        message: String,
        usage: NativeTokenUsage? = nil
    ) -> NativeLLMFailure {
        let normalized = failureCode(
            status: status,
            body: message,
            parsed: ProviderErrorBody(code: code, type: type, statusName: statusName, message: message)
        )
        return NativeLLMFailure(code: normalized, status: status, usage: usage, message: message)
    }

    static func failureCode(status: Int?, body: String, parsed: ProviderErrorBody) -> String {
        if status == 400, rejectsWebSearch(body) { return "web_search_unsupported" }
        if isInsufficientQuota(status: status, parsed: parsed) { return "insufficient_quota" }
        if isModelNotFound(status: status, parsed: parsed) { return "model_not_found" }
        if isRateLimited(status: status, parsed: parsed) { return "rate_limited" }
        switch status {
        case 400: return "invalid_request"
        case 401, 403: return "unauthorized"
        case 408, 504: return "timeout"
        case 500, 502, 503: return "server_error"
        default: return status == nil ? (parsed.code ?? parsed.type ?? "provider_error") : "server_error"
        }
    }

    static func isInsufficientQuota(status: Int?, parsed: ProviderErrorBody) -> Bool {
        if status == 402 { return true }
        let tokens = parsed.tokens
        if tokens.contains(where: isQuotaToken) { return true }
        let message = parsed.message.lowercased()
        let phrases = [
            "insufficient_quota", "insufficient quota", "insufficient balance",
            "credit balance", "out of credits", "payment required",
            "quota exceeded", "exceeded your current quota", "billing_error",
        ]
        if phrases.contains(where: { message.contains($0) }) { return true }
        return parsed.message.contains("余额不足")
            || parsed.message.contains("额度不足")
            || parsed.message.contains("额度用尽")
    }

    private static func isQuotaToken(_ token: String) -> Bool {
        [
            "insufficient_quota", "insufficient_balance", "billing_error",
            "payment_required", "credit_balance_too_low", "out_of_credits",
            "quota_exceeded", "insufficient_credits",
        ].contains(token)
    }

    private static func isRateLimited(status: Int?, parsed: ProviderErrorBody) -> Bool {
        if isInsufficientQuota(status: status, parsed: parsed) { return false }
        let tokens = parsed.tokens
        if tokens.contains(where: { ["rate_limit_exceeded", "rate_limit_error", "too_many_requests", "rate_limited"].contains($0) }) {
            return true
        }
        return status == 429
    }

    private static func isModelNotFound(status: Int?, parsed: ProviderErrorBody) -> Bool {
        if status == 404 { return true }
        return parsed.tokens.contains(where: { ["model_not_found", "model_not_available", "not_found_error"].contains($0) })
    }

    private static func rejectsWebSearch(_ body: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else { return false }
        // ponytail: only explicit search rejection wording; extend when another service response is observed.
        let normalized = message.lowercased().replacingOccurrences(of: #"[`'"]"#, with: "", options: .regularExpression)
        let search = #"\b(?:web[_ ]search(?:_preview|_\d{8})?|google_search|enable_search)\b"#
        return normalized.range(
            of: "(?:^(?:(?:hosted )?tool(?: type)? )?\(search) is not supported\\b|^unsupported tool(?: type)?:? \(search)(?:$|[ .]))",
            options: .regularExpression
        ) != nil
    }
}

struct ProviderErrorBody: Equatable {
    var code: String?
    var type: String?
    var statusName: String?
    var message: String

    var tokens: [String] {
        [code, type, statusName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func parse(_ body: String) -> ProviderErrorBody {
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else {
            return ProviderErrorBody(code: nil, type: nil, statusName: nil, message: body)
        }
        let error = object["error"] as? [String: Any] ?? object
        return ProviderErrorBody(
            code: text(error["code"]),
            type: text(error["type"]),
            statusName: text(error["status"]),
            message: text(error["message"]) ?? body
        )
    }

    private static func text(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber, !(value is Bool) { return number.stringValue }
        return nil
    }
}

private final class ConnectionTimeoutGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didFire = false

    var fired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didFire
    }

    func fire() {
        lock.lock()
        didFire = true
        lock.unlock()
    }
}
