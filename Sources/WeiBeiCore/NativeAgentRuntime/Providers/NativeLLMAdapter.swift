import Foundation

public struct NativeLLMRequest: Sendable {
    public var model: String
    public var messages: [NativeModelMessage]
    public var tools: [NativeToolDefinition]
    public var temperature: Double?

    public init(
        model: String,
        messages: [NativeModelMessage],
        tools: [NativeToolDefinition] = [],
        temperature: Double? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
    }
}

public protocol NativeLLMAdapter: Sendable {
    var family: String { get }
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error>
}
