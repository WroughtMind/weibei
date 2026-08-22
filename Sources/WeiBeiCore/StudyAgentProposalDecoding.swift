import Foundation

/// Shared proposal-details decoders used by Pi RPC and Native applySideEffects.
/// Shape only — no mechanical limits.
public enum StudyAgentProposalDecoding {
    public static func noteProposal(from details: [String: Any]) -> StudyAgentNoteProposal? {
        guard details["kind"] as? String == "note_proposal",
              let markdown = details["markdown"] as? String,
              let revision = details["contextRevision"] as? String else {
            return nil
        }
        let evidence: [String]
        if let list = details["evidence"] as? [String] {
            evidence = list
        } else if let single = details["evidence"] as? String, !single.isEmpty {
            evidence = [single]
        } else {
            evidence = []
        }
        return StudyAgentNoteProposal(
            markdown: markdown,
            evidence: evidence,
            contextRevision: revision
        )
    }

    public static func relationProposal(from details: [String: Any]) -> StudyAgentRelationProposal? {
        guard details["kind"] as? String == "relation_proposal",
              let noteItemID = details["noteItemID"] as? String,
              let sourceItemID = details["sourceItemID"] as? String,
              let revision = details["contextRevision"] as? String else {
            return nil
        }
        return StudyAgentRelationProposal(
            noteItemID: noteItemID,
            sourceItemID: sourceItemID,
            contextRevision: revision
        )
    }

    public static func learningUpdate(from details: [String: Any]) -> StudyAgentLearningUpdate? {
        guard details["kind"] as? String == "learning_update",
              let revision = details["contextRevision"] as? String,
              let memoryRevision = uint64(details["memoryRevision"]),
              let rawEntries = details["entries"] as? [Any],
              let rawResolutions = details["resolutions"] as? [Any],
              let suggestedNext = details["suggestedNext"] as? [String] else {
            return nil
        }
        let sessionSummary: String?
        if let raw = details["sessionSummary"] {
            guard let value = raw as? String else { return nil }
            sessionSummary = value
        } else {
            sessionSummary = nil
        }
        let suggestedPhase: StudyPhase?
        if let raw = details["suggestedPhase"] {
            guard let value = raw as? String, let phase = StudyPhase(rawValue: value) else { return nil }
            suggestedPhase = phase
        } else {
            suggestedPhase = nil
        }
        var entries: [StudyAgentMemoryUpdateEntry] = []
        for rawEntry in rawEntries {
            guard let entry = rawEntry as? [String: Any],
                  let kindRaw = entry["kind"] as? String,
                  let kind = LearningMemoryKind(rawValue: kindRaw),
                  let text = entry["text"] as? String,
                  let evidence = entry["evidence"] as? String,
                  let originRaw = entry["origin"] as? String,
                  let origin = LearningMemoryOrigin(rawValue: originRaw) else {
                return nil
            }
            let memoryID: String?
            if let rawMemoryID = entry["memoryID"] {
                guard let value = rawMemoryID as? String else { return nil }
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
        for rawResolution in rawResolutions {
            guard let resolution = rawResolution as? [String: Any],
                  let memoryID = resolution["memoryID"] as? String,
                  let text = resolution["text"] as? String ?? resolution["evidence"] as? String,
                  let evidence = resolution["evidence"] as? String else {
                return nil
            }
            resolutions.append(
                StudyAgentMemoryResolution(memoryID: memoryID, text: text, evidence: evidence)
            )
        }
        return StudyAgentLearningUpdate(
            contextRevision: revision,
            memoryRevision: memoryRevision,
            sessionSummary: sessionSummary,
            suggestedPhase: suggestedPhase,
            suggestedNext: suggestedNext,
            entries: entries,
            resolutions: resolutions
        )
    }

    public static func courseProfileUpdate(from details: [String: Any]) -> StudyAgentCourseProfileUpdate? {
        guard details["kind"] as? String == "course_profile_update",
              let revision = details["contextRevision"] as? String,
              let profileRevision = uint64(details["profileRevision"]),
              let checkpoint = details["checkpoint"] as? String else {
            return nil
        }
        let rawEntries: [Any]
        if let typed = details["entries"] as? [[String: Any]] {
            rawEntries = typed
        } else if let any = details["entries"] as? [Any] {
            rawEntries = any
        } else if details["entries"] == nil {
            rawEntries = []
        } else {
            return nil
        }
        let removedEntryIDs: [String]
        if let ids = details["removedEntryIDs"] as? [String] {
            removedEntryIDs = ids
        } else if details["removedEntryIDs"] == nil {
            removedEntryIDs = []
        } else {
            return nil
        }
        var entries: [StudyAgentCourseProfileUpdateEntry] = []
        for raw in rawEntries {
            guard let rawEntry = raw as? [String: Any],
                  let kindRaw = rawEntry["kind"] as? String,
                  let kind = CourseKnowledgeProfileEntryKind(rawValue: kindRaw),
                  let text = rawEntry["text"] as? String else {
                return nil
            }
            let rawSources = rawEntry["sources"] as? [[String: Any]]
                ?? (rawEntry["sources"] as? [Any])?.compactMap { $0 as? [String: Any] }
                ?? []
            var sources: [StudyAgentCourseProfileSource] = []
            for rawSource in rawSources {
                guard let itemID = rawSource["itemID"] as? String,
                      let role = rawSource["role"] as? String,
                      let sourceRevision = rawSource["sourceRevision"] as? String else {
                    return nil
                }
                let location: String?
                if let rawLocation = rawSource["location"] {
                    guard let value = rawLocation as? String else { return nil }
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
        return StudyAgentCourseProfileUpdate(
            contextRevision: revision,
            profileRevision: profileRevision,
            checkpoint: checkpoint,
            entries: entries,
            removedEntryIDs: removedEntryIDs
        )
    }

    private static func uint64(_ raw: Any?) -> UInt64? {
        if let number = raw as? NSNumber, !(raw is Bool), number.int64Value >= 0 {
            return number.uint64Value
        }
        if let value = raw as? UInt64 { return value }
        if let value = raw as? Int, value >= 0 { return UInt64(value) }
        return nil
    }
}
