import Foundation

public struct NativeLLMRequest: Sendable {
    public var model: String
    public var messages: [NativeModelMessage]
    public var tools: [NativeToolDefinition]
    public var temperature: Double?
    public var reasoningEffort: String?
    public var enableNativeWebSearch: Bool
    public var replayState: Data?
    public var maxTokens: Int?

    public init(
        model: String,
        messages: [NativeModelMessage],
        tools: [NativeToolDefinition] = [],
        temperature: Double? = nil,
        reasoningEffort: String? = nil,
        enableNativeWebSearch: Bool = false,
        replayState: Data? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.enableNativeWebSearch = enableNativeWebSearch
        self.replayState = replayState
        self.maxTokens = maxTokens
    }
}

public protocol NativeLLMAdapter: Sendable {
    var family: String { get }
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error>
}
