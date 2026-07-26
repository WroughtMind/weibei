import Foundation

public struct PiAgentProviderConfiguration: Equatable, Sendable {
    public var provider: String?
    public var model: String?
    public var apiKey: String?
    public var baseURL: String?
    public var thinkingLevel: String

    public init(
        provider: String? = nil,
        model: String? = nil,
        apiKey: String? = nil,
        baseURL: String? = nil,
        thinkingLevel: String = "medium"
    ) {
        self.provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.thinkingLevel = thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "medium"
            : thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
