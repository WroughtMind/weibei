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

public struct PiRPCExtensionUIRequest: Equatable, Sendable {
    public var id: String
    public var method: String
    public var title: String?
    public var message: String?
    public var placeholder: String?
    public var options: [String]
    public var notifyType: String?
}

public enum PiRPCIncomingMessage: Equatable, Sendable {
    case response(PiRPCResponse)
    case textDelta(String)
    case runActivity(PiRPCRunActivity)
    case assistantError(String)
    case extensionUIRequest(PiRPCExtensionUIRequest)
    case toolStarted(id: String, name: String, argumentsJSON: Data?)
    case courseSourcesRead(
        id: String,
        toolName: String,
        contextRevision: String,
        labels: [String],
        assetIDs: [String],
        sourceRevisions: [String: String],
        jumpEvidence: [String: String],
        sources: [AgentReplySource]
    )
    case visualAssetRead(id: String, contextRevision: String, assetID: String, sha256: String, byteCount: Int)
    case learningMemoryRead(id: String, contextRevision: String, memoryRevision: UInt64, labels: [String], jumpEvidence: [String: String])
    case skillsLoaded(id: String, contextRevision: String, skills: [StudyAgentLoadedSkill])
    case artifactComputed(
        id: String,
        contextRevision: String,
        requestID: String,
        operation: String,
        workerVersion: String,
        requestSHA256: String,
        outputSHA256: String,
        artifactSHA256s: [String],
        durationMS: Int
    )
    case richAnswer(id: String, data: Data)
    case visualization(id: String, fragment: AgentVisualization)
    case noteProposal(id: String, StudyAgentNoteProposal)
    case relationProposal(id: String, StudyAgentRelationProposal)
    case learningUpdate(id: String, StudyAgentLearningUpdate)
    case courseProfileUpdate(id: String, StudyAgentCourseProfileUpdate)
    case toolFailed(id: String, name: String, message: String)
    case agentEnded(text: String, stopReason: String?, error: String?, provider: String?, model: String?)
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

        case "extension_ui_request":
            guard let id = object["id"] as? String,
                  !id.isEmpty,
                  id.utf8.count <= 256,
                  let method = object["method"] as? String,
                  method.utf8.count <= 64 else {
                throw PiRPCProtocolError.invalidEnvelope
            }
            let title = object["title"] as? String
            let message = object["message"] as? String
            let placeholder = object["placeholder"] as? String
            let options = object["options"] as? [String] ?? []
            guard [title, message, placeholder].compactMap({ $0 }).allSatisfy({ $0.utf8.count <= 8 * 1_024 * 1_024 }),
                  options.count <= 100,
                  options.allSatisfy({ $0.utf8.count <= 16_384 }) else {
                throw PiRPCProtocolError.invalidEnvelope
            }
            return .extensionUIRequest(
                PiRPCExtensionUIRequest(
                    id: id,
                    method: method,
                    title: title,
                    message: message,
                    placeholder: placeholder,
                    options: options,
                    notifyType: object["notifyType"] as? String
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
            let argumentsJSON = jsonData(object["args"])
            let maximumArgumentBytes = name == "weibei_visualize"
                ? 1_100_000
                : 16_384
            guard argumentsJSON?.count ?? 0 <= maximumArgumentBytes else {
                throw PiRPCProtocolError.invalidEnvelope
            }
            return .toolStarted(
                id: object["toolCallId"] as? String ?? "",
                name: name,
                argumentsJSON: argumentsJSON
            )

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
            if name == "weibei_visualize",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "weibei_visualization",
               let id = details["id"] as? String,
               let spec = details["spec"] as? [String: Any],
               let items = spec["items"] as? [Any],
               !items.isEmpty,
               JSONSerialization.isValidJSONObject(spec),
               let specData = try? JSONSerialization.data(
                   withJSONObject: spec,
                   options: [.sortedKeys]
               ),
               let specJSON = String(data: specData, encoding: .utf8),
               !id.isEmpty,
               id.utf8.count <= 128,
               id == id.lowercased(),
               id.first != "-",
               id.last != "-",
               !id.contains("--"),
               id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
               specData.count <= 1_000_000 {
                return .visualization(
                    id: object["toolCallId"] as? String ?? "",
                    fragment: AgentVisualization(
                        id: id,
                        specJSON: specJSON,
                        surface: AgentVisualizationSurface(
                            rawValue: details["surface"] as? String ?? "inline"
                        ) ?? .inline
                    )
                )
            }
            if name == "weibei_visualize" {
                throw PiRPCProtocolError.invalidEnvelope
            }
            if ["weibei_course_search", "weibei_course_read"].contains(name),
               let details = result?["details"] as? [String: Any],
               ["course_search", "course_read"].contains(details["kind"] as? String ?? ""),
               let contextRevision = details["contextRevision"] as? String {
                let entries = (details["catalog"] as? [[String: Any]])
                    ?? (details["results"] as? [[String: Any]])
                    ?? []
                let readableEntries = entries.filter { entry in
                    guard let searchText = entry["searchText"] as? String else { return false }
                    return !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
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
                let labels = details["evidenceLabels"] as? [String] ?? legacyLabels
                let jumpEvidence = details["jumpEvidence"] as? [String: String] ?? [:]
                let sources = zip(readableEntries, labels).compactMap { entry, label -> AgentReplySource? in
                    guard let itemID = entry["id"] as? String,
                          let title = entry["title"] as? String,
                          let role = entry["role"] as? String,
                          let searchText = entry["searchText"] as? String else { return nil }
                    let reference = jumpEvidence
                        .filter { $0.value == label }
                        .map(\.key)
                        .max { left, right in
                            left.components(separatedBy: "，").count
                                < right.components(separatedBy: "，").count
                        }
                    let parsed = SourceReferenceTitle.parse(reference ?? title)
                    return AgentReplySource(
                        itemID: itemID,
                        courseID: (entry["courseIDs"] as? [String])?
                            .first
                            .flatMap(UUID.init(uuidString:)),
                        kind: role == "note" ? .note : .material,
                        title: parsed.title.isEmpty ? title : parsed.title,
                        label: label,
                        excerpt: String(searchText.prefix(400)),
                        pageIndex: parsed.pageIndex,
                        sectionTitle: parsed.sectionTitle,
                        sectionLocationID: parsed.sectionLocationID,
                        sectionOrdinal: parsed.sectionOrdinal,
                        courseItemOrdinal: parsed.courseItemOrdinal
                    )
                }
                return .courseSourcesRead(
                    id: object["toolCallId"] as? String ?? "",
                    toolName: name,
                    contextRevision: contextRevision,
                    labels: labels,
                    assetIDs: readableEntries.compactMap { entry in
                        guard let id = entry["id"] as? String,
                              let searchText = entry["searchText"] as? String,
                              !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return nil
                        }
                        return id
                    },
                    sourceRevisions: Dictionary(
                        uniqueKeysWithValues: readableEntries.compactMap { entry in
                            guard let id = entry["id"] as? String,
                                  let revision = entry["sourceRevision"] as? String else {
                                return nil
                            }
                            return (id, revision)
                        }
                    ),
                    jumpEvidence: jumpEvidence,
                    sources: sources
                )
            }
            if name == "weibei_visual_asset",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "visual_asset_read",
               let contextRevision = details["contextRevision"] as? String,
               let assetID = details["assetID"] as? String,
               let sha256 = details["sha256"] as? String,
               let byteCount = details["byteCount"] as? NSNumber {
                return .visualAssetRead(
                    id: object["toolCallId"] as? String ?? "",
                    contextRevision: contextRevision,
                    assetID: assetID,
                    sha256: sha256,
                    byteCount: byteCount.intValue
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
            if name == "read",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "weibei_skill_read",
               let contextRevision = details["contextRevision"] as? String,
               let entry = details["loaded"] as? [String: Any],
               let id = entry["id"] as? String,
               let skillName = entry["name"] as? String,
               let version = entry["version"] as? String,
               let sha256 = entry["sha256"] as? String,
               let byteCount = entry["byteCount"] as? NSNumber,
               let relativePath = entry["relativePath"] as? String,
               let loadedAtContextRevision = entry["loadedAtContextRevision"] as? String {
                let skill = StudyAgentLoadedSkill(
                    id: id,
                    name: skillName,
                    version: version,
                    sha256: sha256,
                    byteCount: byteCount.intValue,
                    relativePath: relativePath,
                    loadedAtContextRevision: loadedAtContextRevision
                )
                return .skillsLoaded(
                    id: object["toolCallId"] as? String ?? "",
                    contextRevision: contextRevision,
                    skills: [skill]
                )
            }
            if name == "weibei_compute_artifact",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "compute_artifact",
               let contextRevision = details["contextRevision"] as? String,
               let requestID = details["requestID"] as? String,
               let operation = details["operation"] as? String,
               let workerVersion = details["workerVersion"] as? String,
               let requestSHA256 = details["requestSHA256"] as? String,
               let outputSHA256 = details["outputSHA256"] as? String,
               let durationMS = details["durationMS"] as? NSNumber {
                let artifactSHA256s = (details["artifacts"] as? [[String: Any]] ?? [])
                    .compactMap { $0["sha256"] as? String }
                return .artifactComputed(
                    id: object["toolCallId"] as? String ?? "",
                    contextRevision: contextRevision,
                    requestID: requestID,
                    operation: operation,
                    workerVersion: workerVersion,
                    requestSHA256: requestSHA256,
                    outputSHA256: outputSHA256,
                    artifactSHA256s: artifactSHA256s,
                    durationMS: durationMS.intValue
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
            if name == "weibei_relation_proposal",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "relation_proposal",
               let noteItemID = details["noteItemID"] as? String,
               let sourceItemID = details["sourceItemID"] as? String,
               let revision = details["contextRevision"] as? String {
                return .relationProposal(
                    id: object["toolCallId"] as? String ?? "",
                    StudyAgentRelationProposal(
                        noteItemID: noteItemID,
                        sourceItemID: sourceItemID,
                        contextRevision: revision
                    )
                )
            }
            if name == "weibei_learning_update",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "learning_update",
               let revision = details["contextRevision"] as? String,
               let memoryRevision = details["memoryRevision"] as? NSNumber,
               memoryRevision.int64Value >= 0,
               let rawEntries = details["entries"] as? [Any],
               let rawResolutions = details["resolutions"] as? [Any],
               let suggestedNext = details["suggestedNext"] as? [String] {
                let sessionSummary: String?
                if let rawSessionSummary = details["sessionSummary"] {
                    guard let value = rawSessionSummary as? String else {
                        return .event(type)
                    }
                    sessionSummary = value
                } else {
                    sessionSummary = nil
                }

                let suggestedPhase: StudyPhase?
                if let rawSuggestedPhase = details["suggestedPhase"] {
                    guard let value = rawSuggestedPhase as? String,
                          let phase = StudyPhase(rawValue: value) else {
                        return .event(type)
                    }
                    suggestedPhase = phase
                } else {
                    suggestedPhase = nil
                }

                var entries: [StudyAgentMemoryUpdateEntry] = []
                entries.reserveCapacity(rawEntries.count)
                for rawEntry in rawEntries {
                    guard let entry = rawEntry as? [String: Any],
                          let kindRaw = entry["kind"] as? String,
                          let kind = LearningMemoryKind(rawValue: kindRaw),
                          let text = entry["text"] as? String,
                          let evidence = entry["evidence"] as? String,
                          let originRaw = entry["origin"] as? String,
                          let origin = LearningMemoryOrigin(rawValue: originRaw) else {
                        return .event(type)
                    }
                    let memoryID: String?
                    if let rawMemoryID = entry["memoryID"] {
                        guard let value = rawMemoryID as? String else {
                            return .event(type)
                        }
                        memoryID = value
                    } else {
                        memoryID = nil
                    }
                    entries.append(
                        StudyAgentMemoryUpdateEntry(
                            memoryID: memoryID,
                            kind: kind,
                            text: text,
                            evidence: evidence,
                            origin: origin
                        )
                    )
                }

                var resolutions: [StudyAgentMemoryResolution] = []
                resolutions.reserveCapacity(rawResolutions.count)
                for rawResolution in rawResolutions {
                    guard let resolution = rawResolution as? [String: Any],
                          let memoryID = resolution["memoryID"] as? String,
                          let text = resolution["text"] as? String,
                          let evidence = resolution["evidence"] as? String else {
                        return .event(type)
                    }
                    resolutions.append(
                        StudyAgentMemoryResolution(
                            memoryID: memoryID,
                            text: text,
                            evidence: evidence
                        )
                    )
                }

                return .learningUpdate(
                    id: object["toolCallId"] as? String ?? "",
                    StudyAgentLearningUpdate(
                        contextRevision: revision,
                        memoryRevision: memoryRevision.uint64Value,
                        sessionSummary: sessionSummary,
                        suggestedPhase: suggestedPhase,
                        suggestedNext: suggestedNext,
                        entries: entries,
                        resolutions: resolutions
                    )
                )
            }
            if name == "weibei_course_profile_update",
               let details = result?["details"] as? [String: Any],
               details["kind"] as? String == "course_profile_update",
               let revision = details["contextRevision"] as? String,
               let profileRevision = details["profileRevision"] as? NSNumber,
               profileRevision.int64Value >= 0,
               let checkpoint = details["checkpoint"] as? String,
               let rawEntries = details["entries"] as? [[String: Any]],
               let removedEntryIDs = details["removedEntryIDs"] as? [String] {
                var entries: [StudyAgentCourseProfileUpdateEntry] = []
                for rawEntry in rawEntries {
                    guard let kindRaw = rawEntry["kind"] as? String,
                          let kind = CourseKnowledgeProfileEntryKind(rawValue: kindRaw),
                          let text = rawEntry["text"] as? String,
                          let rawSources = rawEntry["sources"] as? [[String: Any]] else {
                        return .event(type)
                    }
                    var sources: [StudyAgentCourseProfileSource] = []
                    for rawSource in rawSources {
                        guard let itemID = rawSource["itemID"] as? String,
                              let role = rawSource["role"] as? String,
                              let sourceRevision = rawSource["sourceRevision"] as? String else {
                            return .event(type)
                        }
                        let location: String?
                        if let rawLocation = rawSource["location"] {
                            guard let value = rawLocation as? String else {
                                return .event(type)
                            }
                            location = value
                        } else {
                            location = nil
                        }
                        sources.append(
                            StudyAgentCourseProfileSource(
                                itemID: itemID,
                                role: role,
                                location: location,
                                sourceRevision: sourceRevision
                            )
                        )
                    }
                    entries.append(
                        StudyAgentCourseProfileUpdateEntry(
                            entryID: rawEntry["entryID"] as? String,
                            kind: kind,
                            text: text,
                            sources: sources
                        )
                    )
                }
                return .courseProfileUpdate(
                    id: object["toolCallId"] as? String ?? "",
                    StudyAgentCourseProfileUpdate(
                        contextRevision: revision,
                        profileRevision: profileRevision.uint64Value,
                        checkpoint: checkpoint,
                        entries: entries,
                        removedEntryIDs: removedEntryIDs
                    )
                )
            }
            return .event(type)

        case "agent_end":
            let messages = object["messages"] as? [[String: Any]] ?? []
            var finalText = ""
            var stopReason: String?
            var finalError: String?
            var provider: String?
            var model: String?
            for message in messages where message["role"] as? String == "assistant" {
                let text = assistantText(in: message)
                if !text.isEmpty { finalText = text }
                stopReason = message["stopReason"] as? String ?? stopReason
                finalError = assistantError(in: message) ?? finalError
                provider = message["provider"] as? String ?? provider
                model = message["model"] as? String ?? model
            }
            return .agentEnded(
                text: finalText,
                stopReason: stopReason,
                error: finalError,
                provider: provider,
                model: model
            )

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
