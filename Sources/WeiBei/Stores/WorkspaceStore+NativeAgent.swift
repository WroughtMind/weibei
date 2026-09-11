import Foundation
import WeiBeiCore

/// 互动操作被拒的类型化身份:测试按 case 断言;message 只负责展示。
/// agentRefused 的载荷是 askAgent 现场生成的完整说明文案。
enum AgentVisualizationActionRejection: Equatable {
    case emptyAction
    case actionNameTooLong
    case payloadTooLarge
    case payloadUnreadable
    case agentBusy(activeChat: Bool)
    case agentRefused(String)

    func message(_ ui: (String, String) -> String) -> String {
        switch self {
        case .emptyAction:
            return ui("这个按钮没有可执行的回答操作。", "This button has no executable response action.")
        case .actionNameTooLong:
            return ui("这个互动操作名称过长，未提交回答。", "This interactive action name is too long, so nothing was submitted.")
        case .payloadTooLarge:
            return ui("互动数据过大，无法提交回答。", "The interactive data is too large to submit.")
        case .payloadUnreadable:
            return ui("互动数据无法读取，未提交回答。", "The interactive data could not be read, so nothing was submitted.")
        case .agentBusy(activeChat: true):
            return ui("这个互动操作正在处理中。", "This interactive action is being processed.")
        case .agentBusy(activeChat: false):
            return ui("另一条回答正在处理，请稍候。", "Another response is being processed. Please wait.")
        case .agentRefused(let detail):
            return detail
        }
    }
}

@MainActor
extension WorkspaceStore {
    func submitAgentVisualizationAction(_ action: String, payloadJSON: String) -> AgentVisualizationActionRejection? {
        let action = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            return .emptyAction
        }
        guard action.count <= 200 else {
            return .actionNameTooLong
        }
        guard payloadJSON.utf8.count <= 65_536 else {
            return .payloadTooLarge
        }
        guard (try? JSONSerialization.jsonObject(
            with: Data(payloadJSON.utf8),
            options: .fragmentsAllowed
        )) != nil else {
            return .payloadUnreadable
        }
        guard agentRequestTask == nil, !isAskingAgent, !isStoppingAgent else {
            return .agentBusy(activeChat: isAgentRunningInActiveChat)
        }
        guard let refusal = askAgent(
            replayingSelections: [],
            visibleQuestionOverride: ui(
                "互动操作：\(action)",
                "Interactive action: \(action)"
            ),
            questionOverride: ui(
                "我在互动界面中执行了「\(action)」。当前界面数据：\(payloadJSON)",
                "I used “\(action)” in the interactive view. Current view data: \(payloadJSON)"
            )
        ) else { return nil }
        return .agentRefused(refusal)
    }

    var canCopyReference: Bool {
        hasSelectionAttachments || selectionContext != nil || hasSelectedMaterial || activeNoteItem?.isNotebookNote == true
    }

    var copyReferenceActionTitle: String {
        if hasSelectionAttachments || selectionContext != nil { return ui("复制选区引用", "Copy selection reference") }
        if hasSelectedMaterial { return ui("复制资料引用", "Copy material reference") }
        return ui("复制笔记引用", "Copy note reference")
    }

    var sendAgentActionTitle: String {
        isAgentRunningInActiveChat
            ? ui("停止回答", "Stop response")
            : ui("发送问题", "Send question")
    }

    var isAgentRunningInActiveChat: Bool {
        agentRequestTask != nil && agentRun.chatID == activeStudySessionID
    }

    func isAgentRunning(in chatID: UUID) -> Bool {
        agentRuns[chatID]?.agentRequestTask != nil
    }

    var hasPersistedGeneratingAgentReply: Bool {
        messages.contains { $0.role == .assistant && $0.origin?.requestID == activeAgentRequestID }
    }

    func agentDisplayText(for message: AgentMessage) -> String {
        guard message.id == activeAgentReplyMessageID,
              message.completionState == .generating else {
            return message.text
        }
        return latestAgentStreamingText
    }

    func agentReplyDisplayedStreamingText(_ message: AgentMessage) -> Bool {
        agentReplyIDsThatDisplayedStreamingText.contains(message.id)
    }

    var isAgentStreamingSurfaceVisible: Bool {
        hasPrimaryConversationPaneVisible || agentSurface == .selectionFloat
    }

    func finishAgentStreamingDisplay() {
        agentStreaming.finishDisplaying()
        latestAgentStreamingText = ""
    }

    func settleAgentStreamingDisplayImmediately() {
        guard agentStreaming.displayingMessageID != nil else { return }
        agentStreamingDisplayPump.settleImmediately(
            cumulativeText: latestAgentStreamingText
        )
    }

    func landAgentStreamingDisplayImmediately() {
        guard agentStreaming.displayingMessageID != nil else { return }
        agentStreamingDisplayPump.replaceImmediately(
            cumulativeText: latestAgentStreamingText
        )
    }

    func setAgentStreamingReduceMotion(_ enabled: Bool) {
        agentStreamingUsesReducedMotion = enabled
        guard enabled, agentStreaming.displayingMessageID != nil else { return }
        agentStreamingDisplayPump.replaceImmediately(
            cumulativeText: latestAgentStreamingText
        )
    }

    func landAgentStreamingDisplayIfHidden() {
        guard !isAgentStreamingSurfaceVisible else { return }
        landAgentStreamingDisplayImmediately()
    }

    func dispatchStudyAgentRequest(
        _ request: StudyAgentRequest,
        provider selectedProvider: AgentProviderID,
        target: AgentConversationTarget,
        replyMessageID: UUID,
        hostToolHandler: @escaping StudyAgentHostToolHandler
    ) async throws -> StudyAgentReply {
        try await executeNativeStudyAgentRequest(
            request,
            provider: selectedProvider,
            target: target,
            replyMessageID: replyMessageID,
            hostToolHandler: hostToolHandler
        )
    }

    private func executeNativeStudyAgentRequest(
        _ request: StudyAgentRequest,
        provider selectedProvider: AgentProviderID,
        target: AgentConversationTarget,
        replyMessageID: UUID,
        hostToolHandler: @escaping StudyAgentHostToolHandler
    ) async throws -> StudyAgentReply {
        let endpoint = try AgentProviderEndpoint(
            provider: selectedProvider,
            baseURL: agentRun.baseURL
        )
        let selectedModel = agentRun.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let routedModel = NativeProviderRouting.route(selectedProvider).defaultModel
        let model = selectedModel.isEmpty
            ? (routedModel.isEmpty ? "deepseek-chat" : routedModel)
            : selectedModel
        let adapter = try await NativeLLMAdapterFactory.make(
            provider: selectedProvider,
            model: model,
            endpoint: endpoint
        )
        let resources = try AgentResources.bundled()
        let liveStores = NativeLiveStores(
            learning: { [weak self] in
                await MainActor.run {
                    self?.makeLearningContext(target: target) ?? .empty
                }
            },
            profile: { [weak self] in
                await MainActor.run {
                    self?.refreshCourseProfileContext(target: target) ?? .empty
                }
            },
            persistLearningUpdate: { [weak self] update in
                guard let self else {
                    return NativeStorePersistReceipt.rejected("工作区已关闭")
                }
                return await self.persistNativeLearningUpdate(
                    update,
                    expectedContextRevision: request.contextRevision,
                    expectedUserQuestion: request.question,
                    target: target,
                    messageID: replyMessageID
                )
            },
            persistCourseProfileUpdate: { [weak self] update in
                guard let self else {
                    return NativeStorePersistReceipt.rejected("工作区已关闭")
                }
                return await self.persistNativeCourseProfileUpdate(
                    update,
                    expectedContextRevision: request.contextRevision,
                    target: target
                )
            },
            documentsRoot: workspaceDirectory.appendingPathComponent("NativeAgent/Documents", isDirectory: true),
            skillRegistry: try NativeSkillRegistry.load(from: resources.skillsURL),
            confirmDocumentCreation: { title, summary in
                await AgentDocumentConfirmationCenter.shared.requestConfirmation(
                    title: title,
                    summary: summary
                )
            }
        )
        let sessionTitleHandler: StudyAgentSessionTitleHandler?
        if let session = studySessions.first(where: { $0.id == target.sessionID }),
           Self.sessionNeedsSemanticTitle(
               replacing: session.title,
               messages: session.messages,
               titleSetByUser: session.titleSetByUser
           ) {
            sessionTitleHandler = { [weak self] title in
                await self?.applySemanticSessionTitleAndSave(title, to: target.sessionID)
            }
        } else {
            sessionTitleHandler = nil
        }
        let runtime = NativeStudyAgentRuntime(
            model: model,
            adapter: adapter,
            contextWindow: NativeProviderRouting.contextWindow(
                provider: selectedProvider,
                model: model
            ),
            ledgerRoot: workspaceDirectory.appendingPathComponent("NativeAgent/Ledgers", isDirectory: true),
            systemPromptText: resources.systemPrompt,
            hostToolHandler: hostToolHandler,
            liveStores: liveStores,
            sessionTitleHandler: sessionTitleHandler
        )
        let run = agentRun
        run.runtime = runtime
        defer { run.runtime = nil }
        return try await runtime.respond(
            to: request,
            progress: { [weak self] progress in
                await AgentConversationExecution.$run.withValue(run) {
                    await self?.applyAgentProgress(
                        progress,
                        requestID: request.id,
                        replyMessageID: replyMessageID,
                        chatID: target.sessionID
                    )
                }
            }
        )
    }

    nonisolated private static func pagedSearchResult(
        query: String,
        items: [StudyAgentHostToolItem],
        total: Int,
        offset: Int
    ) -> StudyAgentHostToolResult {
        var page: [StudyAgentHostToolItem] = []
        for item in items {
            let candidate = StudyAgentHostToolResult(
                query: query,
                items: page + [item],
                total: total,
                nextCursor: offset + page.count + 1 < total
                    ? String(offset + page.count + 1)
                    : nil
            )
            guard page.isEmpty || searchPageFitsBudget(candidate) else { break }
            page.append(item)
        }
        let nextOffset = offset + page.count
        return StudyAgentHostToolResult(
            query: query,
            items: page,
            total: total,
            nextCursor: nextOffset < total ? String(nextOffset) : nil
        )
    }

    nonisolated private static func searchPageFitsBudget(
        _ result: StudyAgentHostToolResult
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(result),
              data.count <= 50_000,
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.components(separatedBy: "\\n").count <= 2_000
    }

    nonisolated private static func sourceToolItem(
        _ source: AgentHostToolSource,
        passage: CourseDocumentPassage? = nil,
        state: CourseDocumentIndexResult? = nil,
        preferredCourseID: String? = nil,
        links: [NoteSourceLink] = []
    ) -> StudyAgentHostToolItem {
        let courseID = preferredCourseID.flatMap { source.courseIDs.contains($0) ? $0 : nil } ?? source.courseIDs.first
        let reference = passage.map {
            AgentReplySource(itemID: source.item.id, courseID: courseID.flatMap(UUID.init(uuidString:)),
                kind: source.role == "note" ? .note : .material, title: source.title, label: "", excerpt: $0.text,
                pageIndex: $0.pageIndex, sectionTitle: $0.title,
                sectionLocationID: $0.location.isEmpty ? nil : $0.location, sectionOrdinal: $0.sectionOrdinal)
        }
        return StudyAgentHostToolItem(
            item: StudyAgentCourseItem(id: source.item.id, title: source.title, subtitle: source.subtitle,
                kind: source.kind, role: source.role,
                linkedItemIDs: links.compactMap { link in
                    if link.noteItemID == source.item.id { return link.sourceItemID }
                    if link.sourceItemID == source.item.id { return link.noteItemID }
                    return nil
                },
                headings: passage?.title.map { [$0] } ?? [], tags: source.courseTitles,
                searchText: passage?.text ?? "", isTruncated: state?.isTruncated ?? false,
                indexedPageCount: state?.indexedPageCount, totalPageCount: state?.totalPageCount,
                uncoveredPageNumbers: state?.uncoveredPageIndexes.map { $0 + 1 } ?? [],
                failedPageNumbers: state?.failedPageIndexes.map { $0 + 1 } ?? [],
                failedPageReasons: state.map { Dictionary(uniqueKeysWithValues: $0.failedPageReasons.map { ($0.key + 1, $0.value) }) } ?? [:]),
            relativePath: source.relativePath, courseIDs: source.courseIDs, courseTitles: source.courseTitles,
            sourceRevision: state?.sourceRevision ?? source.projectItem.sourceRevision, source: reference,
            availability: state.map { String(describing: $0.availability) }
        )
    }

    nonisolated private static func scopedToolSources(
        _ sources: [AgentHostToolSource], scope: StudyAgentSourceScope, id: String?
    ) -> [AgentHostToolSource] {
        sources.filter { source in
            guard agentHostToolSourceIsValid(source) else { return false }
            switch scope {
            case .library: return true
            case .material: return source.item.id == id
            case .course: return id.map { source.courseIDs.contains($0.lowercased()) } ?? false
            }
        }
    }

    nonisolated private static func sourcePageOffset(_ cursor: String?) throws -> Int {
        guard let cursor else { return 0 }
        guard let offset = Int(cursor), offset >= 0 else {
            throw AgentConversationTargetError(message: "目录或搜索游标无效")
        }
        return offset
    }

    nonisolated static func executeAgentHostTool(
        _ request: StudyAgentHostToolRequest,
        title: String,
        sources: [AgentHostToolSource],
        links: [NoteSourceLink],
        searchIndex: CourseDocumentSearchIndex
    ) async throws -> StudyAgentHostToolResult {
        try Task.checkCancellation()
        switch request {
        case let .courseMap(scope, scopeID, name, cursor, limit):
            let offset = try sourcePageOffset(cursor)
            let selected = scopedToolSources(sources, scope: scope, id: scopeID).filter {
                name == nil || $0.title.localizedCaseInsensitiveContains(name ?? "")
            }
            if scope == .material, let source = selected.first {
                var state: CourseDocumentIndexResult
                if let markdown = source.memoryText {
                    let all = CourseDocumentSearchIndex.markdownPassages(markdown).filter { !$0.location.isEmpty }
                    let entries = all.dropFirst(offset).prefix(limit).map { passage -> CourseDocumentPassage in
                        var entry = passage; entry.text = ""; return entry
                    }
                    state = CourseDocumentIndexResult(text: nil, isTruncated: false,
                        nextCursor: offset + entries.count < all.count ? String(offset + entries.count) : nil,
                        sourceRevision: CourseDocumentSearchIndex.sourceRevision(forMarkdown: markdown), passages: entries)
                } else {
                    state = searchIndex.outlinePassages(item: source.item, offset: offset, limit: limit)
                }
                return StudyAgentHostToolResult(query: name ?? "",
                    items: state.passages.map { sourceToolItem(source, passage: $0, state: state, links: links) },
                    nextCursor: state.nextCursor, scope: scope, scopeID: scopeID,
                    coverage: [sourceToolItem(source, state: state)])
            }
            var result = pagedSearchResult(query: name ?? "",
                items: selected.dropFirst(offset).prefix(limit).map { sourceToolItem($0, links: links) },
                total: selected.count, offset: offset)
            result.scope = scope; result.scopeID = scopeID
            return result

        case let .workspaceSearch(query, scope, scopeID, cursor, limit):
            let offset = try sourcePageOffset(cursor)
            let selected = scopedToolSources(sources, scope: scope, id: scopeID)
            var matches: [StudyAgentHostToolItem] = []
            var coverage: [StudyAgentHostToolItem] = []
            for source in selected {
                try Task.checkCancellation()
                let state: CourseDocumentIndexResult
                if let markdown = source.memoryText {
                    state = CourseDocumentIndexResult(text: nil, isTruncated: false,
                        sourceRevision: CourseDocumentSearchIndex.sourceRevision(forMarkdown: markdown),
                        passages: CourseDocumentSearchIndex.markdownPassages(markdown).compactMap { $0.excerpt(matching: query) })
                } else {
                    state = searchIndex.searchPassages(item: source.item, query: query)
                }
                guard agentHostToolSourceIsValid(source) else { continue }
                matches += state.passages.map { sourceToolItem(source, passage: $0, state: state,
                    preferredCourseID: scope == .course ? scopeID : nil) }
                if state.isTruncated || state.availability != .ready {
                    coverage.append(sourceToolItem(source, state: state))
                }
            }
            var result = pagedSearchResult(query: query, items: Array(matches.dropFirst(offset).prefix(limit)),
                total: matches.count, offset: offset)
            result.scope = scope; result.scopeID = scopeID
            result.coverage = coverage.isEmpty ? nil : coverage
            return result

        case let .courseRead(itemID, page, location, cursor, maximumCharacters):
            guard let source = sources.first(where: { $0.item.id == itemID }), agentHostToolSourceIsValid(source) else {
                throw AgentConversationTargetError(message: "资料不存在或无法读取")
            }
            let state: CourseDocumentIndexResult
            if let markdown = source.memoryText {
                state = CourseDocumentSearchIndex.readMarkdown(markdown, location: location, cursor: cursor,
                    sourceID: source.item.id, maximumCharacters: maximumCharacters)
            } else {
                state = searchIndex.read(item: source.item, page: page, location: location, cursor: cursor,
                    maximumCharacters: maximumCharacters)
            }
            guard agentHostToolSourceIsValid(source) else {
                throw AgentConversationTargetError(message: "资料在读取期间发生了变化")
            }
            return StudyAgentHostToolResult(query: "",
                items: state.passages.map { sourceToolItem(source, passage: $0, state: state) },
                nextCursor: state.nextCursor, sourceRevision: state.sourceRevision,
                scope: .material, scopeID: itemID, coverage: [sourceToolItem(source, state: state)])

        case let .retryFailedPDFPages(itemID):
            guard let source = sources.first(where: { $0.item.id == itemID }),
                  source.item.kind == .pdf,
                  agentHostToolSourceIsValid(source) else {
                throw AgentConversationTargetError(message: "这份 PDF 不属于当前 Chat 的查询范围")
            }
            guard searchIndex.retryFailedPDFPages(in: source.item) else {
                throw AgentConversationTargetError(message: "这份 PDF 当前没有可重新索引的识别失败页")
            }
            return StudyAgentHostToolResult(
                query: "已开始重新索引失败页",
                items: []
            )

        case let .webOpen(url, cursor, maximumCharacters):
            let offset = max(Int(cursor ?? "") ?? 0, 0)
            let page = try await WeiBeiWebResearchClient.open(
                url,
                cursor: offset,
                maximumCharacters: maximumCharacters
            )
            return StudyAgentHostToolResult(
                query: url,
                items: [],
                webPages: [page],
                nextCursor: page.isTruncated ? String(offset + page.text.count) : nil
            )

        }
    }

    nonisolated static func agentHostToolSourceIsValid(
        _ source: AgentHostToolSource
    ) -> Bool {
        source.grants.contains(where: agentFileGrantIsValid)
            || agentDirectSourceIsValid(source.item)
    }

    nonisolated static func agentDirectSourceIsValid(
        _ item: StudyItem
    ) -> Bool {
        guard let url = item.url?.standardizedFileURL,
              FileManager.default.isReadableFile(atPath: url.path),
              CourseProjectPathPolicy.isSame(
                  url,
                  url.resolvingSymlinksInPath().standardizedFileURL
              ) else {
            return false
        }
        switch item.storage {
        case .common:
            return true
        case .bundledSample:
            return item.isSample
        case .courseOwned:
            return false
        }
    }

    nonisolated static func agentFileGrantIsValid(
        _ grant: AgentFileGrant
    ) -> Bool {
        guard CourseProjectFileWorker.identity(at: grant.rootURL) == grant.rootIdentity,
              CourseProjectFileWorker.identity(at: grant.entryURL) == grant.entryIdentity,
              CourseProjectFileWorker.identity(at: grant.targetURL) == grant.targetIdentity,
              CourseProjectPathPolicy.isSame(
                  grant.targetURL,
                  grant.targetURL.resolvingSymlinksInPath().standardizedFileURL
              ) else {
            return false
        }
        if grant.isShared {
            return CourseProjectFileWorker.symbolicLink(
                at: grant.entryURL,
                pointsTo: grant.targetURL
            )
        }
        return CourseProjectPathPolicy.isSame(grant.entryURL, grant.targetURL)
            && CourseProjectPathPolicy.contains(
                grant.rootURL,
                grant.targetURL,
                includingRoot: false
            )
    }

    static func agentFailureMessage(
        for error: Error,
        kind: AgentFailureKind,
        language: WeiBeiInterfaceLanguage
    ) -> String {
        if error is NativeAgentResourcesError {
            return language.text(
                NativeAgentResourcesError.agentComponentsIncompleteMessage,
                "Agent components are incomplete, so the Agent cannot start. Repair or reinstall WeiBei."
            )
        }
        return kind.userMessage(
            language: language,
            userFacingDetail: userFacingAgentFailureDetail(for: error),
            draftPreserved: true
        )
    }
}
