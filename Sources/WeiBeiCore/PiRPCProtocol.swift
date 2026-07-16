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

public enum PiRPCRunActivity: Equatable, Sendable {
    case thinking
    case tool
    case retrying
}

public enum PiRPCIncomingMessage: Equatable, Sendable {
    case response(PiRPCResponse)
    case textDelta(String)
    case runActivity(PiRPCRunActivity)
    case assistantError(String)
    case toolStarted(id: String, name: String)
    case contextRead(id: String, contextRevision: String)
    case courseSourcesRead(id: String, contextRevision: String, labels: [String], assetIDs: [String], jumpEvidence: [String: String])
    case learningMemoryRead(id: String, contextRevision: String, memoryRevision: UInt64, labels: [String], jumpEvidence: [String: String])
    case richAnswer(id: String, data: Data)
    case noteProposal(id: String, StudyAgentNoteProposal)
    case learningUpdate(id: String, StudyAgentLearningUpdate)
    case toolFailed(id: String, name: String, message: String)
    case agentEnded(text: String, stopReason: String?, error: String?)
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
            if ["thinking_start", "thinking_delta", "thinking_end"].contains(eventType) {
                return .runActivity(.thinking)
            }
            if eventType == "error" {
                let reason = event["error"] as? String
                    ?? event["reason"] as? String
                    ?? "PI agent request failed"
                return .assistantError(reason)
            }
            return .event(eventType)

        case "auto_retry_start", "auto_retry_end":
            return .runActivity(.retrying)

        case "tool_execution_update":
            return .runActivity(.tool)

        case "message_end", "turn_end":
            guard let message = object["message"] as? [String: Any],
                  message["role"] as? String == "assistant",
                  message["stopReason"] as? String == "error",
                  let error = assistantError(in: message) else {
                return .event(type)
            }
            return .assistantError(error)

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
            if name == "weibei_course_search",
               let details = result?["details"] as? [String: Any],
               let contextRevision = details["contextRevision"] as? String {
                let entries = (details["catalog"] as? [[String: Any]])
                    ?? (details["results"] as? [[String: Any]])
                    ?? []
                let legacyLabels = entries.compactMap { entry -> String? in
                    guard let title = entry["title"] as? String,
                          let role = entry["role"] as? String,
                          role == "material" || role == "note",
                          let searchText = entry["searchText"] as? String,
                          !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    return role == "note" ? "[笔记：\(title)]" : "[材料：\(title)]"
                }
                return .courseSourcesRead(
                    id: object["toolCallId"] as? String ?? "",
                    contextRevision: contextRevision,
                    labels: details["evidenceLabels"] as? [String] ?? legacyLabels,
                    assetIDs: entries.compactMap { entry in
                        guard let id = entry["id"] as? String,
                              let searchText = entry["searchText"] as? String,
                              !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return nil
                        }
                        return id
                    },
                    jumpEvidence: details["jumpEvidence"] as? [String: String] ?? [:]
                )
            }
            if name == "weibei_learning_memory",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "learning_memory",
               let contextRevision = details["contextRevision"] as? String,
               let memoryRevision = details["memoryRevision"] as? NSNumber {
                let learning = details["learning"] as? [String: Any] ?? [:]
                var labels: [String] = []
                if learning["lastLocation"] is [String: Any] {
                    labels.append("[学习记录：上次位置]")
                }
                if let memories = learning["memories"] as? [[String: Any]], !memories.isEmpty {
                    labels.append("[学习记忆：用户状态]")
                }
                if learning["session"] is [String: Any] {
                    labels.append("[会话：当前]")
                }
                if labels.isEmpty {
                    labels.append("[学习记忆：无记录]")
                }
                return .learningMemoryRead(
                    id: object["toolCallId"] as? String ?? "",
                    contextRevision: contextRevision,
                    memoryRevision: memoryRevision.uint64Value,
                    labels: labels,
                    jumpEvidence: details["jumpEvidence"] as? [String: String] ?? [:]
                )
            }
            if name == "weibei_rich_answer",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "rich_answer",
               let envelopeData = jsonData(details["envelope"]) {
                return .richAnswer(
                    id: object["toolCallId"] as? String ?? "",
                    data: envelopeData
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
            if name == "weibei_learning_update",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "learning_update",
               let revision = details["contextRevision"] as? String,
               let memoryRevision = details["memoryRevision"] as? NSNumber {
                let entries = (details["entries"] as? [[String: Any]] ?? []).compactMap { entry -> StudyAgentMemoryUpdateEntry? in
                    guard let kindRaw = entry["kind"] as? String,
                          let kind = LearningMemoryKind(rawValue: kindRaw),
                          let text = entry["text"] as? String,
                          let evidence = entry["evidence"] as? String,
                          let originRaw = entry["origin"] as? String,
                          let origin = LearningMemoryOrigin(rawValue: originRaw) else { return nil }
                    return StudyAgentMemoryUpdateEntry(
                        kind: kind,
                        text: text,
                        evidence: evidence,
                        origin: origin
                    )
                }
                let resolutions = (details["resolutions"] as? [[String: Any]] ?? []).compactMap { resolution -> StudyAgentMemoryResolution? in
                    guard let memoryID = resolution["memoryID"] as? String,
                          let text = resolution["text"] as? String,
                          let evidence = resolution["evidence"] as? String else { return nil }
                    return StudyAgentMemoryResolution(
                        memoryID: memoryID,
                        text: text,
                        evidence: evidence
                    )
                }
                return .learningUpdate(
                    id: object["toolCallId"] as? String ?? "",
                    StudyAgentLearningUpdate(
                        contextRevision: revision,
                        memoryRevision: memoryRevision.uint64Value,
                        sessionSummary: details["sessionSummary"] as? String,
                        suggestedPhase: (details["suggestedPhase"] as? String).flatMap(StudyPhase.init(rawValue:)),
                        suggestedNext: details["suggestedNext"] as? [String] ?? [],
                        entries: entries,
                        resolutions: resolutions
                    )
                )
            }
            return .event(type)

        case "agent_end":
            let messages = object["messages"] as? [[String: Any]] ?? []
            var finalText = ""
            var stopReason: String?
            var finalError: String?
            for message in messages where message["role"] as? String == "assistant" {
                let text = assistantText(in: message)
                if !text.isEmpty { finalText = text }
                stopReason = message["stopReason"] as? String ?? stopReason
                finalError = assistantError(in: message) ?? finalError
            }
            return .agentEnded(text: finalText, stopReason: stopReason, error: finalError)

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

    private static func assistantError(in message: [String: Any]) -> String? {
        if let errorMessage = nonEmptyString(message["errorMessage"]) {
            return errorMessage
        }
        let diagnostics = message["diagnostics"] as? [[String: Any]] ?? []
        for diagnostic in diagnostics.reversed() {
            if let error = diagnostic["error"] as? [String: Any],
               let message = nonEmptyString(error["message"]) {
                return message
            }
            if let message = nonEmptyString(diagnostic["message"]) {
                return message
            }
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
