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
        isAskingAgent && activeAgentReplyChatID == activeStudySessionID
    }

    var runningAgentChatTitle: String {
        guard let chatID = activeAgentReplyChatID,
              let session = studySessions.first(where: { $0.id == chatID }) else {
            return ui("另一条 Chat", "another Chat")
        }
        return session.title
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

    func cancelStudyAgentRuntimes() async {
        await NativeAgentRuntimeBox.runtime?.cancel()
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
            baseURL: agentBaseURL
        )
        let selectedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        NativeAgentRuntimeBox.runtime = runtime
        defer { NativeAgentRuntimeBox.runtime = nil }
        return try await runtime.respond(
            to: request,
            progress: { [weak self] progress in
                await self?.applyAgentProgress(
                    progress,
                    requestID: request.id,
                    replyMessageID: replyMessageID,
                    chatID: target.sessionID
                )
            }
        )
    }

    func searchWorkspaceForAgent(
        query rawQuery: String,
        limit: Int,
        crossLibrary: Bool,
        currentCourseID: UUID?
    ) async -> StudyAgentHostToolResult {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let cappedLimit = min(max(limit, 1), 8)
        guard !query.isEmpty else {
            return StudyAgentHostToolResult(query: rawQuery, items: [])
        }
        if crossLibrary {
            let outcome = await searchAllCourses(
                currentCourseID: currentCourseID,
                query: query
            )
            // 检索能力对所有 Chat 一致：跨库时其他课程的材料与笔记一样可搜，
            // 当前课程命中已由 searchAllCourses 排在最前，这里只按类型过滤。
            let hits = outcome.hits.filter { hit in
                hit.result.kind == .material || hit.result.kind == .note
            }
            return StudyAgentHostToolResult(
                query: query,
                items: hits.prefix(cappedLimit).map { hostToolItem(from: $0) }
            )
        }
        guard let currentCourseID else {
            return StudyAgentHostToolResult(query: query, items: [])
        }
        let outcome = await searchCourseHome(courseID: currentCourseID, query: query)
        let courseTitle = course(withID: currentCourseID)?.title ?? ""
        let results = outcome.results.filter {
            $0.kind == .material || $0.kind == .note
        }
        return StudyAgentHostToolResult(
            query: query,
            items: results.prefix(cappedLimit).map {
                hostToolItem(
                    from: $0,
                    courseID: currentCourseID,
                    courseTitle: courseTitle
                )
            }
        )
    }

    private func hostToolItem(from hit: GlobalSearchHit) -> StudyAgentHostToolItem {
        hostToolItem(
            from: hit.result,
            courseID: hit.courseID,
            courseTitle: hit.courseTitle
        )
    }

    private func hostToolItem(
        from result: CourseHomeSearchResult,
        courseID: UUID?,
        courseTitle: String
    ) -> StudyAgentHostToolItem {
        let role = result.kind == .note ? "note" : "material"
        let excerpt = result.matchedText ?? result.detail
        return StudyAgentHostToolItem(
            item: StudyAgentCourseItem(
                id: result.itemID ?? result.id,
                title: result.title,
                subtitle: result.detail,
                kind: result.kind.rawValue,
                role: role,
                tags: courseTitle.isEmpty ? [] : [courseTitle],
                searchText: excerpt
            ),
            courseIDs: courseID.map { [$0.uuidString.lowercased()] } ?? [],
            courseTitles: courseTitle.isEmpty ? [] : [courseTitle]
        )
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
        case let .courseMap(itemID, offset, limit):
            let approvedSources = sources.filter(agentHostToolSourceIsValid)
            let selectedSources: ArraySlice<AgentHostToolSource>
            let total: Int
            if let itemID {
                let matches = approvedSources.filter { $0.item.id == itemID }
                selectedSources = matches[...]
                total = matches.count
            } else {
                selectedSources = approvedSources.dropFirst(offset).prefix(limit)
                total = approvedSources.count
            }
            let items = selectedSources.map { source in
                let linkedItemIDs = links.compactMap { link -> String? in
                    if link.noteItemID == source.item.id { return link.sourceItemID }
                    if link.sourceItemID == source.item.id { return link.noteItemID }
                    return nil
                }
                return StudyAgentHostToolItem(
                    item: StudyAgentCourseItem(
                        id: source.item.id,
                        title: source.title,
                        subtitle: source.subtitle,
                        kind: source.kind,
                        role: source.role,
                        linkedItemIDs: linkedItemIDs,
                        headings: itemID == nil
                            ? []
                            : searchIndex.outline(item: source.item),
                        tags: source.courseTitles,
                        searchText: "",
                        isTruncated: false
                    ),
                    relativePath: source.relativePath,
                    courseIDs: source.courseIDs,
                    courseTitles: source.courseTitles,
                    sourceRevision: source.projectItem.sourceRevision
                )
            }
            return StudyAgentHostToolResult(
                query: "",
                items: items,
                total: total,
                nextCursor: offset + items.count < total
                    ? String(offset + items.count)
                    : nil
            )

        case let .courseSearch(query, limit):
            let approvedSources = sources.filter(agentHostToolSourceIsValid)
            let indexed = searchIndex.lookup(
                items: approvedSources.compactMap {
                    $0.memoryText == nil ? $0.item : nil
                },
                query: query
            )
            let matched = approvedSources.compactMap { source -> (
                source: AgentHostToolSource,
                result: CourseDocumentIndexResult,
                titleMatched: Bool
            )? in
                let titleMatched = source.title.localizedCaseInsensitiveContains(query)
                    || source.subtitle.localizedCaseInsensitiveContains(query)
                    || (
                        source.title.count >= 2
                            && query.localizedCaseInsensitiveContains(source.title)
                    )
                let indexedResult = indexed[source.item.id]
                let result: CourseDocumentIndexResult
                if let memoryText = source.memoryText {
                    result = CourseDocumentSearchIndex.readMarkdown(
                        memoryText,
                        query: titleMatched ? "" : query,
                        location: nil
                    )
                } else if titleMatched {
                    result = searchIndex.read(
                        item: source.item,
                        query: "",
                        location: nil
                    )
                } else {
                    result = indexedResult ?? CourseDocumentIndexResult(
                        text: nil,
                        isTruncated: false,
                        rank: nil
                    )
                }
                let text = result.text ?? ""
                guard agentHostToolSourceIsValid(source),
                      (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || result.totalPageCount != nil) else {
                    return nil
                }
                return (
                    source,
                    CourseDocumentIndexResult(
                        text: text,
                        isTruncated: result.isTruncated,
                        rank: result.rank,
                        sourceRevision: result.sourceRevision,
                        indexedPageCount: result.indexedPageCount,
                        totalPageCount: result.totalPageCount,
                        uncoveredPageIndexes: result.uncoveredPageIndexes,
                        failedPageIndexes: result.failedPageIndexes,
                        failedPageReasons: result.failedPageReasons
                    ),
                    titleMatched
                )
            }.sorted { left, right in
                if left.titleMatched != right.titleMatched {
                    return left.titleMatched
                }
                return (left.result.rank ?? .greatestFiniteMagnitude)
                    < (right.result.rank ?? .greatestFiniteMagnitude)
            }
            let knowledgeSources = matched.prefix(max(limit * 4, limit)).map { match in
                CourseKnowledgeSource(
                    id: match.source.item.id,
                    title: match.source.title,
                    subtitle: match.source.subtitle,
                    kind: match.source.kind,
                    role: match.source.role,
                    text: match.result.text ?? "",
                    isTruncated: match.result.isTruncated,
                    indexedPageCount: match.result.indexedPageCount,
                    totalPageCount: match.result.totalPageCount,
                    uncoveredPageNumbers: match.result.uncoveredPageIndexes.map { $0 + 1 },
                    failedPageNumbers: match.result.failedPageIndexes.map { $0 + 1 },
                    failedPageReasons: Dictionary(
                        uniqueKeysWithValues: match.result.failedPageReasons.map { ($0.key + 1, $0.value) }
                    )
                )
            }
            let context = CourseKnowledgeIndex.build(
                title: title,
                sources: knowledgeSources,
                links: links,
                query: query,
                currentMaterialID: nil,
                currentNoteID: nil
            )
            let sourceByID = Dictionary(
                uniqueKeysWithValues: matched.map { ($0.source.item.id, $0.source) }
            )
            let sourceRevisionByID = Dictionary(
                uniqueKeysWithValues: matched.map {
                    ($0.source.item.id, $0.result.sourceRevision)
                }
            )
            return StudyAgentHostToolResult(
                query: query,
                items: context.items.prefix(limit).compactMap { item in
                    guard let source = sourceByID[item.id] else { return nil }
                    return StudyAgentHostToolItem(
                        item: item,
                        relativePath: source.relativePath,
                        courseIDs: source.courseIDs,
                        courseTitles: source.courseTitles,
                        sourceRevision: sourceRevisionByID[item.id] ?? nil
                    )
                }
            )

        case let .courseRead(itemID, query, location, cursor, maximumCharacters):
            guard let source = sources.first(where: { $0.item.id == itemID }),
                  agentHostToolSourceIsValid(source) else {
                throw AgentConversationTargetError(message: "这份资料不属于当前 Chat 的查询范围")
            }
            let indexed: CourseDocumentIndexResult
            if let memoryText = source.memoryText {
                indexed = CourseDocumentSearchIndex.readMarkdown(
                    memoryText,
                    query: query,
                    location: location,
                    cursor: cursor,
                    sourceID: source.item.id,
                    maximumCharacters: maximumCharacters
                )
            } else {
                indexed = searchIndex.read(
                    item: source.item,
                    query: query,
                    location: location,
                    cursor: cursor,
                    maximumCharacters: maximumCharacters
                )
            }
            guard let text = indexed.text,
                  agentHostToolSourceIsValid(source) else {
                throw AgentConversationTargetError(message: "这份资料在读取期间发生了变化")
            }
            let context = CourseKnowledgeIndex.build(
                title: title,
                sources: [
                    CourseKnowledgeSource(
                        id: source.item.id,
                        title: source.title,
                        subtitle: source.subtitle,
                        kind: source.kind,
                        role: source.role,
                        text: text,
                        isTruncated: indexed.isTruncated,
                        indexedPageCount: indexed.indexedPageCount,
                        totalPageCount: indexed.totalPageCount,
                        uncoveredPageNumbers: indexed.uncoveredPageIndexes.map { $0 + 1 },
                        failedPageNumbers: indexed.failedPageIndexes.map { $0 + 1 },
                        failedPageReasons: Dictionary(
                            uniqueKeysWithValues: indexed.failedPageReasons.map { ($0.key + 1, $0.value) }
                        )
                    ),
                ],
                links: links,
                query: [query, location].compactMap { $0 }.joined(separator: " "),
                currentMaterialID: nil,
                currentNoteID: nil
            )
            return StudyAgentHostToolResult(
                query: query,
                items: context.items.map { item in
                    var item = item
                    item.searchText = text
                    item.isTruncated = indexed.isTruncated
                    return StudyAgentHostToolItem(
                        item: item,
                        relativePath: source.relativePath,
                        courseIDs: source.courseIDs,
                        courseTitles: source.courseTitles,
                        sourceRevision: indexed.sourceRevision
                    )
                },
                nextCursor: indexed.nextCursor,
                sourceRevision: indexed.sourceRevision
            )

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

        case let .webOpen(url, maximumCharacters):
            return StudyAgentHostToolResult(
                query: url,
                items: [],
                webPages: [
                    try await WeiBeiWebResearchClient.open(
                        url,
                        maximumCharacters: maximumCharacters
                    ),
                ]
            )

        case .workspaceSearch:
            throw AgentConversationTargetError(message: "工作区检索由课程宿主执行")
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

@MainActor
enum NativeAgentRuntimeBox {
    static var runtime: NativeStudyAgentRuntime?
}
