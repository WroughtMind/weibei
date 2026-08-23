import Foundation

public actor NativeAgentLoop {
    private var cancelled = false

    public init() {}

    public func cancel() {
        cancelled = true
    }

    public func reset() {
        cancelled = false
    }

    public func run(
        request: StudyAgentRequest,
        ledger: NativeAgentLedger,
        registry: NativeToolRegistry,
        adapter: NativeLLMAdapter,
        model: String,
        hostToolHandler: StudyAgentHostToolHandler?,
        systemPrompt: String,
        liveStores: NativeLiveStores = .empty,
        mode: NativeAgentMode = .assistant,
        progress: StudyAgentProgressHandler?
    ) async throws -> NativeLoopResult {
        await progress?(.preparing)
        let turn = 1
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(type: .turnStart, seq: seq, timeMS: time, turn: turn)
        }
        let userMessage: String
        if let selection = request.selectionText,
           !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let title = request.selectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectionTitle = title.flatMap { $0.isEmpty ? nil : $0 }
                ?? request.language.text("当前选区", "Current selection")
            userMessage = request.language.text(
                "[选中文字：\(selectionTitle)]\n\(selection)\n\n[问题]\n\(request.question)",
                "[Selected text: \(selectionTitle)]\n\(selection)\n\n[Question]\n\(request.question)"
            )
        } else {
            userMessage = request.question
        }
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(
                type: .userMessage,
                seq: seq,
                timeMS: time,
                turn: turn,
                text: userMessage
            )
        }

        var context = NativeToolExecutionContext(
            request: request,
            mode: mode,
            hostToolHandler: hostToolHandler,
            persistentAssetIDsByContextID: Dictionary(
                uniqueKeysWithValues: request.courseContext.items.map { ($0.id, $0.id) }
            ),
            liveStores: liveStores
        )
        let scope = NativeToolScope.session(request.id.uuidString)
        let tools = await registry.resolved(scope: scope)

        var collectedText = ""
        var toolTrace: [String] = []
        var noteProposal: StudyAgentNoteProposal?
        var relationProposal: StudyAgentRelationProposal?
        var learningUpdate: StudyAgentLearningUpdate?
        var courseProfileUpdate: StudyAgentCourseProfileUpdate?
        var appliedMemoryUpdate: AgentReplyMemoryUpdate?
        var appliedProfileUpdate: AgentReplyProfileUpdate?
        var loadedSkills: [StudyAgentLoadedSkill] = []
        var readItemIDs: [String] = []
        var sources: [AgentReplySource] = []
        var contentBlocks: [AgentMessageContentBlock] = []
        var pendingUnstarted: [NativeToolCall] = []

        do {
            var step = 0
            while true {
                step += 1
                try checkCancelled()
                _ = try await ledger.append { seq, time in
                    NativeSessionEvent(type: .stepStart, seq: seq, timeMS: time, turn: turn, step: step)
                }
                var messages = [NativeModelMessage(role: .system, content: systemPrompt)]
                messages.append(contentsOf: await ledger.deriveMessages())
                if let invariant = NativeAgentInvariant.mismatch(logged: await ledger.deriveMessages(), outgoing: Array(messages.dropFirst())) {
                    assertionFailure(invariant)
                }
                var llmRequest = NativeLLMRequest(model: model, messages: messages, tools: tools)
                if adapter.family.contains("responses") {
                    llmRequest.enableNativeWebSearch = tools.contains { $0.name == "weibei_course_map" }
                    llmRequest.reasoningEffort = "low"
                }
                var assembler = NativeToolCallAssembler()
                var finish: NativeFinishReason?
                var stepText = ""
                for try await chunk in adapter.stream(llmRequest) {
                    try checkCancelled()
                    assembler.apply(chunk)
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(
                            type: .assistantChunk,
                            seq: seq,
                            timeMS: time,
                            turn: turn,
                            step: step,
                            chunk: chunk
                        )
                    }
                    switch chunk {
                    case let .textDelta(_, text):
                        stepText += text
                        collectedText += text
                        await progress?(.text(collectedText, []))
                    case let .toolCallDelta(_, _, name, _):
                        if let name {
                            await progress?(.usingTool(name, nil))
                        }
                    case let .finish(reason, _):
                        finish = reason
                    default:
                        break
                    }
                }
                if !stepText.isEmpty {
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(
                            type: .assistantMessage,
                            seq: seq,
                            timeMS: time,
                            turn: turn,
                            step: step,
                            text: stepText
                        )
                    }
                }

                let calls: [NativeToolCall]
                do {
                    calls = (finish == .toolCalls || finish == .stop) ? (try assembler.completedCalls()) : []
                } catch {
                    throw error
                }
                if calls.isEmpty {
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(type: .stepEnd, seq: seq, timeMS: time, turn: turn, step: step)
                    }
                    guard finish == .stop else {
                        try await ledger.closeTurn(turn: turn, reason: .error)
                        throw NativeLLMFailure(
                            code: finish?.rawValue ?? "incomplete",
                            message: "模型回答未正常结束，请继续。"
                        )
                    }
                    break
                }
                pendingUnstarted = calls
                for call in calls {
                    toolTrace.append(call.name)
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(
                            type: .toolCall,
                            seq: seq,
                            timeMS: time,
                            turn: turn,
                            step: step,
                            toolCallID: call.id,
                            toolName: call.name,
                            argumentsJSON: call.arguments
                        )
                    }
                }
                for call in calls {
                    try checkCancelled()
                    pendingUnstarted.removeAll { $0.id == call.id }
                    let result: NativeToolExecutionResult
                    do {
                        result = try await registry.execute(
                            NativeToolCallRequest(name: call.name, argumentsJSON: call.arguments, callID: call.id),
                            context: context,
                            scope: scope
                        )
                    } catch {
                        result = NativeToolExecutionResult(text: error.localizedDescription, isError: true)
                    }
                    applySideEffects(
                        name: call.name,
                        result: result,
                        contextRevision: request.contextRevision,
                        noteProposal: &noteProposal,
                        relationProposal: &relationProposal,
                        learningUpdate: &learningUpdate,
                        courseProfileUpdate: &courseProfileUpdate,
                        appliedMemoryUpdate: &appliedMemoryUpdate,
                        appliedProfileUpdate: &appliedProfileUpdate,
                        loadedSkills: &loadedSkills,
                        readItemIDs: &readItemIDs,
                        sources: &sources,
                        contentBlocks: &contentBlocks,
                        context: &context
                    )
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(
                            type: .toolResult,
                            seq: seq,
                            timeMS: time,
                            turn: turn,
                            step: step,
                            text: result.text,
                            toolCallID: call.id,
                            toolName: call.name,
                            isError: result.isError
                        )
                    }
                }
                _ = try await ledger.append { seq, time in
                    NativeSessionEvent(type: .stepEnd, seq: seq, timeMS: time, turn: turn, step: step)
                }
            }
            try await ledger.closeTurn(turn: turn, reason: .completed)
            return NativeLoopResult(
                text: collectedText,
                contentBlocks: contentBlocks,
                sources: sources,
                toolTrace: toolTrace,
                noteProposal: noteProposal,
                relationProposal: relationProposal,
                learningUpdate: learningUpdate,
                courseProfileUpdate: courseProfileUpdate,
                appliedMemoryUpdate: appliedMemoryUpdate,
                appliedProfileUpdate: appliedProfileUpdate,
                loadedSkills: loadedSkills,
                readItemIDs: readItemIDs
            )
        } catch is CancellationError {
            try await balanceCancellation(
                ledger: ledger,
                turn: turn,
                pending: pendingUnstarted
            )
            throw NativeLLMFailure(code: "cancelled", message: "cancelled")
        } catch let failure as NativeLLMFailure where failure.code == "cancelled" {
            try await balanceCancellation(
                ledger: ledger,
                turn: turn,
                pending: pendingUnstarted
            )
            throw failure
        }
    }

    private func checkCancelled() throws {
        if cancelled || Task.isCancelled {
            throw CancellationError()
        }
    }

    private func balanceCancellation(
        ledger: NativeAgentLedger,
        turn: Int,
        pending: [NativeToolCall]
    ) async throws {
        for call in pending {
            _ = try await ledger.append { seq, time in
                NativeSessionEvent(
                    type: .toolResult,
                    seq: seq,
                    timeMS: time,
                    turn: turn,
                    text: "not executed: cancelled",
                    toolCallID: call.id,
                    toolName: call.name,
                    isError: true
                )
            }
        }
        try await ledger.closeTurn(turn: turn, reason: .cancelled)
    }

    private func applySideEffects(
        name: String,
        result: NativeToolExecutionResult,
        contextRevision: String,
        noteProposal: inout StudyAgentNoteProposal?,
        relationProposal: inout StudyAgentRelationProposal?,
        learningUpdate: inout StudyAgentLearningUpdate?,
        courseProfileUpdate: inout StudyAgentCourseProfileUpdate?,
        appliedMemoryUpdate: inout AgentReplyMemoryUpdate?,
        appliedProfileUpdate: inout AgentReplyProfileUpdate?,
        loadedSkills: inout [StudyAgentLoadedSkill],
        readItemIDs: inout [String],
        sources: inout [AgentReplySource],
        contentBlocks: inout [AgentMessageContentBlock],
        context: inout NativeToolExecutionContext
    ) {
        if result.isError { return }
        let details = result.details
        if name == "weibei_course_search" || name == "weibei_course_read" {
            if let items = (try? JSONDecoder().decode(StudyAgentHostToolResult.self, from: Data(result.text.utf8)))?.items {
                for item in items {
                    if !context.searchedItemIDs.contains(item.item.id) {
                        context.searchedItemIDs.append(item.item.id)
                    }
                    readItemIDs.append(item.item.id)
                    if let revision = item.sourceRevision {
                        context.readSourceRevisions[item.item.id] = revision
                    }
                    let excerpt = item.item.searchText
                    let kind: AgentReplySourceKind = item.item.role == "note" ? .note : .material
                    let label = kind == .note ? "[笔记：\(item.item.title)]" : "[材料：\(item.item.title)]"
                    if !sources.contains(where: { $0.itemID == item.item.id }) {
                        sources.append(
                            AgentReplySource(
                                itemID: item.item.id,
                                kind: kind,
                                title: item.item.title,
                                label: label,
                                excerpt: String(excerpt.prefix(160))
                            )
                        )
                    }
                }
            }
        }
        if name == "weibei_note_proposal" {
            noteProposal = StudyAgentProposalDecoding.noteProposal(from: details)
        }
        if name == "weibei_relation_proposal" {
            relationProposal = StudyAgentProposalDecoding.relationProposal(from: details)
        }
        if name == "weibei_read_learning_memory" {
            context.lastReadMemoryRevision = context.request.learningContext.memoryRevision
        }
        if name == "weibei_update_learning_memory" {
            learningUpdate = StudyAgentProposalDecoding.learningUpdate(from: details)
            if let applied = memoryApplyReceipt(from: details) {
                appliedMemoryUpdate = applied
            }
        }
        if name == "weibei_course_profile_update" {
            courseProfileUpdate = StudyAgentProposalDecoding.courseProfileUpdate(from: details)
            if let applied = profileApplyReceipt(from: details) {
                appliedProfileUpdate = applied
            }
        }
        if name == "weibei_visualize",
           let id = details["id"] as? String,
           let spec = details["spec"],
           let specData = try? JSONSerialization.data(withJSONObject: spec),
           let specJSON = String(data: specData, encoding: .utf8) {
            contentBlocks.append(.visualization(AgentVisualization(id: id, specJSON: specJSON)))
        }
        if name == "load_skill" || name == "read" {
            if let loaded = details["loaded"] as? [String: Any],
               let id = loaded["id"] as? String,
               let skillName = loaded["name"] as? String,
               let sha = loaded["sha256"] as? String,
               let relative = loaded["relativePath"] as? String {
                context.loadedSkillIDs.insert(id)
                let skill = StudyAgentLoadedSkill(
                    id: id,
                    name: skillName,
                    version: loaded["version"] as? String ?? "1.0.0",
                    sha256: sha,
                    byteCount: loaded["byteCount"] as? Int ?? 0,
                    relativePath: relative,
                    loadedAtContextRevision: contextRevision
                )
                if let index = loadedSkills.firstIndex(where: { $0.id == skill.id }) {
                    loadedSkills[index] = skill
                } else {
                    loadedSkills.append(skill)
                }
            }
        }
    }

    private func memoryApplyReceipt(from details: [String: Any]) -> AgentReplyMemoryUpdate? {
        guard let applied = details["appliedMemoryUpdate"] as? [String: Any],
              let rawIDs = applied["memoryIDs"] as? [String] else { return nil }
        let ids = rawIDs.compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return nil }
        return AgentReplyMemoryUpdate(
            memoryIDs: ids,
            summary: applied["summary"] as? String ?? ""
        )
    }

    private func profileApplyReceipt(from details: [String: Any]) -> AgentReplyProfileUpdate? {
        guard let applied = details["appliedProfileUpdate"] as? [String: Any],
              let rawIDs = applied["entryIDs"] as? [String] else { return nil }
        let ids = rawIDs.compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return nil }
        return AgentReplyProfileUpdate(
            entryIDs: ids,
            summary: applied["summary"] as? String ?? "",
            texts: applied["texts"] as? [String] ?? []
        )
    }
}

public struct NativeLoopResult: Sendable {
    public var text: String
    public var contentBlocks: [AgentMessageContentBlock]
    public var sources: [AgentReplySource]
    public var toolTrace: [String]
    public var noteProposal: StudyAgentNoteProposal?
    public var relationProposal: StudyAgentRelationProposal?
    public var learningUpdate: StudyAgentLearningUpdate?
    public var courseProfileUpdate: StudyAgentCourseProfileUpdate?
    public var appliedMemoryUpdate: AgentReplyMemoryUpdate?
    public var appliedProfileUpdate: AgentReplyProfileUpdate?
    public var loadedSkills: [StudyAgentLoadedSkill]
    public var readItemIDs: [String]
}

enum NativeAgentInvariant {
    static func mismatch(logged: [NativeModelMessage], outgoing: [NativeModelMessage]) -> String? {
        guard logged.count == outgoing.count else {
            return "model-visible ⟺ logged failed: count \(logged.count) vs \(outgoing.count)"
        }
        for (left, right) in zip(logged, outgoing) {
            if left.role != right.role || left.content != right.content {
                return "model-visible ⟺ logged failed: role/content drift"
            }
        }
        return nil
    }
}
