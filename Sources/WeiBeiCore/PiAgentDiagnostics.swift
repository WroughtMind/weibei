import Foundation

public enum PiAgentRuntimeError: LocalizedError, Equatable, Sendable {
    case unavailable
    case resourcesMissing(String)
    case busy
    case launchFailed(String)
    case commandTimedOut(String)
    case commandRejected(String)
    case protocolFailure(String)
    case agentFailed(String)
    case inFlightFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "魏碑内建的 PI 运行时缺失或损坏，请重新安装应用。"
        case let .resourcesMissing(path):
            return "魏碑的 PI 资源不完整：\(path)"
        case .busy:
            return "PI 正在处理另一项任务"
        case let .launchFailed(message):
            return "PI 启动失败：\(message)"
        case let .commandTimedOut(command):
            return "PI 命令超时：\(command)"
        case let .commandRejected(message):
            return "PI 拒绝命令：\(message)"
        case let .protocolFailure(message):
            return "PI 通信失败：\(message)"
        case let .agentFailed(message):
            return "PI 回答失败：\(message)"
        case let .inFlightFailed(message):
            return "PI 运行中断：\(message)"
        case .cancelled:
            return "PI 请求已取消"
        }
    }

    public var permitsAutomaticFallback: Bool {
        switch self {
        case .unavailable, .resourcesMissing, .busy, .launchFailed, .commandRejected:
            return true
        case let .commandTimedOut(command):
            return command != "prompt" && command != "abort"
        case .protocolFailure:
            return true
        case .agentFailed, .inFlightFailed, .cancelled:
            return false
        }
    }
}

public struct PiAgentRejectedReplyError: LocalizedError, Sendable {
    public let reason: String
    public let reply: StudyAgentReply

    public init(reason: String, reply: StudyAgentReply) {
        self.reason = reason
        self.reply = reply
    }

    public var errorDescription: String? { reason }
}

public enum PiAgentDiagnosticSanitizer {
    public static func sanitize(_ value: String, secret: String? = nil) -> String {
        var result = value
        if let secret, !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        let redactions = [
            (#"(?i)bearer\s+[A-Za-z0-9._~+/=-]{8,}"#, "Bearer [REDACTED]"),
            (#"\bsk-[A-Za-z0-9_-]{8,}\b"#, "[REDACTED]"),
            (#"(?i)([\"']?(?:authorization|api[_-]?key|access[_-]?token|secret)[\"']?\s*[:=]\s*[\"']?)([^\s\"',;}]+)"#, "$1[REDACTED]"),
        ]
        for (pattern, replacement) in redactions {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement
            )
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(2_048))
    }
}

public enum PiAnswerEvidenceRequirement {
    public static func validationError(
        contentLabels: Set<String>,
        learningLabels: Set<String>,
        allowsLearningOnlyAnswer: Bool,
        allowsSourceFreeAnswer: Bool
    ) -> String? {
        guard allowsSourceFreeAnswer
                || !contentLabels.isEmpty
                || (allowsLearningOnlyAnswer && !learningLabels.isEmpty) else {
            return "PI returned a content answer without a current-turn source citation"
        }
        return nil
    }
}
