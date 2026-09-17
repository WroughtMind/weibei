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
        contextWindow: Int? = nil,
        hostToolHandler: StudyAgentHostToolHandler?,
        systemPrompt: String,
        liveStores: NativeLiveStores = .empty,
        mode: NativeAgentMode = .assistant,
        progress: StudyAgentProgressHandler?
    ) async throws -> NativeLoopResult {
        await progress?(.preparing)
        let existingEvents = await ledger.allEvents()
        let turn = (existingEvents.compactMap(\.turn).max() ?? 0) + 1
        let aliasScope = NativeStateAliases.scopeKey(for: request)
        let persistedAliases = existingEvents.reversed().first {
            $0.stateAliasScope == aliasScope && $0.stateAliases != nil
        }?.stateAliases ?? [:]
        let reservedAliases = Set(existingEvents.compactMap(\.stateAliases).flatMap(\.values))
        var aliases = NativeStateAliases(
            request: request,
            persisted: persistedAliases,
            reservedAliases: reservedAliases
        )
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(
                type: .turnStart,
                seq: seq,
                timeMS: time,
                turn: turn,
                stateAliasScope: aliasScope,
                stateAliases: aliases.persistedSnapshot
            )
        }
        let previousEvents = request.reusingLastUserMessage ? await ledger.allEvents() : []
        let originalUser = previousEvents.last { $0.type == .userMessage }
        var sources = request.knownSources
        sources += previousEvents.filter { $0.type == .toolResult && $0.seq > (originalUser?.seq ?? Int.max) }
            .flatMap { NativeAgentSources.fromToolText($0.text ?? "", aliases: aliases) }
        var sourceIndex = 0
        let selections = request.selectionSources.filter { !$0.excerpt.isEmpty }.map { source in
            sourceIndex += 1
            return NativeAgentSources.label(source, turn: originalUser?.turn ?? turn, index: sourceIndex)
        }
        sources += selections
        let referenceContext = try NativePromptAssembler.turnContext(for: request, selections: selections, aliases: aliases)
        let turnContext = referenceContext + "\n\n用户问题：\n" + request.question
        let userMessageEvent: NativeSessionEvent
        if let original = originalUser {
            try await ledger.replaceLastAnswer(question: request.question)
            userMessageEvent = original
        } else {
            if !referenceContext.isEmpty {
                _ = try await ledger.append { seq, time in
                    NativeSessionEvent(type: .turnContext, seq: seq, timeMS: time, turn: turn, text: referenceContext)
                }
            }
            userMessageEvent = try await ledger.append { seq, time in
                NativeSessionEvent(type: .userMessage, seq: seq, timeMS: time, turn: turn, text: request.question)
            }
        }

        var assetIDs = Dictionary(
            uniqueKeysWithValues: request.courseContext.items.map { ($0.id, $0.id) }
        )
        for note in request.projectScope.items where note.role == "note" {
            if let alias = aliases.noteAlias(for: note.itemID) { assetIDs[alias] = note.itemID }
        }
        var context = NativeToolExecutionContext(
            request: request,
            mode: mode,
            hostToolHandler: hostToolHandler,
            persistentAssetIDsByContextID: assetIDs,
            liveStores: liveStores
        )
        context.request.knownSources = sources
        context.stateAliases = aliases
        let scope = NativeToolScope.session(request.id.uuidString)
        let tools = await registry.resolved(scope: scope)

        let completedWrites = request.reusingLastUserMessage ? (await ledger.allEvents()).filter { event in
            guard event.type == .toolResult, event.seq > userMessageEvent.seq, !event.isError,
                  ["weibei_note_proposal", "weibei_relation_proposal", "weibei_update_learning_memory", "weibei_course_profile_update"].contains(event.toolName),
                  let text = event.text,
                  let receipt = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return false }
            return ["saved", "unchanged"].contains(receipt["status"] as? String ?? "")
        } : []

        var collectedText = ""
        var toolTrace: [String] = []
        var appliedMemoryUpdate: AgentReplyMemoryUpdate?
        var appliedProfileUpdate: AgentReplyProfileUpdate?
        var loadedSkills: [StudyAgentLoadedSkill] = []
        var readItemIDs: [String] = []
        var contentBlocks: [AgentMessageContentBlock] = []
        var pendingUnstarted: [NativeToolCall] = []

        do {
            var step = 0
            while true {
                step += 1
                try checkCancelled()
                let projection = aliases.projectedHistory(await ledger.deriveProjection())
                for message in projection.messages where message.role == .tool {
                    for source in NativeAgentSources.fromToolText(message.content, aliases: aliases) where !sources.contains(where: { $0.label == source.label }) {
                        sources.append(source)
                    }
                }
                var messages = [NativeModelMessage(role: .system, content: systemPrompt)]
                messages.append(contentsOf: projection.messages)
                if let invariant = NativeAgentInvariant.mismatch(
                    logged: projection.messages,
                    outgoing: Array(messages.dropFirst())
                ) {
                    assertionFailure(invariant)
                }
                var llmRequest = NativeLLMRequest(
                    model: model, messages: messages, tools: tools,
                    promptCacheKey: request.projectScope.chatID.isEmpty
                        ? request.id.uuidString.lowercased()
                        : request.projectScope.chatID.lowercased()
                )
                llmRequest.enableNativeWebSearch = tools.contains { $0.name == "weibei_course_map" }
                llmRequest.reasoningEffort = request.reasoningEffort
                let effectiveContextWindow = contextWindow ?? adapter.contextWindow
                if let effectiveContextWindow {
                    let candidate: NativeContextCompactionCandidate?
                    do {
                        candidate = try await NativeContextCompaction.prepareCandidate(
                            request: llmRequest,
                            projection: projection,
                            adapter: adapter,
                            contextWindow: effectiveContextWindow,
                            turnContext: (userMessageEvent.seq, turnContext)
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let failure as NativeLLMFailure where failure.code == "cancelled" {
                        throw failure
                    } catch {
                        candidate = nil
                    }
                    if let candidate {
                        try checkCancelled()
                        _ = try await ledger.append { seq, time in
                            NativeSessionEvent(
                                type: .contextCompaction,
                                seq: seq,
                                timeMS: time,
                                summary: candidate.summary,
                                firstKeptSeq: candidate.firstKeptSeq
                            )
                        }
                        llmRequest = candidate.request
                    }
                }
                _ = try await ledger.append { seq, time in
                    NativeSessionEvent(type: .stepStart, seq: seq, timeMS: time, turn: turn, step: step)
                }
                var assembler = NativeToolCallAssembler()
                var finish: NativeFinishReason?
                var stepText = ""
                var stepUsage: NativeTokenUsage?
                var reportedSearchActivity = false
                var sourceOnlyURLs: [String] = []
                var receivedChunk = false
                var recoveredOverflow = false
                streamAttempt: while true {
                    do {
                        for try await chunk in adapter.stream(llmRequest) {
                            try checkCancelled()
                            receivedChunk = true
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
                                if !contentBlocks.isEmpty {
                                    if case let .text(previous)? = contentBlocks.last {
                                        contentBlocks[contentBlocks.count - 1] = .text(previous + text)
                                    } else {
                                        contentBlocks.append(.text(text))
                                    }
                                }
                                await progress?(.text(collectedText, contentBlocks, NativeAgentSources.used(in: collectedText, available: sources)))
                            case var .serverToolActivity(activity):
                                reportedSearchActivity = true
                                activity.id = "\(step):server:\(activity.id)"
                                activity.textOffset = collectedText.count
                                await progress?(.toolActivity(activity))
                            case let .webSearchSource(url):
                                // Some providers expose only sources, not a search lifecycle.
                                // Report the observed result once, without inventing a running phase.
                                if !reportedSearchActivity && !sourceOnlyURLs.contains(url) {
                                    sourceOnlyURLs.append(url)
                                    await progress?(.toolActivity(.init(
                                        id: "\(step):server:sources", name: "$web_search_sources", state: .completed,
                                        sourceURLs: sourceOnlyURLs, textOffset: collectedText.count
                                    )))
                                }
                                if !context.currentRunSourceURLs.contains(url) {
                                    context.currentRunSourceURLs.append(url)
                                }
                            case let .toolCallDelta(_, _, name, _):
                                if let name {
                                    await progress?(.usingTool(name, nil))
                                }
                            case let .usage(usage):
                                stepUsage = stepUsage?.merging(usage) ?? usage
                            case let .finish(reason, _):
                                finish = reason
                            default:
                                break
                            }
                        }
                        break streamAttempt
                    } catch let failure as NativeLLMFailure
                        where failure.isContextOverflow
                            && !recoveredOverflow
                            && !receivedChunk {
                        let candidate: NativeContextCompactionCandidate?
                        do {
                            let recoveryProjection = await ledger.deriveProjection()
                            candidate = try await NativeContextCompaction.prepareOverflowCandidate(
                                request: llmRequest,
                                projection: recoveryProjection,
                                adapter: adapter,
                                contextWindow: effectiveContextWindow,
                                turnContext: (userMessageEvent.seq, turnContext)
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch let cancellation as NativeLLMFailure where cancellation.code == "cancelled" {
                            throw cancellation
                        } catch {
                            throw failure
                        }
                        guard let candidate else { throw failure }
                        try checkCancelled()
                        _ = try await ledger.append { seq, time in
                            NativeSessionEvent(
                                type: .contextCompaction,
                                seq: seq,
                                timeMS: time,
                                summary: candidate.summary,
                                firstKeptSeq: candidate.firstKeptSeq
                            )
                        }
                        llmRequest = candidate.request
                        recoveredOverflow = true
                    }
                }
                let completedUsage: NativeTokenUsage? = if finish == .stop || finish == .toolCalls || finish == .length {
                    stepUsage
                } else {
                    nil
                }
                if !stepText.isEmpty || completedUsage != nil {
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(
                            type: .assistantMessage,
                            seq: seq,
                            timeMS: time,
                            turn: turn,
                            step: step,
                            text: stepText,
                            usage: completedUsage
                        )
                    }
                }

                let callResults = (finish == .toolCalls || finish == .stop) ? assembler.callResults() : []
                let calls = callResults.map { $0.call }
                if calls.isEmpty {
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(type: .stepEnd, seq: seq, timeMS: time, turn: turn, step: step)
                    }
                    guard finish == .stop else {
                        try await ledger.closeTurn(turn: turn, reason: finish == .refused ? .rejected : .error)
                        throw NativeLLMFailure(
                            code: finish?.rawValue ?? "incomplete",
                            message: (finish == .length ? AgentFailureKind.truncated : finish == .paused ? .paused : finish == .refused ? .refused : .generic).title(language: request.language)
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
                for callResult in callResults {
                    let call = callResult.call
                    try checkCancelled()
                    pendingUnstarted.removeAll { $0.id == call.id }
                    let arguments = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any]
                    await progress?(.toolActivity(NativeToolActivityPresentation.activity(
                        id: "\(step):\(call.id)", name: call.name, arguments: arguments ?? [:], context: context, textOffset: collectedText.count)))
                    var result: NativeToolExecutionResult
                    if let failure = callResult.failure {
                        result = NativeToolExecutionResult(text: failure.localizedDescription, isError: true)
                    } else if call.name == "$web_search" {
                        // Kimi 内置搜索:把模型给出的搜索参数原样回传,服务端执行检索。
                        result = NativeToolExecutionResult(text: call.arguments)
                    } else if let previous = completedWrites.last(where: { $0.toolName == call.name }) {
                        result = NativeToolExecutionResult(text: "此前的操作已经完成；重新生成保留这些写入，不重复执行。原始回执：\n" + (previous.text ?? ""))
                    } else {
                        do {
                            result = try await registry.execute(
                                NativeToolCallRequest(name: call.name, argumentsJSON: call.arguments, callID: call.id),
                                context: context,
                                scope: scope
                            )
                        } catch {
                            result = NativeToolExecutionResult(text: error.localizedDescription, isError: true)
                        }
                    }
                    if let refreshedAliases = result.stateAliases {
                        aliases = refreshedAliases
                        context.stateAliases = refreshedAliases
                    }
                    NativeAgentSources.attach(to: &result, name: call.name, turn: turn, index: &sourceIndex)
                    applySideEffects(
                        name: call.name,
                        result: result,
                        contextRevision: request.contextRevision,
                        appliedMemoryUpdate: &appliedMemoryUpdate,
                        appliedProfileUpdate: &appliedProfileUpdate,
                        loadedSkills: &loadedSkills,
                        readItemIDs: &readItemIDs,
                        sources: &sources,
                        contentBlocks: &contentBlocks,
                        context: &context
                    )
                    if call.name == "render_ui", !result.isError,
                       let changed = contentBlocks.first(where: { block in
                           if case let .visualization(value) = block { return value.id == result.details["id"] as? String }
                           return false
                       }), case let .visualization(visualization) = changed {
                        // Preserve text before the first figure, then append later text in place.
                        if contentBlocks.count == 1, !collectedText.isEmpty {
                            contentBlocks.insert(.text(collectedText), at: 0)
                        }
                        if let display = liveStores.displayVisualization {
                            result = await display(visualization, contentBlocks)
                        } else {
                            result = NativeToolExecutionResult(text: "互动内容已生成，但当前没有显示界面，尚未展示。", isError: true)
                        }
                    }
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
                            isError: result.isError,
                            imageMediaType: result.image?.mediaType,
                            imageBase64: result.image?.base64,
                            stateAliasScope: aliasScope,
                            stateAliases: aliases.persistedSnapshot
                        )
                    }
                    await progress?(.toolActivity(NativeToolActivityPresentation.activity(
                        id: "\(step):\(call.id)", name: call.name, arguments: arguments ?? [:], context: context, result: result, textOffset: collectedText.count)))
                }
                _ = try await ledger.append { seq, time in
                    NativeSessionEvent(type: .stepEnd, seq: seq, timeMS: time, turn: turn, step: step)
                }
            }
            try await ledger.closeTurn(turn: turn, reason: .completed)
            return NativeLoopResult(
                text: collectedText,
                contentBlocks: contentBlocks,
                sources: NativeAgentSources.used(in: collectedText, available: sources),
                toolTrace: toolTrace,
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
        if let note = details["persistedNote"] as? StudyAgentPersistedNoteRef {
            context.request.confirmedNotes.append(note)
        }
        if name == "weibei_course_read" || name == "weibei_search_workspace" || name == "weibei_read_discussion" {
            let aliases = context.stateAliases ?? NativeStateAliases(request: context.request)
            for source in NativeAgentSources.fromToolText(result.text, aliases: aliases) {
                if !sources.contains(where: { $0.label == source.label }) { sources.append(source) }
                if !context.request.knownSources.contains(where: { $0.label == source.label }) {
                    context.request.knownSources.append(source)
                }
                if name == "weibei_course_read", let id = source.itemID, !readItemIDs.contains(id) {
                    readItemIDs.append(id)
                }
            }
            if name == "weibei_read_discussion",
               let payload = try? JSONDecoder().decode(StudyAgentHostToolResult.self, from: Data(result.text.utf8)) {
                for message in (payload.discussions ?? []).flatMap({ $0.messages ?? [] }) where message.role == .user {
                    context.userEvidence[message.source.label] = message.source.excerpt
                }
            }
        }
        if name == "weibei_web_open",
           let pages = (try? JSONDecoder().decode(
            StudyAgentHostToolResult.self,
            from: Data(result.text.utf8)
           ))?.webPages {
            for link in pages.flatMap(\.links) where !context.currentRunSourceURLs.contains(link) {
                context.currentRunSourceURLs.append(link)
            }
        }
        if name == "weibei_read_learning_memory" {
            context.lastReadMemoryRevision = (details["memoryRevision"] as? NSNumber)?.uint64Value
        }
        if name == "weibei_update_learning_memory" {
            if let applied = memoryApplyReceipt(from: details) {
                appliedMemoryUpdate = applied
            }
        }
        if name == "weibei_course_profile_update" {
            if let applied = profileApplyReceipt(from: details) {
                appliedProfileUpdate = applied
            }
        }
        if name == "render_ui",
           let id = details["id"] as? String,
           let spec = details["spec"],
           let specData = try? JSONSerialization.data(withJSONObject: spec),
           let specJSON = String(data: specData, encoding: .utf8) {
            let block = AgentMessageContentBlock.visualization(AgentVisualization(id: id, specJSON: specJSON))
            if let index = contentBlocks.firstIndex(where: {
                if case let .visualization(value) = $0 { return value.id == id }
                return false
            }) {
                contentBlocks[index] = block
            } else {
                contentBlocks.append(block)
            }
        }
        if name == "load_skill" {
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
            if left.role != right.role || left.content != right.content || left.images != right.images {
                return "model-visible ⟺ logged failed: role/content drift"
            }
        }
        return nil
    }
}
