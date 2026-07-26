import Foundation

public enum StudyAgentProgress: Equatable, Sendable {
    case readingContext
    case usingTool(String)
    case text(String)
}

public typealias StudyAgentProgressHandler = @Sendable (StudyAgentProgress) async -> Void

/// User-facing classification for agent request failures (Pi + OpenAI + offline).
public enum AgentFailureKind: String, Equatable, Sendable {
    case offline
    case unauthorized
    case rateLimited
    case serverError
    case timedOut
    case cancelled
    case generic

    public func title(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .offline:
            return language.text("网络不可用", "Network unavailable")
        case .unauthorized:
            return language.text("密钥无效或未授权", "Invalid or unauthorized key")
        case .rateLimited:
            return language.text("请求过于频繁", "Rate limited")
        case .serverError:
            return language.text("模型服务暂时不可用", "Model service temporarily unavailable")
        case .timedOut:
            return language.text("请求超时", "Request timed out")
        case .cancelled:
            return language.text("已取消", "Cancelled")
        case .generic:
            return language.text("请求失败", "Request failed")
        }
    }

    public func guidance(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .offline:
            return language.text("请检查本机网络后重试。", "Check your network connection, then retry.")
        case .unauthorized:
            return language.text("请在设置中核对密钥与提供商。", "Check the API key and provider in Settings.")
        case .rateLimited:
            return language.text("请稍后再试，或更换模型/提供商。", "Wait a moment, or switch model/provider.")
        case .serverError:
            return language.text("服务端异常，请稍后重试。", "The server had an error. Try again shortly.")
        case .timedOut:
            return language.text("可以缩短问题或稍后重试。", "Try a shorter question, or retry later.")
        case .cancelled:
            return language.text("本次请求已取消。", "This request was cancelled.")
        case .generic:
            return language.text("可直接重试。", "You can retry.")
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .cancelled:
            return false
        case .offline, .unauthorized, .rateLimited, .serverError, .timedOut, .generic:
            return true
        }
    }

    public static func classify(_ error: Error) -> AgentFailureKind {
        if error is CancellationError {
            return .cancelled
        }
        if let pi = error as? PiAgentRuntimeError {
            switch pi {
            case .cancelled:
                return .cancelled
            case .commandTimedOut:
                return .timedOut
            case let .agentFailed(message):
                return classifyMessage(message)
            case let .inFlightFailed(message):
                return classifyMessage(message)
            case let .protocolFailure(message):
                return classifyMessage(message)
            case .unavailable, .resourcesMissing, .busy, .launchFailed, .commandRejected:
                return .generic
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return .offline
            case NSURLErrorTimedOut:
                return .timedOut
            case NSURLErrorUserCancelledAuthentication, NSURLErrorCancelled:
                return .cancelled
            default:
                break
            }
        }
        if ns.domain == "WeiBei.OpenAI" {
            switch ns.code {
            case 401, 403:
                return .unauthorized
            case 429:
                return .rateLimited
            case 408, 504:
                return .timedOut
            case 500, 502, 503:
                return .serverError
            default:
                if (500...599).contains(ns.code) { return .serverError }
            }
        }
        return classifyMessage(error.localizedDescription)
    }

    private static func classifyMessage(_ message: String) -> AgentFailureKind {
        let lower = message.lowercased()
        if lower.contains("cancel") || message.contains("取消") {
            return .cancelled
        }
        if lower.contains("timeout") || lower.contains("timed out") || message.contains("超时") {
            return .timedOut
        }
        if lower.contains("401") || lower.contains("403") || lower.contains("unauthorized") || lower.contains("invalid api key") || message.contains("未授权") || message.contains("密钥") {
            return .unauthorized
        }
        if lower.contains("429") || lower.contains("rate limit") || message.contains("过于频繁") {
            return .rateLimited
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("internet") || message.contains("网络") {
            return .offline
        }
        if lower.contains("500") || lower.contains("502") || lower.contains("503") || lower.contains("server") {
            return .serverError
        }
        return .generic
    }

    /// Build a bilingual failure bubble body. Includes a stable marker for UI detection.
    public func userMessage(
        language: WeiBeiInterfaceLanguage,
        detail: String?,
        draftPreserved: Bool = false
    ) -> String {
        let titleText = title(language: language)
        // Avoid "请求失败：请求失败" when the kind title is already "请求失败".
        let header: String
        switch self {
        case .generic:
            header = titleText
        default:
            header = language.text("请求失败：\(titleText)", "Request failed: \(titleText)")
        }
        var lines = [header, guidance(language: language)]
        if let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            let clipped = detail.count > 280 ? String(detail.prefix(280)) + "…" : detail
            lines.append(language.text("详情：\(clipped)", "Detail: \(clipped)"))
        }
        if draftPreserved {
            lines.append(language.text("问题已保留在输入框。", "The question remains in the composer."))
        }
        return lines.joined(separator: "\n")
    }
}
