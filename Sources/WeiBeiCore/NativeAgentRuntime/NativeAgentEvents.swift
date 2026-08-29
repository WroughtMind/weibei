import Foundation

/// Stream vocabulary translated from DSH `StreamChunk`.
/// Tool-call arguments stay a raw JSON string until a complete object exists.
public enum NativeStreamChunk: Codable, Equatable, Sendable {
    case blockStart(index: Int, blockType: NativeContentBlockType)
    case textDelta(index: Int, text: String)
    case reasoningDelta(index: Int, text: String)
    case webSearchSource(url: String)
    case toolCallDelta(index: Int, id: String, name: String?, argumentsDelta: String)
    case blockEnd(index: Int, block: NativeContentBlock)
    case usage(NativeTokenUsage)
    case finish(reason: NativeFinishReason, replayState: Data?)

    public enum NativeContentBlockType: String, Codable, Sendable {
        case text
        case reasoning
        case toolCall = "tool_call"
    }
}

public enum NativeContentBlock: Codable, Equatable, Sendable {
    case text(String)
    case reasoning(String)
    case toolCall(id: String, name: String, arguments: String)
}

public struct NativeTokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum NativeFinishReason: String, Codable, Sendable {
    case stop
    case toolCalls = "tool_calls"
    case length
    case error
    case aborted
}

public struct NativeLLMFailure: Error, LocalizedError, Codable, Equatable, Sendable {
    public var code: String
    public var status: Int?
    public var retryAfterMs: Int?
    public var requestID: String?
    public var message: String

    public var errorDescription: String? { message }

    public init(
        code: String,
        status: Int? = nil,
        retryAfterMs: Int? = nil,
        requestID: String? = nil,
        message: String
    ) {
        self.code = code
        self.status = status
        self.retryAfterMs = retryAfterMs
        self.requestID = requestID
        self.message = message
    }

    public var asAgentFailureKind: AgentFailureKind {
        if let status {
            switch status {
            case 401, 403: return .unauthorized
            case 429: return .rateLimited
            case 408, 504: return .timedOut
            case 500, 502, 503: return .serverError
            default: break
            }
        }
        switch code {
        case "unauthorized": return .unauthorized
        case "rate_limited": return .rateLimited
        case "timeout": return .timedOut
        case "offline": return .offline
        case "cancelled", "aborted": return .cancelled
        case "server_error": return .serverError
        default:
            return AgentFailureKind.classify(
                NSError(domain: "WeiBei.NativeAgent", code: status ?? 0, userInfo: [
                    NSLocalizedDescriptionKey: message,
                ])
            )
        }
    }
}

public enum NativeTurnEndReason: String, Codable, Sendable {
    case completed
    case cancelled
    case error
    case rejected
}

public enum NativeSessionEventType: String, Codable, Sendable {
    case turnStart = "turn/start"
    case turnEnd = "turn/end"
    case stepStart = "step/start"
    case stepEnd = "step/end"
    case userMessage = "user/message"
    case assistantChunk = "assistant/chunk"
    case assistantMessage = "assistant/message"
    case toolCall = "tool/call"
    case toolResult = "tool/result"
    case surfaceReplace = "surface/replace"
    case closer = "session/closer"
}

public struct NativeSessionEvent: Codable, Equatable, Sendable {
    public var type: NativeSessionEventType
    public var seq: Int
    public var timeMS: Int64
    public var turn: Int?
    public var step: Int?
    public var text: String?
    public var toolCallID: String?
    public var toolName: String?
    public var argumentsJSON: String?
    public var isError: Bool
    public var finishReason: NativeTurnEndReason?
    public var chunk: NativeStreamChunk?
    public var replaceStart: Int?
    public var replaceEnd: Int?
    public var imageMediaType: String?
    public var imageBase64: String?

    public init(
        type: NativeSessionEventType,
        seq: Int,
        timeMS: Int64,
        turn: Int? = nil,
        step: Int? = nil,
        text: String? = nil,
        toolCallID: String? = nil,
        toolName: String? = nil,
        argumentsJSON: String? = nil,
        isError: Bool = false,
        finishReason: NativeTurnEndReason? = nil,
        chunk: NativeStreamChunk? = nil,
        replaceStart: Int? = nil,
        replaceEnd: Int? = nil,
        imageMediaType: String? = nil,
        imageBase64: String? = nil
    ) {
        self.type = type
        self.seq = seq
        self.timeMS = timeMS
        self.turn = turn
        self.step = step
        self.text = text
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.isError = isError
        self.finishReason = finishReason
        self.chunk = chunk
        self.replaceStart = replaceStart
        self.replaceEnd = replaceEnd
        self.imageMediaType = imageMediaType
        self.imageBase64 = imageBase64
    }

    public var imagePart: NativeImagePart? {
        guard let imageMediaType,
              let imageBase64,
              let data = Data(base64Encoded: imageBase64),
              !data.isEmpty else { return nil }
        return NativeImagePart(mediaType: imageMediaType, data: data)
    }
}

public struct NativeImagePart: Equatable, Sendable {
    public var mediaType: String
    public var data: Data

    public init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }

    public var base64: String { data.base64EncodedString() }

    public var dataURL: String { "data:\(mediaType);base64,\(base64)" }
}

public struct NativeModelMessage: Equatable, Sendable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var content: String
    public var toolCallID: String?
    public var toolCalls: [NativeToolCall]?
    public var images: [NativeImagePart]

    public init(
        role: Role,
        content: String,
        toolCallID: String? = nil,
        toolCalls: [NativeToolCall]? = nil,
        images: [NativeImagePart] = []
    ) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.images = images
    }
}

public struct NativeToolCall: Equatable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}
