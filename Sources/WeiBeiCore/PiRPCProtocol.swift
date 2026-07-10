import Foundation

public enum PiRPCProtocolError: LocalizedError, Equatable, Sendable {
    case lineTooLarge(Int)
    case incompleteLine
    case invalidJSON
    case invalidEnvelope

    public var errorDescription: String? {
        switch self {
        case let .lineTooLarge(size):
            return "PI RPC line exceeded the size limit (\(size) bytes)"
        case .incompleteLine:
            return "PI RPC ended with an incomplete JSONL record"
        case .invalidJSON:
            return "PI RPC emitted invalid JSON"
        case .invalidEnvelope:
            return "PI RPC emitted an invalid envelope"
        }
    }
}

public struct PiJSONLFramer: Sendable {
    public var maximumLineBytes: Int
    private var buffer = Data()

    public init(maximumLineBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumLineBytes = maximumLineBytes
    }

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        guard buffer.count <= maximumLineBytes || buffer.contains(0x0A) else {
            throw PiRPCProtocolError.lineTooLarge(buffer.count)
        }

        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            if line.count > maximumLineBytes {
                throw PiRPCProtocolError.lineTooLarge(line.count)
            }
            if !line.isEmpty { lines.append(line) }
        }

        if buffer.count > maximumLineBytes {
            throw PiRPCProtocolError.lineTooLarge(buffer.count)
        }
        return lines
    }

    public mutating func finish() throws -> [Data] {
        guard buffer.isEmpty else { throw PiRPCProtocolError.incompleteLine }
        return []
    }
}

public struct PiRPCResponse: Equatable, Sendable {
    public var id: String?
    public var command: String
    public var success: Bool
    public var error: String?
    public var dataJSON: Data?

    public init(id: String?, command: String, success: Bool, error: String?, dataJSON: Data? = nil) {
        self.id = id
        self.command = command
        self.success = success
        self.error = error
        self.dataJSON = dataJSON
    }
}

public enum PiRPCIncomingMessage: Equatable, Sendable {
    case response(PiRPCResponse)
    case textDelta(String)
    case assistantError(String)
    case toolStarted(id: String, name: String)
    case contextRead(id: String, contextRevision: String)
    case noteProposal(id: String, StudyAgentNoteProposal)
    case toolFailed(id: String, name: String, message: String)
    case agentEnded(text: String, stopReason: String?)
    case extensionError(String)
    case event(String)
}

public enum PiRPCMessageDecoder {
    public static func decode(_ data: Data) throws -> PiRPCIncomingMessage {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PiRPCProtocolError.invalidJSON
        }
        guard let object = value as? [String: Any], let type = object["type"] as? String else {
            throw PiRPCProtocolError.invalidEnvelope
        }

        switch type {
        case "response":
            guard let command = object["command"] as? String,
                  let success = object["success"] as? Bool else {
                throw PiRPCProtocolError.invalidEnvelope
            }
            return .response(
                PiRPCResponse(
                    id: object["id"] as? String,
                    command: command,
                    success: success,
                    error: object["error"] as? String,
                    dataJSON: jsonData(object["data"])
                )
            )

        case "message_update":
            guard let event = object["assistantMessageEvent"] as? [String: Any],
                  let eventType = event["type"] as? String else {
                return .event(type)
            }
            if eventType == "text_delta", let delta = event["delta"] as? String {
                return .textDelta(delta)
            }
            if eventType == "error" {
                let reason = event["error"] as? String
                    ?? event["reason"] as? String
                    ?? "PI agent request failed"
                return .assistantError(reason)
            }
            return .event(eventType)

        case "tool_execution_start":
            guard let name = object["toolName"] as? String else {
                throw PiRPCProtocolError.invalidEnvelope
            }
            return .toolStarted(id: object["toolCallId"] as? String ?? "", name: name)

        case "tool_execution_end":
            let name = object["toolName"] as? String ?? "unknown"
            let isError = object["isError"] as? Bool ?? false
            let result = object["result"] as? [String: Any]
            if isError {
                return .toolFailed(
                    id: object["toolCallId"] as? String ?? "",
                    name: name,
                    message: firstText(in: result) ?? "Tool failed"
                )
            }
            if name == "weibei_context",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "weibei_context",
               let revision = details["contextRevision"] as? String {
                return .contextRead(
                    id: object["toolCallId"] as? String ?? "",
                    contextRevision: revision
                )
            }
            if name == "weibei_note_proposal",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "note_proposal",
               let markdown = details["markdown"] as? String,
               let revision = details["contextRevision"] as? String {
                return .noteProposal(
                    id: object["toolCallId"] as? String ?? "",
                    StudyAgentNoteProposal(
                        markdown: markdown,
                        evidence: details["evidence"] as? [String] ?? [],
                        contextRevision: revision
                    )
                )
            }
            return .event(type)

        case "agent_end":
            let messages = object["messages"] as? [[String: Any]] ?? []
            var finalText = ""
            var stopReason: String?
            for message in messages where message["role"] as? String == "assistant" {
                let text = assistantText(in: message)
                if !text.isEmpty { finalText = text }
                stopReason = message["stopReason"] as? String ?? stopReason
            }
            return .agentEnded(text: finalText, stopReason: stopReason)

        case "extension_error":
            let path = object["extensionPath"] as? String ?? "WeiBei extension"
            let event = object["event"] as? String ?? "event"
            let message = object["error"] as? String ?? "Unknown extension error"
            return .extensionError("\(path) [\(event)]: \(message)")

        default:
            return .event(type)
        }
    }

    private static func assistantText(in message: [String: Any]) -> String {
        let content = message["content"] as? [[String: Any]] ?? []
        return content.compactMap { item in
            guard item["type"] as? String == "text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstText(in result: [String: Any]?) -> String? {
        let content = result?["content"] as? [[String: Any]] ?? []
        return content.compactMap { $0["text"] as? String }.first
    }

    private static func jsonData(_ value: Any?) -> Data? {
        guard let value, JSONSerialization.isValidJSONObject(value) else { return nil }
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
