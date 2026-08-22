import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func applyLearningUpdate(
        _ update: StudyAgentLearningUpdate?,
        expectedContextRevision: String,
        expectedMemoryRevision: UInt64,
        expectedUserQuestion: String,
        target: AgentConversationTarget,
        messageID: UUID
    ) -> AgentReplyMemoryUpdate? {
        if activeStudySessionID == target.sessionID {
            latestAgentLearningUpdate = nil
        }
        guard let courseID = target.courseID,
              activeCourseRemovalTokens[courseID] == nil,
              let update,
              update.contextRevision == expectedContextRevision,
              update.memoryRevision == expectedMemoryRevision,
              learningMemoryContextRevision(courseID: target.courseID)
                == expectedMemoryRevision,
              update.entries.count <= 12,
              update.resolutions.count <= 12 else { return nil }

        let scopes = learningMemoryContextScopes(courseID: target.courseID)
        var entriesByScope = Dictionary(
            uniqueKeysWithValues: scopes.map { ($0, learningMemoryEntries(in: $0)) }
        )
        func locatedMemory(_ id: UUID) -> (LearningMemoryScope, Int, LearningMemoryEntry)? {
            for scope in scopes {
                if let index = entriesByScope[scope]?.firstIndex(where: { $0.id == id }),
                   let entry = entriesByScope[scope]?[index] {
                    return (scope, index, entry)
                }
            }
            return nil
        }
        var validatedEntries: [(
            proposal: StudyAgentMemoryUpdateEntry,
            memoryID: UUID?,
            scope: LearningMemoryScope,
            text: String,
            evidence: String,
            origin: LearningMemoryOrigin
        )] = []
        var entryTargetIDs: Set<UUID> = []
        for proposal in update.entries {
            let text = proposal.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = proposal.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !evidence.isEmpty else { return nil }
            if evidence.hasPrefix("[用户：本轮]") || evidence.hasPrefix("[会话：当前]") {
                guard StudyAgentCurrentTurnEvidence.matches(
                    evidence,
                    question: expectedUserQuestion
                ) else { return nil }
            }
            if proposal.origin == .userStatement {
                guard evidence.hasPrefix("[用户：本轮]") else { return nil }
            }
            let memoryID: UUID?
            let scope: LearningMemoryScope
            switch Self.parseOptionalRecordID(proposal.memoryID) {
            case .omitted:
                memoryID = nil
                scope = learningMemoryScope(
                    for: proposal.kind,
                    courseID: target.courseID
                )
            case .invalid:
                return nil
            case .id(let parsedMemoryID):
                guard entryTargetIDs.insert(parsedMemoryID).inserted,
                      let located = locatedMemory(parsedMemoryID),
                      located.2.status == .active,
                      located.0 == learningMemoryScope(
                          for: proposal.kind,
                          courseID: target.courseID
                      ) else {
                    return nil
                }
                if located.2.origin == .userStatement,
                   !evidence.hasPrefix("[用户：本轮]"),
                   !evidence.hasPrefix("[会话：当前]") {
                    return nil
                }
                memoryID = parsedMemoryID
                scope = located.0
            }
            validatedEntries.append(
                (
                    proposal,
                    memoryID,
                    scope,
                    String(text.prefix(500)),
                    String(evidence.prefix(400)),
                    proposal.origin == .observed ? .agentInference : proposal.origin
                )
            )
        }

        var validatedResolutions: [(
            memoryID: UUID,
            scope: LearningMemoryScope,
            evidence: String
        )] = []
        var resolutionTargetIDs: Set<UUID> = []
        for proposal in update.resolutions {
            let evidence = proposal.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard StudyAgentCurrentTurnEvidence.matches(
                evidence,
                question: expectedUserQuestion
            ),
            let memoryID = UUID(uuidString: proposal.memoryID),
            resolutionTargetIDs.insert(memoryID).inserted,
            let located = locatedMemory(memoryID),
            located.2.status == .active,
            located.2.kind == .goal
                || located.2.kind == .confusion
                || located.2.kind == .nextStep else {
                return nil
            }
            validatedResolutions.append(
                (
                    memoryID,
                    located.0,
                    String(evidence.prefix(400))
                )
            )
        }

        var sessionChanged = false
        var changedMemoryIDs: [UUID] = []
        var changedMemoryIDsByScope: [LearningMemoryScope: Set<UUID>] = [:]
        var acceptedEntries: [StudyAgentMemoryUpdateEntry] = []
        let now = Date()
        for validated in validatedEntries {
            var memoryEntries = entriesByScope[validated.scope] ?? []
            if let memoryID = validated.memoryID,
               let index = memoryEntries.firstIndex(where: { $0.id == memoryID }) {
                let origin: LearningMemoryOrigin = validated.evidence
                    .hasPrefix("[用户：本轮]")
                    ? .userStatement
                    : validated.origin
                guard memoryEntries[index].kind != validated.proposal.kind
                        || memoryEntries[index].text != validated.text
                        || memoryEntries[index].evidence != validated.evidence
                        || memoryEntries[index].origin != origin else {
                    continue
                }
                memoryEntries[index].kind = validated.proposal.kind
                memoryEntries[index].text = validated.text
                memoryEntries[index].evidence = validated.evidence
                memoryEntries[index].origin = origin
                memoryEntries[index].sessionID = target.sessionID
                memoryEntries[index].messageID = messageID
                memoryEntries[index].updatedAt = now
                changedMemoryIDs.append(memoryID)
                changedMemoryIDsByScope[validated.scope, default: []].insert(memoryID)
                acceptedEntries.append(
                    StudyAgentMemoryUpdateEntry(
                        memoryID: memoryID.uuidString.lowercased(),
                        kind: memoryEntries[index].kind,
                        text: memoryEntries[index].text,
                        evidence: memoryEntries[index].evidence,
                        origin: memoryEntries[index].origin
                    )
                )
            } else {
                let normalized = Self.normalizedMemoryText(validated.text)
                guard !memoryEntries.contains(where: {
                    $0.kind == validated.proposal.kind
                        && $0.status == .active
                        && Self.normalizedMemoryText($0.text) == normalized
                }) else {
                    continue
                }
                let entry = LearningMemoryEntry(
                    kind: validated.proposal.kind,
                    text: validated.text,
                    evidence: validated.evidence,
                    origin: validated.origin,
                    sessionID: target.sessionID,
                    messageID: messageID,
                    createdAt: now,
                    updatedAt: now
                )
                memoryEntries.append(entry)
                changedMemoryIDs.append(entry.id)
                changedMemoryIDsByScope[validated.scope, default: []].insert(entry.id)
                acceptedEntries.append(
                    StudyAgentMemoryUpdateEntry(
                        memoryID: entry.id.uuidString.lowercased(),
                        kind: entry.kind,
                        text: entry.text,
                        evidence: entry.evidence,
                        origin: entry.origin
                    )
                )
            }
            entriesByScope[validated.scope] = memoryEntries
        }

        for validated in validatedResolutions {
            var memoryEntries = entriesByScope[validated.scope] ?? []
            guard let index = memoryEntries.firstIndex(where: {
                $0.id == validated.memoryID
            }) else { continue }
            memoryEntries[index].status = .resolved
            memoryEntries[index].resolvedAt = now
            memoryEntries[index].resolutionEvidence = validated.evidence
            memoryEntries[index].sessionID = target.sessionID
            memoryEntries[index].messageID = messageID
            memoryEntries[index].updatedAt = now
            if !changedMemoryIDs.contains(validated.memoryID) {
                changedMemoryIDs.append(validated.memoryID)
            }
            changedMemoryIDsByScope[validated.scope, default: []]
                .insert(validated.memoryID)
            entriesByScope[validated.scope] = memoryEntries
        }

        for (scope, memoryIDs) in changedMemoryIDsByScope {
            var memoryEntries = entriesByScope[scope] ?? []
            let nextRevision = learningMemoryRevision(in: scope) &+ 1
            for memoryID in memoryIDs {
                guard let index = memoryEntries.firstIndex(where: { $0.id == memoryID }) else {
                    continue
                }
                Self.appendLearningMemoryRevision(
                    to: &memoryEntries[index],
                    revision: nextRevision,
                    actor: .agent,
                    recordedAt: now
                )
            }
            if let stateIndex = learningMemoryStateIndex(
                for: scope,
                createIfMissing: true
            ) {
                learningMemoryStates[stateIndex].entries = memoryEntries
                learningMemoryStates[stateIndex].revision = nextRevision
            }
            entriesByScope[scope] = memoryEntries
        }

        if let index = studySessions.firstIndex(where: { $0.id == target.sessionID }) {
            if let summary = update.sessionSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty,
               studySessions[index].summary != String(summary.prefix(2_000)) {
                studySessions[index].summary = String(summary.prefix(2_000))
                sessionChanged = true
            }
            if !studySessions[index].flow.pinnedByUser,
               let phase = update.suggestedPhase,
               studySessions[index].flow.phase != phase {
                studySessions[index].flow.phase = phase
                sessionChanged = true
            }
            let next = update.suggestedNext
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
                .map { String($0.prefix(300)) }
            if !next.isEmpty, studySessions[index].flow.suggestedNext != next {
                studySessions[index].flow.suggestedNext = next
                sessionChanged = true
            }
            if sessionChanged {
                studySessions[index].updatedAt = now
            }
        }

        var acceptedUpdate = update
        acceptedUpdate.entries = acceptedEntries
        // A5b applies valid resolutions immediately; the persisted reply attachment
        // records the changed IDs, so the legacy confirmation strip must not ask again.
        acceptedUpdate.resolutions = []
        if activeStudySessionID == target.sessionID {
            latestAgentLearningUpdate = acceptedUpdate
            latestAgentLearningUpdateQuestion = expectedUserQuestion
        }
        guard !changedMemoryIDs.isEmpty else { return nil }
        let summary = changedMemoryIDs.compactMap { id in
            scopes.lazy.compactMap { scope in
                entriesByScope[scope]?.first(where: { $0.id == id })?.text
            }.first
        }.prefix(3).joined(separator: "；")
        return AgentReplyMemoryUpdate(
            memoryIDs: changedMemoryIDs,
            summary: summary.isEmpty
                ? ui("学习进度已更新", "Study progress updated")
                : String(summary.prefix(300))
        )
    }

    static func appendLearningMemoryRevision(
        to entry: inout LearningMemoryEntry,
        revision: UInt64,
        actor: LearningMemoryRevisionActor,
        recordedAt: Date
    ) {
        var revisions = entry.revisions ?? []
        revisions.append(
            LearningMemoryRevisionRecord(
                revision: revision,
                kind: entry.kind,
                text: entry.text,
                evidence: entry.evidence,
                origin: entry.origin,
                status: entry.status,
                sessionID: entry.sessionID,
                messageID: entry.messageID,
                resolutionEvidence: entry.resolutionEvidence,
                actor: actor,
                recordedAt: recordedAt
            )
        )
        entry.revisions = revisions
    }

    func applyCourseProfileUpdate(
        _ update: StudyAgentCourseProfileUpdate?,
        expectedContextRevision: String,
        expectedProfileRevision: UInt64,
        target: AgentConversationTarget
    ) -> AgentReplyProfileUpdate? {
        guard let courseID = target.courseID,
              activeCourseRemovalTokens[courseID] == nil,
              let update,
              update.contextRevision == expectedContextRevision,
              update.profileRevision == expectedProfileRevision,
              let profileIndex = courseKnowledgeProfiles.firstIndex(where: {
                  $0.courseID == courseID && $0.revision == expectedProfileRevision
              }) else { return nil }
        var profile = courseKnowledgeProfiles[profileIndex]
        let existingIDs = Set(profile.entries.map(\.id))
        let removedIDs = Set(update.removedEntryIDs.compactMap(UUID.init(uuidString:)))
        guard removedIDs.count == update.removedEntryIDs.count,
              removedIDs.isSubset(of: existingIDs) else { return nil }
        let itemsByID = Dictionary(
            uniqueKeysWithValues: courseItems(in: courseID).map { ($0.id, $0) }
        )

        var targetIDs = Set<UUID>()
        var replacements: [(UUID?, CourseKnowledgeProfileEntry)] = []
        let now = Date()
        for proposal in update.entries {
            let entryID: UUID?
            switch Self.parseOptionalRecordID(proposal.entryID) {
            case .omitted:
                entryID = nil
            case .invalid:
                return nil
            case .id(let parsed):
                entryID = parsed
            }
            guard entryID.map(existingIDs.contains) ?? true,
                  entryID.map({ targetIDs.insert($0).inserted }) ?? true else { return nil }
            var sources: [CourseKnowledgeProfileSource] = []
            for source in proposal.sources {
                guard let item = itemsByID[source.itemID],
                (item.isNotebookNote ? "note" : "material") == source.role else { return nil }
                let revision = item.isNotebookNote
                    ? loadedAgentNoteText(for: item).map(
                        CourseDocumentSearchIndex.sourceRevision(forMarkdown:)
                    )
                    : CourseDocumentSearchIndex.sourceRevision(for: item)
                guard revision == source.sourceRevision else { return nil }
                sources.append(
                    CourseKnowledgeProfileSource(
                        itemID: source.itemID,
                        role: item.isNotebookNote ? .note : .material,
                        location: source.location,
                        sourceRevision: source.sourceRevision
                    )
                )
            }
            let allowsEmptySources = update.checkpoint == "userRequested"
                || proposal.text.hasPrefix("用户自述：")
            guard !sources.isEmpty || allowsEmptySources else { return nil }
            let existing = entryID.flatMap { id in
                profile.entries.first(where: { $0.id == id })
            }
            replacements.append(
                (
                    entryID,
                    CourseKnowledgeProfileEntry(
                        id: entryID ?? UUID(),
                        kind: proposal.kind,
                        text: String(proposal.text.prefix(1_200)),
                        sources: sources,
                        createdAt: existing?.createdAt ?? now,
                        updatedAt: now
                    )
                )
            )
        }

        profile.entries.removeAll { removedIDs.contains($0.id) }
        for (entryID, replacement) in replacements {
            if let entryID,
               let index = profile.entries.firstIndex(where: { $0.id == entryID }) {
                profile.entries[index] = replacement
            } else {
                profile.entries.append(replacement)
            }
        }
        guard profile.entries.count <= 200 else { return nil }
        guard profile.entries != courseKnowledgeProfiles[profileIndex].entries else { return nil }
        profile.overview = profile.entries
            .filter { $0.kind == .overview }
            .max(by: { $0.updatedAt < $1.updatedAt })?.text ?? ""
        profile.revision &+= 1
        profile.updatedAt = now
        courseKnowledgeProfiles[profileIndex] = profile
        dirtyPortableCourseIDs.insert(courseID)
        let texts = replacements.map { $0.1.text }
        return AgentReplyProfileUpdate(
            entryIDs: replacements.map { $0.1.id },
            summary: texts.prefix(3).joined(separator: "；"),
            texts: texts
        )
    }

    private enum OptionalRecordID {
        case omitted
        case invalid
        case id(UUID)
    }

    private static func parseOptionalRecordID(_ raw: String?) -> OptionalRecordID {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return .omitted }
        guard let id = UUID(uuidString: trimmed) else { return .invalid }
        return .id(id)
    }

    func persistNativeLearningUpdate(
        _ update: StudyAgentLearningUpdate,
        expectedContextRevision: String,
        expectedUserQuestion: String,
        target: AgentConversationTarget,
        messageID: UUID
    ) -> NativeStorePersistReceipt {
        if let applied = applyLearningUpdate(
            update,
            expectedContextRevision: expectedContextRevision,
            expectedMemoryRevision: update.memoryRevision,
            expectedUserQuestion: expectedUserQuestion,
            target: target,
            messageID: messageID
        ) {
            return NativeStorePersistReceipt(
                accepted: true,
                message: "已写入学习记忆",
                memoryUpdate: applied
            )
        }
        let hasClientID = update.entries.contains {
            !($0.memoryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        }
        if hasClientID {
            return .rejected("魏碑没有保存这次学习记忆。更新只能沿用 weibei_read_learning_memory 返回的 memoryID；新建请省略该字段，不要传空字符串，也不要自己编 UUID。")
        }
        return .rejected("魏碑没有保存这次学习记忆。用户自述请用 origin=userStatement，evidence 以「[用户：本轮]」开头并带上用户原话。")
    }

    func persistNativeCourseProfileUpdate(
        _ update: StudyAgentCourseProfileUpdate,
        expectedContextRevision: String,
        target: AgentConversationTarget
    ) -> NativeStorePersistReceipt {
        if let applied = applyCourseProfileUpdate(
            update,
            expectedContextRevision: expectedContextRevision,
            expectedProfileRevision: update.profileRevision,
            target: target
        ) {
            return NativeStorePersistReceipt(
                accepted: true,
                message: "已写入课程知识档案",
                profileUpdate: applied
            )
        }
        let hasClientID = update.entries.contains {
            !($0.entryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        }
        if hasClientID {
            return .rejected("魏碑没有保存这次课程档案。更新只能沿用当前档案已有条目的 entryID；新建请省略该字段，不要传空字符串，也不要自己编 UUID。")
        }
        return .rejected("魏碑没有保存这次课程档案。自述掌握用 kind=concept、text 以「用户自述：」开头、checkpoint=userRequested。")
    }

}
