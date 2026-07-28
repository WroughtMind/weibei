import Foundation

/// 验证核心对 CLI 暴露的稳定错误。
public struct VerificationError: Error, Equatable, LocalizedError, Sendable {
    public let code: String
    public let message: String

    /// 创建带稳定错误代码的验证错误。
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        "\(code): \(message)"
    }
}
