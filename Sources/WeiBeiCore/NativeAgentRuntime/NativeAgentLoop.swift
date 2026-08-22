import Foundation

public actor NativeAgentLoop {
    public var maximumSteps = 12
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
        progress: StudyAgentProgressHandler?
    ) async throws -> NativeLoopResult {
        await progress?(.preparing)
        let turn = 1
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(type: .turnStart, seq: seq, timeMS: time, turn: turn)
        }
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(
                type: .userMessage,
                seq: seq,
                timeMS: time,
                turn: turn,
                text: request.question
            )
        }

        var context = NativeToolExecutionContext(
            request: request,
            hostToolHandler: hostToolHandler,
            persistentAssetIDsByContextID: Dictionary(
                uniqueKeysWithValues: request.courseContext.items.map { ($0.id, $0.id) }
            ),
            liveStores: liveStores
        )
        let scope = NativeToolScope.session(request.id.uuidString)
        var tools = await registry.resolved(scope: scope)
        if !request.interactiveVisualizationsEnabled {
            await registry.hide("weibei_visualize", scope: scope)
            tools = await registry.resolved(scope: scope)
        }

        var collectedText = ""
        var toolTrace: [String] = []
        var noteProposal: StudyAgentNoteProposal?
        var relationProposal: StudyAgentRelationProposal?
        var learningUpdate: StudyAgentLearningUpdate?
        var courseProfileUpdate: StudyAgentCourseProfileUpdate?
        var richAnswer: RichAnswerPresentation?
        var loadedSkills: [StudyAgentLoadedSkill] = []
        var readItemIDs: [String] = []
        var pendingUnstarted: [NativeToolCall] = []

        do {
            for step in 1...maximumSteps {
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
                var finish: NativeFinishReason = .stop
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
                        richAnswer: &richAnswer,
                        loadedSkills: &loadedSkills,
                        readItemIDs: &readItemIDs,
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
                toolTrace: toolTrace,
                noteProposal: noteProposal,
                relationProposal: relationProposal,
                learningUpdate: learningUpdate,
                courseProfileUpdate: courseProfileUpdate,
                richAnswer: richAnswer,
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
        richAnswer: inout RichAnswerPresentation?,
        loadedSkills: inout [StudyAgentLoadedSkill],
        readItemIDs: inout [String],
        context: inout NativeToolExecutionContext
    ) {
        let details = result.details
        if name == "weibei_course_search" || name == "weibei_course_read" {
            if let items = (try? JSONDecoder().decode(StudyAgentHostToolResult.self, from: Data(result.text.utf8)))?.items {
                for item in items {
                    context.searchedItemIDs.insert(item.item.id)
                    readItemIDs.append(item.item.id)
                    if let revision = item.sourceRevision {
                        context.readSourceRevisions[item.item.id] = revision
                    }
                }
            }
        }
        if name == "weibei_note_proposal" {
            let markdown = details["markdown"] as? String ?? ""
            let evidence = details["evidence"] as? [String] ?? []
            noteProposal = StudyAgentNoteProposal(
                markdown: markdown,
                evidence: evidence,
                contextRevision: contextRevision
            )
        }
        if name == "weibei_relation_proposal" {
            relationProposal = StudyAgentRelationProposal(
                noteItemID: details["noteItemID"] as? String ?? "",
                sourceItemID: details["sourceItemID"] as? String ?? "",
                contextRevision: contextRevision
            )
        }
        if name == "weibei_learning_memory" {
            context.lastReadMemoryRevision = context.request.learningContext.memoryRevision
        }
        if name == "weibei_course_profile_update" {
            context.courseProfileUpdated = true
        }
        _ = learningUpdate
        _ = courseProfileUpdate
        _ = richAnswer
        _ = loadedSkills
    }
}

public struct NativeLoopResult: Sendable {
    public var text: String
    public var toolTrace: [String]
    public var noteProposal: StudyAgentNoteProposal?
    public var relationProposal: StudyAgentRelationProposal?
    public var learningUpdate: StudyAgentLearningUpdate?
    public var courseProfileUpdate: StudyAgentCourseProfileUpdate?
    public var richAnswer: RichAnswerPresentation?
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
