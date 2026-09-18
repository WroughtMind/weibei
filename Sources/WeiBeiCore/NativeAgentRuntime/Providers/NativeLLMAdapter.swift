import Foundation

public struct NativeLLMRequest: Sendable {
    public var model: String
    public var purpose: NativeModelCallPurpose = .answer
    public var messages: [NativeModelMessage]
    public var tools: [NativeToolDefinition]
    public var temperature: Double?
    public var reasoningEffort: String?
    public var enableNativeWebSearch: Bool
    public var maxTokens: Int?
    public var promptCacheKey: String?

    public init(
        model: String,
        messages: [NativeModelMessage],
        tools: [NativeToolDefinition] = [],
        temperature: Double? = nil,
        reasoningEffort: String? = nil,
        enableNativeWebSearch: Bool = false,
        maxTokens: Int? = nil,
        promptCacheKey: String? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.enableNativeWebSearch = enableNativeWebSearch
        self.maxTokens = maxTokens
        self.promptCacheKey = promptCacheKey
    }
}

public protocol NativeLLMAdapter: Sendable {
    var family: String { get }
    var contextWindow: Int? { get }
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error>
}

public extension NativeLLMAdapter {
    var contextWindow: Int? { nil }
}
