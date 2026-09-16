import Foundation

struct NativeStateAliases: Sendable {
    private let memoryAliasByID: [String: String]
    private let memoryIDByAlias: [String: String]
    private let profileAliasByID: [String: String]
    private let profileIDByAlias: [String: String]
    private let noteAliasByID: [String: String]
    private let noteIDByAlias: [String: String]
    private let persistedAliases: [String: String]
    private let reservedAliasValues: Set<String>

    init(
        request: StudyAgentRequest,
        persisted: [String: String] = [:],
        reservedAliases: Set<String> = []
    ) {
        let memories = request.learningContext.memories
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
            .map { $0.id.uuidString.lowercased() }
        let memoryMaps = Self.maps(ids: memories, prefix: "m", persisted: persisted, reservedAliases: reservedAliases)
        (memoryAliasByID, memoryIDByAlias) = (memoryMaps.aliases, memoryMaps.idsByAlias)
        let profileMaps = Self.maps(
            ids: request.courseProfile.entries.map(\.id),
            prefix: "e",
            persisted: persisted,
            reservedAliases: reservedAliases
        )
        (profileAliasByID, profileIDByAlias) = (profileMaps.aliases, profileMaps.idsByAlias)
        let noteIDs = request.projectScope.items
            .filter { $0.role == "note" }
            .map(\.itemID)
            + request.courseContext.catalog.filter { $0.role == "note" }.map(\.id)
            + request.courseContext.items.filter { $0.role == "note" }.map(\.id)
            + request.confirmedNotes.map(\.itemID)
        let noteMaps = Self.maps(ids: noteIDs, prefix: "n", persisted: persisted, reservedAliases: reservedAliases)
        (noteAliasByID, noteIDByAlias) = (noteMaps.aliases, noteMaps.idsByAlias)
        persistedAliases = memoryMaps.persisted
            .merging(profileMaps.persisted, uniquingKeysWith: { _, new in new })
            .merging(noteMaps.persisted, uniquingKeysWith: { _, new in new })
        reservedAliasValues = reservedAliases.union(persistedAliases.values)
    }

    static func scopeKey(for request: StudyAgentRequest) -> String {
        if let courseID = request.projectScope.courseID, !courseID.isEmpty { return "course:\(courseID.lowercased())" }
        return "global"
    }

    var persistedSnapshot: [String: String] { persistedAliases }

    func refreshed(for request: StudyAgentRequest) -> NativeStateAliases {
        NativeStateAliases(
            request: request,
            persisted: persistedAliases,
            reservedAliases: reservedAliasValues
        )
    }

    func memoryAlias(for id: String) -> String? { memoryAliasByID[id.lowercased()] }
    func profileAlias(for id: String) -> String? { profileAliasByID[id.lowercased()] }
    func noteAlias(for id: String) -> String? { noteAliasByID[id.lowercased()] }

    func memoryID(for alias: String) -> String? { memoryIDByAlias[alias.lowercased()] }
    func profileID(for alias: String) -> String? { profileIDByAlias[alias.lowercased()] }
    func itemID(for alias: String) -> String? { noteIDByAlias[alias.lowercased()] }

    func projectedLearningContext(_ request: StudyAgentRequest) -> [String: Any] {
        let memories = request.learningContext.memories.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt < $1.createdAt
        }.compactMap { entry -> [String: Any]? in
            guard let alias = memoryAlias(for: entry.id.uuidString) else { return nil }
            var result: [String: Any] = [
                "memoryID": alias,
                "kind": entry.kind.rawValue,
                "text": entry.text,
                "evidence": entry.evidence,
                "origin": entry.origin.rawValue,
                "status": entry.status.rawValue,
            ]
            if let resolutionEvidence = entry.resolutionEvidence, !resolutionEvidence.isEmpty {
                result["resolutionEvidence"] = resolutionEvidence
            }
            return result
        }
        let profileEntries = request.courseProfile.entries.compactMap { entry -> [String: Any]? in
            guard let alias = profileAlias(for: entry.id) else { return nil }
            return ["entryID": alias, "kind": entry.kind, "text": entry.text]
        }
        var result: [String: Any] = [
            "memories": memories,
            "courseProfile": ["entries": profileEntries],
        ]
        if let location = request.learningContext.lastLocation,
           let data = try? JSONEncoder().encode(location),
           var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let itemID = object["itemID"] as? String, let alias = noteAlias(for: itemID) {
                object["itemID"] = alias
            }
            result["lastLocation"] = object
        }
        if let session = request.learningContext.session {
            result["session"] = [
                "title": session.title,
                "summary": session.summary,
                "phase": session.phase,
                "turnCount": session.turnCount,
            ]
        }
        return result
    }

    func projected(_ result: StudyAgentHostToolResult) -> StudyAgentHostToolResult {
        var result = result
        result.items = result.items.map(projected)
        result.coverage = result.coverage?.map(projected)
        if let scopeID = result.scopeID, let alias = noteAlias(for: scopeID) {
            result.scopeID = alias
        }
        return result
    }

    func resolving(_ source: AgentReplySource) -> AgentReplySource {
        var source = source
        if let alias = source.itemID, let realID = itemID(for: alias) {
            source.itemID = realID
        }
        return source
    }

    func projected(_ source: AgentReplySource) -> AgentReplySource {
        var source = source
        if let itemID = source.itemID, let alias = noteAlias(for: itemID) {
            source.itemID = alias
        }
        return source
    }

    func projectedHistory(_ projection: NativeLedgerProjection) -> NativeLedgerProjection {
        let toolNames = projection.records.reduce(into: [String: String]()) { result, record in
            for call in record.message.toolCalls ?? [] { result[call.id] = call.name }
        }
        var projection = projection
        projection.summaryMessage = projection.summaryMessage.map { message in
            var message = message
            message.content = sanitizedText(message.content)
            return message
        }
        projection.records = projection.records.map { record in
            var record = record
            var message = record.message
            if message.role == .user {
                message.content = sanitizedText(message.content)
            } else if message.role == .assistant {
                message.content = sanitizedText(message.content)
            }
            if let calls = message.toolCalls {
                message.toolCalls = calls.map { call in
                    var call = call
                    call.arguments = sanitizedArguments(call.arguments, toolName: call.name)
                    return call
                }
            }
            if message.role == .tool,
               let callID = message.toolCallID,
               let toolName = toolNames[callID] {
                message.content = sanitizedToolResult(message.content, toolName: toolName)
            }
            record.message = message
            return record
        }
        return projection
    }

    private func projected(_ item: StudyAgentHostToolItem) -> StudyAgentHostToolItem {
        var item = item
        if let alias = noteAlias(for: item.item.id) { item.item.id = alias }
        item.item.linkedItemIDs = item.item.linkedItemIDs.map { noteAlias(for: $0) ?? $0 }
        if let source = item.source { item.source = projected(source) }
        return item
    }

    private func sanitizedArguments(_ text: String, toolName: String) -> String {
        guard [
            "weibei_update_learning_memory",
            "weibei_course_profile_update",
            "weibei_note_proposal",
            "weibei_relation_proposal",
        ].contains(toolName),
        let data = text.data(using: .utf8),
        var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return sanitizedText(text)
        }
        object.removeValue(forKey: "contextRevision")
        object.removeValue(forKey: "memoryRevision")
        object.removeValue(forKey: "profileRevision")
        guard let sanitized = replacingStateIDs(in: object) as? [String: Any] else { return "{}" }
        guard let encoded = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: encoded, encoding: .utf8) ?? "{}"
    }

    private func sanitizedToolResult(_ text: String, toolName: String) -> String {
        let hidesUUIDs = [
            "weibei_read_learning_memory",
            "weibei_update_learning_memory",
            "weibei_course_profile_update",
            "weibei_note_proposal",
            "weibei_relation_proposal",
        ].contains(toolName)
        guard hidesUUIDs else { return sanitizedText(text) }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return sanitizedText(text)
        }
        let sanitized = replacingStateIDs(in: object)
        guard let encoded = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]) else {
            return sanitizedText(text)
        }
        return String(data: encoded, encoding: .utf8) ?? "{}"
    }

    private func replacingStateIDs(in value: Any) -> Any {
        if var object = value as? [String: Any] {
            for key in ["contextRevision", "memoryRevision", "profileRevision", "revisions"] {
                object.removeValue(forKey: key)
            }
            if let id = object["id"] as? String {
                if let alias = memoryAlias(for: id) {
                    object.removeValue(forKey: "id")
                    object["memoryID"] = alias
                } else if let alias = profileAlias(for: id) {
                    object.removeValue(forKey: "id")
                    object["entryID"] = alias
                } else if let alias = noteAlias(for: id) {
                    object.removeValue(forKey: "id")
                    object["noteItemID"] = alias
                }
            }
            if let id = object["memoryID"] as? String {
                object["memoryID"] = memoryAlias(for: id) ?? (Self.isUUID(id) ? "已隐藏" : id)
            }
            if let id = object["entryID"] as? String {
                object["entryID"] = profileAlias(for: id) ?? (Self.isUUID(id) ? "已隐藏" : id)
            }
            if let id = object["noteItemID"] as? String {
                object["noteItemID"] = noteAlias(for: id) ?? (Self.isUUID(id) ? "已隐藏" : id)
            }
            return object.mapValues(replacingStateIDs)
        }
        if let array = value as? [Any] { return array.map(replacingStateIDs) }
        if let string = value as? String {
            return sanitizedText(string)
        }
        return value
    }

    private func sanitizedText(_ text: String) -> String {
        var text = text
        for (id, alias) in memoryAliasByID.merging(profileAliasByID, uniquingKeysWith: { left, _ in left })
            .merging(noteAliasByID, uniquingKeysWith: { left, _ in left }) {
            text = text.replacingOccurrences(of: id, with: alias, options: .caseInsensitive)
        }
        text = text.replacingOccurrences(
            of: #"(?m)^本轮 contextRevision 是 `[^`]+`。.*(?:\n|$)"#,
            with: "",
            options: .regularExpression
        )
        return text
    }

    private static func maps(
        ids: [String],
        prefix: String,
        persisted: [String: String],
        reservedAliases: Set<String>
    ) -> (aliases: [String: String], idsByAlias: [String: String], persisted: [String: String]) {
        var aliases: [String: String] = [:]
        var idsByAlias: [String: String] = [:]
        var persistedForPrefix: [String: String] = [:]
        var used = Set(reservedAliases.filter { aliasIndex($0, prefix: prefix) != nil })
        for (id, alias) in persisted.sorted(by: { $0.key < $1.key }) {
            guard aliasIndex(alias, prefix: prefix) != nil,
                  !persistedForPrefix.values.contains(alias) else { continue }
            persistedForPrefix[id.lowercased()] = alias
            used.insert(alias)
        }
        for id in ids {
            let normalized = id.lowercased()
            guard aliases[normalized] == nil else { continue }
            let alias: String
            if let existing = persistedForPrefix[normalized] {
                alias = existing
            } else {
                var index = 1
                while used.contains("\(prefix)\(index)") { index += 1 }
                alias = "\(prefix)\(index)"
                persistedForPrefix[normalized] = alias
                used.insert(alias)
            }
            aliases[normalized] = alias
            idsByAlias[alias] = id
        }
        return (persistedForPrefix, idsByAlias, persistedForPrefix)
    }

    private static func aliasIndex(_ alias: String, prefix: String) -> Int? {
        guard alias.hasPrefix(prefix),
              let index = Int(alias.dropFirst(prefix.count)),
              index > 0 else { return nil }
        return index
    }

    private static func isUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}
