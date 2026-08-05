import CryptoKit
import Darwin
import Foundation
import WeiBeiCore

private struct PiTerminalRuntimeFixture {
    var rootURL: URL
    var executableURL: URL

    func workingDirectory(named name: String) throws -> URL {
        let url = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum PiTerminalRuntimeSelfCheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

private actor PiProgressProbe {
    private var reachedPreparing = false

    func record(_ event: StudyAgentProgress) {
        if event == .preparing {
            reachedPreparing = true
        }
    }

    func waitForPreparing() async -> Bool {
        for _ in 0..<250 {
            if reachedPreparing { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }
}

func runPiTerminalRuntimeSelfChecks() async throws {
    let fixture = try makePiTerminalRuntimeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

    try await checkUserStopReturnsImmediately(fixture)
    try await checkCancelledTurnCannotAffectImmediateNextChat(fixture)
    try await checkTerminalErrorBypassesSlowProgress(fixture)
    try await checkGenericEventsDoNotDefeatWatchdog(fixture)
    try await checkMeaningfulThinkingKeepsRunAlive(fixture)
    try await checkRejectedRichAnswerKeepsSafeNarrative(fixture)
    try await checkRejectedActionKeepsOrdinaryAnswer(fixture)
    try await checkRelationProposalUsesCurrentCourseCatalog(fixture)
    try await checkPersistedSelectionSourcesAttachWithoutReadTool(fixture)
    try await checkContextSnapshotLivesUntilProcessShutdown(fixture)
    try await checkConversationBindingLaunchContract(fixture)
    try await checkHostCourseToolBridge(fixture)
    try await checkHostCourseToolBridgeRejectsSymlinkRoot(fixture)
    try await checkMissingSessionStartsFreshNativeHistory(fixture)
    try await checkWrongSessionStateRebuildsOnlyRequestedChat(fixture)
    try await checkUnreadableStoredSessionRebuildsOnce(fixture)
    try await checkStandardProxyEnvironmentIsForwarded(fixture)
}

private func checkHostCourseToolBridgeRejectsSymlinkRoot(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtimeDirectory = try fixture.workingDirectory(named: "SymlinkBridgeRuntime")
    let outsideDirectory = try fixture.workingDirectory(named: "OutsideBridgeResponses")
    let protectedDirectory = outsideDirectory
        .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(
        at: protectedDirectory,
        withIntermediateDirectories: true
    )
    let protectedFile = protectedDirectory.appendingPathComponent("keep.txt")
    try Data("must survive".utf8).write(to: protectedFile)
    try FileManager.default.createSymbolicLink(
        at: runtimeDirectory.appendingPathComponent("ToolResponses", isDirectory: true),
        withDestinationURL: outsideDirectory
    )
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: runtimeDirectory,
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    do {
        _ = try await runtime.respond(
            to: StudyAgentRequest(
                purpose: .conversation,
                question: "不应发送",
                materialTitle: "",
                materialText: "",
                noteTitle: "",
                noteText: "",
                projectScope: StudyAgentProjectScope(
                    kind: .course,
                    chatID: "symlink-bridge-chat",
                    courseID: UUID().uuidString.lowercased()
                ),
                contextRevision: "symlink-bridge-test"
            ),
            sessionID: UUID(),
            workingDirectory: try fixture.workingDirectory(named: "SymlinkBridgeProject"),
            hostToolHandler: nil,
            progress: nil
        )
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI host tool bridge accepted a symbolic-link response root"
        )
    } catch let error as PiTerminalRuntimeSelfCheckError {
        throw error
    } catch {
        guard FileManager.default.fileExists(atPath: protectedFile.path) else {
            throw PiTerminalRuntimeSelfCheckError.failed(
                "PI host tool bridge deleted content through a symbolic-link response root"
            )
        }
    }
    await runtime.shutdown()
}

private func checkHostCourseToolBridge(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtimeDirectory = try fixture.workingDirectory(named: "BridgeRuntime")
    let staleResponseDirectory = runtimeDirectory
        .appendingPathComponent("ToolResponses", isDirectory: true)
        .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(
        at: staleResponseDirectory,
        withIntermediateDirectories: true
    )
    try Data("stale course response".utf8).write(
        to: staleResponseDirectory.appendingPathComponent("response.json")
    )
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: runtimeDirectory,
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "查找利率",
        materialTitle: "利率的含义",
        materialText: "",
        noteTitle: "",
        noteText: "",
        selectionTitle: "利率选区",
        selectionText: "利率是资金的价格。",
        selectionSources: [
            AgentReplySource(
                itemID: "persistent-material",
                kind: .selection,
                title: "利率的含义",
                label: "[选区：利率的含义]",
                excerpt: "利率是资金的价格。"
            ),
        ],
        courseContext: StudyAgentCourseContext(
            title: "测试课程",
            catalog: [
                StudyAgentCourseCatalogItem(
                    id: "persistent-material",
                    title: "利率的含义",
                    subtitle: "测试文稿",
                    kind: "markdown",
                    role: "material"
                ),
            ]
        ),
        projectScope: StudyAgentProjectScope(
            kind: .course,
            chatID: "bridge-chat",
            courseID: UUID().uuidString.lowercased()
        ),
        contextRevision: "bridge-test"
    )
    let reply = try await runtime.respond(
        to: request,
        sessionID: UUID(),
        workingDirectory: try fixture.workingDirectory(named: "BridgeProject"),
        hostToolHandler: { toolRequest in
            guard toolRequest == .courseRead(
                itemID: "persistent-material",
                query: "",
                location: nil,
                cursor: nil,
                maximumCharacters: 6_000
            ) else {
                throw PiTerminalRuntimeSelfCheckError.failed("PI host bridge received invalid arguments")
            }
            return StudyAgentHostToolResult(
                query: "利率",
                items: [
                    StudyAgentHostToolItem(
                        item: StudyAgentCourseItem(
                            id: "persistent-material",
                            title: "利率的含义",
                            subtitle: "测试文稿",
                            kind: "markdown",
                            role: "material",
                            searchText: "利率是资金的价格。FULL_ARTICLE_TAIL_TOKEN"
                        )
                    ),
                ]
            )
        },
        progress: nil
    )
    await runtime.shutdown()
    guard reply.text == "宿主课程全文读取可用。",
          reply.sources.isEmpty else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI host tool bridge returned an invalid reply or attached an uncited source"
        )
    }
    guard !FileManager.default.fileExists(atPath: staleResponseDirectory.path) else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI host tool bridge kept a response directory left by a crashed run"
        )
    }
}

private func checkUserStopReturnsImmediately(_ fixture: PiTerminalRuntimeFixture) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "CancelMode"),
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let probe = PiProgressProbe()
    let run = Task {
        await terminalOutcome(runtime: runtime, revision: "cancel-test") { event in
            await probe.record(event)
        }
    }
    guard await probe.waitForPreparing() else {
        await runtime.shutdown()
        throw PiTerminalRuntimeSelfCheckError.failed("PI cancellation fixture never reached the active run")
    }
    try? await Task.sleep(nanoseconds: 100_000_000)

    let startedAt = Date()
    await runtime.cancel()
    let cancellationSeconds = Date().timeIntervalSince(startedAt)
    let outcome = await run.value
    await runtime.shutdown()

    guard outcome == "error:PI 请求已取消", cancellationSeconds < 0.5 else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI stop waited for the unresponsive abort command (outcome=\(outcome), seconds=\(cancellationSeconds))"
        )
    }
}

private func checkCancelledTurnCannotAffectImmediateNextChat(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "LateCancelRuntime"),
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let probe = PiProgressProbe()
    let firstWorkingDirectory = try fixture.workingDirectory(named: "LateCancelModeA")
    let firstRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "启动后立即切换",
        materialTitle: "",
        materialText: "",
        noteTitle: "",
        noteText: "",
        contextRevision: "cancel-a"
    )
    let firstRun = Task {
        do {
            _ = try await runtime.respond(
                to: firstRequest,
                sessionID: UUID(),
                workingDirectory: firstWorkingDirectory
            ) { event in
                await probe.record(event)
            }
            return "unexpected-success"
        } catch {
            return error.localizedDescription
        }
    }
    guard await probe.waitForPreparing() else {
        await runtime.shutdown()
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI immediate-switch fixture never reached the first active turn"
        )
    }

    await runtime.cancel()
    let firstOutcome = await firstRun.value
    let secondRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "在第二个 Chat 直接回答",
        materialTitle: "",
        materialText: "",
        noteTitle: "",
        noteText: "",
        contextRevision: "direct-answer-test"
    )
    let secondReply = try await runtime.respond(
        to: secondRequest,
        sessionID: UUID(),
        workingDirectory: try fixture.workingDirectory(named: "DirectAnswerModeB"),
        progress: nil
    )
    await runtime.shutdown()

    guard firstOutcome == PiAgentRuntimeError.cancelled.localizedDescription,
          secondReply.text == "普通回答没有来源也能显示。" else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "取消 A 后立即发送 B 时出现忙碌或旧进程事件串入（A=\(firstOutcome)，B=\(secondReply.text)）"
        )
    }
}

private func checkTerminalErrorBypassesSlowProgress(_ fixture: PiTerminalRuntimeFixture) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "ErrorMode"),
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let startedAt = Date()
    let outcome = await terminalOutcome(runtime: runtime, revision: "error-test") { event in
        if case .text = event {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
    let completionSeconds = Date().timeIntervalSince(startedAt)
    await runtime.shutdown()

    guard outcome == "error:PI 回答失败：真实终止错误", completionSeconds < 1.0 else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI terminal error was hidden or blocked behind progress delivery (outcome=\(outcome), seconds=\(completionSeconds))"
        )
    }
}

private func checkGenericEventsDoNotDefeatWatchdog(_ fixture: PiTerminalRuntimeFixture) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "HeartbeatMode"),
        runInactivityTimeoutNanoseconds: 300_000_000
    )
    let startedAt = Date()
    let outcome = await terminalOutcomeWithin(
        runtime: runtime,
        revision: "heartbeat-test",
        timeoutNanoseconds: 1_500_000_000
    )
    let completionSeconds = Date().timeIntervalSince(startedAt)
    await runtime.shutdown()

    let expectedTimeout = "error:\(PiAgentRuntimeError.commandTimedOut("prompt").localizedDescription)"
    guard outcome == expectedTimeout, completionSeconds < 1.5 else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI generic event spam defeated the inactivity watchdog (outcome=\(outcome), seconds=\(completionSeconds))"
        )
    }
}

private func terminalOutcomeWithin(
    runtime: PiAgentRuntime,
    revision: String,
    timeoutNanoseconds: UInt64
) async -> String {
    await withTaskGroup(of: String.self) { group in
        group.addTask {
            await terminalOutcome(runtime: runtime, revision: revision, progress: nil)
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return "self-check-timeout"
        }
        let first = await group.next() ?? "self-check-timeout"
        group.cancelAll()
        return first
    }
}

private func checkMeaningfulThinkingKeepsRunAlive(_ fixture: PiTerminalRuntimeFixture) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "ThinkingMode"),
        runInactivityTimeoutNanoseconds: 300_000_000
    )
    let outcome = await terminalOutcome(runtime: runtime, revision: "thinking-test", progress: nil)
    await runtime.shutdown()

    guard outcome == "reply:[材料：测试材料] 思考完成" else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI meaningful thinking did not keep the run alive (\(outcome))"
        )
    }
}

private func checkRejectedRichAnswerKeepsSafeNarrative(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "RichFallbackMode"),
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "请解释测试材料",
        materialTitle: "测试材料",
        materialText: "测试正文",
        noteTitle: "测试笔记",
        noteText: "",
        contextRevision: "rich-fallback-test"
    )

    do {
        let reply = try await runtime.respond(to: request)
        await runtime.shutdown()
        guard reply.text == "[材料：测试材料] 安全正文",
              reply.richAnswer == nil else {
            throw PiTerminalRuntimeSelfCheckError.failed(
                "PI narrative-only admission lost its safe text or attached a rejected rich block"
            )
        }
    } catch {
        await runtime.shutdown()
        throw error
    }
}

private func checkRejectedActionKeepsOrdinaryAnswer(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "DirectAnswerMode"),
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "直接回答这个普通问题",
        materialTitle: "",
        materialText: "",
        noteTitle: "",
        noteText: "",
        contextRevision: "direct-answer-test"
    )

    do {
        let reply = try await runtime.respond(to: request)
        await runtime.shutdown()
        guard reply.text == "普通回答没有来源也能显示。",
              reply.noteProposal == nil,
              reply.toolTrace.contains(where: {
                  $0.hasPrefix("weibei_note_proposal:host_rejected=")
              }) else {
            throw PiTerminalRuntimeSelfCheckError.failed(
                "PI rejected action swallowed an ordinary source-free answer"
            )
        }
    } catch {
        await runtime.shutdown()
        throw error
    }
}

private func checkRelationProposalUsesCurrentCourseCatalog(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "RelationProposalRuntime"),
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "建议把这份笔记关联到另一份材料",
        materialTitle: "",
        materialText: "",
        noteTitle: "",
        noteText: "",
        courseContext: StudyAgentCourseContext(
            title: "测试课程",
            catalog: [
                StudyAgentCourseCatalogItem(
                    id: "persistent-note",
                    title: "利率笔记",
                    subtitle: "测试笔记",
                    kind: "markdown",
                    role: "note"
                ),
                StudyAgentCourseCatalogItem(
                    id: "persistent-material-a",
                    title: "利率材料",
                    subtitle: "测试文稿",
                    kind: "markdown",
                    role: "material"
                ),
                StudyAgentCourseCatalogItem(
                    id: "persistent-material-b",
                    title: "费雪方程",
                    subtitle: "测试文稿",
                    kind: "markdown",
                    role: "material"
                ),
            ],
            relations: [
                StudyAgentCourseRelation(
                    noteItemID: "persistent-note",
                    sourceItemID: "persistent-material-a"
                ),
            ]
        ),
        projectScope: StudyAgentProjectScope(
            kind: .course,
            chatID: "relation-proposal-chat",
            courseID: UUID().uuidString.lowercased()
        ),
        contextRevision: "relation-proposal-test"
    )

    let reply = try await runtime.respond(
        to: request,
        sessionID: UUID(),
        workingDirectory: try fixture.workingDirectory(named: "RelationProposalMode"),
        progress: nil
    )
    await runtime.shutdown()

    guard reply.text == "关系建议不影响正文。",
          reply.relationProposal == StudyAgentRelationProposal(
              noteItemID: "persistent-note",
              sourceItemID: "persistent-material-b",
              contextRevision: "relation-proposal-test"
          ),
          reply.toolTrace.filter({
              $0.hasPrefix("weibei_relation_proposal:host_rejected=")
          }).count == 2 else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI relation proposal escaped the current course catalog or swallowed the answer"
        )
    }
}

private func checkPersistedSelectionSourcesAttachWithoutReadTool(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "FocusAnswerRuntime"),
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "解释当前材料",
        materialTitle: "测试材料",
        materialText: "利率是资金的价格。",
        noteTitle: "",
        noteText: "",
        selectionTitle: "2 个已选文本片段",
        selectionText: "片段 1：名义利率。\n片段 2：实际利率。",
        selectionSources: [
            AgentReplySource(
                itemID: "persistent-material",
                kind: .selection,
                title: "测试材料",
                label: "[选区：测试材料]",
                excerpt: "名义利率。"
            ),
            AgentReplySource(
                itemID: "persistent-note",
                kind: .selection,
                title: "测试笔记",
                label: "[选区：测试笔记]",
                excerpt: "实际利率。"
            ),
        ],
        courseContext: StudyAgentCourseContext(
            title: "测试课程",
            catalog: [
                StudyAgentCourseCatalogItem(
                    id: "persistent-material",
                    title: "测试材料",
                    subtitle: "测试文稿",
                    kind: "markdown",
                    role: "material",
                    isCurrentMaterial: true
                ),
            ]
        ),
        projectScope: StudyAgentProjectScope(
            kind: .course,
            chatID: "focus-chat",
            courseID: UUID().uuidString.lowercased()
        ),
        contextRevision: "focus-answer-test"
    )

    let reply = try await runtime.respond(
        to: request,
        sessionID: UUID(),
        workingDirectory: try fixture.workingDirectory(named: "FocusAnswerMode"),
        progress: nil
    )
    await runtime.shutdown()

    guard reply.text == "[选区：2 个已选文本片段] 当前选区可直接回答。",
          reply.sources.count == 2,
          reply.sources.contains(where: { $0.label == "[选区：测试材料]" }),
          reply.sources.contains(where: { $0.label == "[选区：测试笔记]" }) else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI did not attach the persisted selection sources without reading another source"
        )
    }
}

private func checkContextSnapshotLivesUntilProcessShutdown(_ fixture: PiTerminalRuntimeFixture) async throws {
    let runtimeDirectory = try fixture.workingDirectory(named: "ThinkingModeContext")
    let contextURL = runtimeDirectory.appendingPathComponent("context.json")
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: runtimeDirectory,
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let outcome = await terminalOutcome(runtime: runtime, revision: "thinking-test", progress: nil)

    await runtime.shutdown()
    guard outcome == "reply:[材料：测试材料] 思考完成",
          !FileManager.default.fileExists(atPath: contextURL.path) else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI turn did not complete normally or its context survived the post-turn process boundary"
        )
    }
}

private func checkConversationBindingLaunchContract(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtimeDirectory = try fixture.workingDirectory(named: "SessionRuntime")
    let projectDirectory = try fixture.workingDirectory(named: "SessionProject")
    let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let secondSessionID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: runtimeDirectory,
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    await runtime.configure(
        PiAgentProviderConfiguration(
            provider: "openai-codex",
            model: AgentModelListService.codexDefaultModel
        )
    )

    for turn in 1...2 {
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: "第 \(turn) 问",
            materialTitle: "测试材料",
            materialText: "测试正文",
            noteTitle: "测试笔记",
            noteText: "",
            selectionTitle: turn == 1 ? "第一讲选区" : nil,
            selectionText: turn == 1 ? "注意力只处理当前上下文" : nil,
            selectionSources: turn == 1
                ? [
                    AgentReplySource(
                        itemID: "material-1",
                        kind: .selection,
                        title: "第一讲",
                        label: "[选区：第一讲]",
                        excerpt: "注意力只处理当前上下文",
                        pageIndex: 17
                    ),
                ]
                : [],
            courseContext: StudyAgentCourseContext(
                title: "测试课程",
                catalog: [
                    StudyAgentCourseCatalogItem(
                        id: "material-1",
                        title: "第一讲",
                        subtitle: "测试文稿",
                        kind: "markdown",
                        role: "material",
                        isCurrentMaterial: true
                    ),
                ]
            ),
            contextRevision: "session-\(turn)"
        )
        let reply = try await runtime.respond(
            to: request,
            sessionID: sessionID,
            workingDirectory: projectDirectory,
            progress: nil
        )
        guard reply.text == "[材料：测试材料] 第 \(turn) 次回答" else {
            await runtime.shutdown()
            throw PiTerminalRuntimeSelfCheckError.failed(
                "同一 Chat 第 \(turn) 轮没有正常完成（\(reply.text)）"
            )
        }
    }
    for (chatID, revision) in [
        (secondSessionID, "session-b"),
        (sessionID, "session-a-return"),
    ] {
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: "切换 Chat",
            materialTitle: "测试材料",
            materialText: "测试正文",
            noteTitle: "测试笔记",
            noteText: "",
            contextRevision: revision
        )
        _ = try await runtime.respond(
            to: request,
            sessionID: chatID,
            workingDirectory: projectDirectory,
            progress: nil
        )
    }
    try await runtime.deleteSession(secondSessionID)
    let firstSessionDirectory = runtimeDirectory
        .appendingPathComponent("Sessions", isDirectory: true)
        .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    let secondSessionDirectory = runtimeDirectory
        .appendingPathComponent("Sessions", isDirectory: true)
        .appendingPathComponent(secondSessionID.uuidString.lowercased(), isDirectory: true)
    guard FileManager.default.fileExists(atPath: firstSessionDirectory.path),
          !FileManager.default.fileExists(atPath: secondSessionDirectory.path) else {
        await runtime.shutdown()
        throw PiTerminalRuntimeSelfCheckError.failed(
            "删除 Chat B 的 Pi 状态时影响了 Chat A，或没有清理 B"
        )
    }
    await runtime.shutdown()

    let traceURL = projectDirectory.appendingPathComponent(".fake-pi-trace.log")
    let trace = try String(contentsOf: traceURL, encoding: .utf8)
    let expectedWorkingDirectories = [
        projectDirectory.path,
        projectDirectory.path.hasPrefix("/private/")
            ? String(projectDirectory.path.dropFirst("/private".count))
            : "/private\(projectDirectory.path)",
    ]
    guard trace.components(separatedBy: "launch\n").count - 1 == 4,
          expectedWorkingDirectories.contains(where: { trace.contains("cwd=\($0)\n") }),
          trace.components(
              separatedBy: "arg=--session-id\narg=\(sessionID.uuidString.lowercased())\n"
          ).count - 1 == 3,
          trace.contains("arg=--session-id\narg=\(secondSessionID.uuidString.lowercased())\n"),
          trace.components(separatedBy: "arg=--session-dir\n").count - 1 == 4,
          trace.components(
              separatedBy: "/Sessions/\(sessionID.uuidString.lowercased())\n"
          ).count - 1 == 3,
          trace.contains("/Sessions/\(secondSessionID.uuidString.lowercased())\n"),
          trace.components(
              separatedBy: "arg=--provider\narg=openai-codex\n"
          ).count - 1 == 4,
          trace.components(
              separatedBy: "arg=--model\narg=\(AgentModelListService.codexDefaultModel)\n"
          ).count - 1 == 4,
          trace.contains("prompt-message=[选中文字：第一讲选区]") &&
          trace.contains("注意力只处理当前上下文") &&
          trace.contains("[选区：第一讲]；条目 ID：course-item-1；第 18 页") &&
          trace.contains("[问题]\\n第 1 问"),
          trace.contains("prompt-message=第 2 问\n"),
          trace.contains("prompt-message=切换 Chat\n"),
          !trace.contains("prompt-message=/skill:"),
          !trace.contains("arg=--no-session\n"),
          !trace.contains("command=new_session\n"),
          trace.components(separatedBy: "command=prompt\n").count - 1 == 4,
          trace.components(separatedBy: "recent=absent\n").count - 1 == 4 else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "Chat 复用、切换隔离或原生历史合同不成立：\n\(trace)"
        )
    }
}

private func checkMissingSessionStartsFreshNativeHistory(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtimeDirectory = try fixture.workingDirectory(named: "RecoveryRuntime")
    let projectDirectory = try fixture.workingDirectory(named: "RecoveryProject")
    let sessionID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: runtimeDirectory,
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "继续此前对话",
        materialTitle: "测试材料",
        materialText: "测试正文",
        noteTitle: "测试笔记",
        noteText: "",
        contextRevision: "recovery-turn"
    )
    _ = try await runtime.respond(
        to: request,
        sessionID: sessionID,
        workingDirectory: projectDirectory,
        progress: nil
    )
    await runtime.shutdown()

    let trace = try String(
        contentsOf: projectDirectory.appendingPathComponent(".fake-pi-trace.log"),
        encoding: .utf8
    )
    guard trace.components(separatedBy: "launch\n").count - 1 == 1,
          trace.contains("state-message-count=0\n"),
          trace.contains("recent=absent\n") else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "Pi 会话缺失时没有从原生空会话开始：\n\(trace)"
        )
    }
}

private func checkWrongSessionStateRebuildsOnlyRequestedChat(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtimeDirectory = try fixture.workingDirectory(named: "WrongStateRuntime")
    let projectDirectory = try fixture.workingDirectory(named: "WrongStateProject")
    let sessionID = UUID(uuidString: "12345678-2222-3333-4444-555555555555")!
    let siblingSessionID = UUID(uuidString: "87654321-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let sessionsDirectory = runtimeDirectory.appendingPathComponent("Sessions", isDirectory: true)
    let sessionDirectory = sessionsDirectory
        .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    let siblingDirectory = sessionsDirectory
        .appendingPathComponent(siblingSessionID.uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: siblingDirectory, withIntermediateDirectories: true)
    let corruptMarker = sessionDirectory.appendingPathComponent("corrupt-session")
    let siblingMarker = siblingDirectory.appendingPathComponent("must-survive")
    try Data("broken".utf8).write(to: corruptMarker)
    try Data("safe".utf8).write(to: siblingMarker)

    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: runtimeDirectory,
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "从损坏会话继续",
        materialTitle: "测试材料",
        materialText: "测试正文",
        noteTitle: "测试笔记",
        noteText: "",
        contextRevision: "wrong-state-recovery"
    )
    _ = try await runtime.respond(
        to: request,
        sessionID: sessionID,
        workingDirectory: projectDirectory,
        progress: nil
    )
    await runtime.shutdown()

    let trace = try String(
        contentsOf: projectDirectory.appendingPathComponent(".fake-pi-trace.log"),
        encoding: .utf8
    )
    guard trace.components(separatedBy: "launch\n").count - 1 == 2,
          trace.contains("state-session=wrong\n"),
          trace.contains("state-session=correct\n"),
          trace.components(separatedBy: "command=prompt\n").count - 1 == 1,
          trace.contains("recent=absent\n"),
          !FileManager.default.fileExists(atPath: corruptMarker.path),
          FileManager.default.fileExists(atPath: siblingMarker.path) else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "错误会话状态没有单次重建目标 Chat，或误伤了兄弟 Chat：\n\(trace)"
        )
    }
}

private func checkUnreadableStoredSessionRebuildsOnce(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let runtimeDirectory = try fixture.workingDirectory(named: "UnreadableStateRuntime")
    let projectDirectory = try fixture.workingDirectory(named: "UnreadableStateProject")
    let sessionID = UUID(uuidString: "12345678-1111-3333-4444-555555555555")!
    let sessionDirectory = runtimeDirectory
        .appendingPathComponent("Sessions", isDirectory: true)
        .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
    try Data("broken".utf8).write(
        to: sessionDirectory.appendingPathComponent("corrupt-session")
    )
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: runtimeDirectory,
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "恢复无法读取的会话",
        materialTitle: "测试材料",
        materialText: "测试正文",
        noteTitle: "测试笔记",
        noteText: "",
        contextRevision: "unreadable-state-recovery"
    )
    _ = try await runtime.respond(
        to: request,
        sessionID: sessionID,
        workingDirectory: projectDirectory,
        progress: nil
    )
    await runtime.shutdown()

    let trace = try String(
        contentsOf: projectDirectory.appendingPathComponent(".fake-pi-trace.log"),
        encoding: .utf8
    )
    guard trace.components(separatedBy: "launch\n").count - 1 == 2,
          trace.contains("state-session=unreadable\n"),
          trace.contains("state-session=correct\n"),
          trace.components(separatedBy: "command=prompt\n").count - 1 == 1,
          trace.contains("recent=absent\n") else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "已有 Pi 会话无法读取时没有只重建一次原生会话：\n\(trace)"
        )
    }
}

private func checkStandardProxyEnvironmentIsForwarded(
    _ fixture: PiTerminalRuntimeFixture
) async throws {
    let proxyName = "all_proxy"
    let previousProxy = getenv(proxyName).map { String(cString: $0) }
    setenv(proxyName, "http://127.0.0.1:61234", 1)
    defer {
        if let previousProxy {
            setenv(proxyName, previousProxy, 1)
        } else {
            unsetenv(proxyName)
        }
    }

    let projectDirectory = try fixture.workingDirectory(named: "ProxyProject")
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: try fixture.workingDirectory(named: "ProxyRuntime"),
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "检查网络路由",
        materialTitle: "测试材料",
        materialText: "测试正文",
        noteTitle: "测试笔记",
        noteText: "",
        contextRevision: "proxy-environment"
    )
    _ = try await runtime.respond(
        to: request,
        sessionID: UUID(),
        workingDirectory: projectDirectory,
        progress: nil
    )
    await runtime.shutdown()

    let trace = try String(
        contentsOf: projectDirectory.appendingPathComponent(".fake-pi-trace.log"),
        encoding: .utf8
    )
    guard trace.contains("all_proxy=http://127.0.0.1:61234\n") else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "Pi 子进程没有继承用户已配置的标准代理入口"
        )
    }
}

private func terminalOutcome(
    runtime: PiAgentRuntime,
    revision: String,
    progress: StudyAgentProgressHandler?
) async -> String {
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "请解释测试材料",
        materialTitle: "测试材料",
        materialText: "测试正文",
        noteTitle: "测试笔记",
        noteText: "",
        contextRevision: revision
    )
    do {
        let reply = try await runtime.respond(to: request, progress: progress)
        return "reply:\(reply.text)"
    } catch {
        return "error:\(error.localizedDescription)"
    }
}

private func makePiTerminalRuntimeFixture() throws -> PiTerminalRuntimeFixture {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("weibei-pi-terminal-\(UUID().uuidString)", isDirectory: true)
    let runtimeURL = rootURL.appendingPathComponent("PiRuntime", isDirectory: true)
    let binURL = runtimeURL.appendingPathComponent("bin", isDirectory: true)
    let themeURL = binURL.appendingPathComponent("theme", isDirectory: true)
    let executableURL = binURL.appendingPathComponent("pi")
    let sourceURL = rootURL.appendingPathComponent("fake-pi.c")

    try fileManager.createDirectory(at: themeURL, withIntermediateDirectories: true)
    try Data(fakePiTerminalSource.utf8).write(to: sourceURL, options: .atomic)
    try runPiFixtureCommand(
        executableURL: URL(fileURLWithPath: "/usr/bin/clang"),
        arguments: [sourceURL.path, "-O0", "-o", executableURL.path]
    )
    try runPiFixtureCommand(
        executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
        arguments: ["--force", "--sign", "-", executableURL.path]
    )

    try Data(#"{"version":"0.82.1"}"#.utf8)
        .write(to: binURL.appendingPathComponent("package.json"), options: .atomic)
    try Data("{}\n".utf8).write(to: themeURL.appendingPathComponent("dark.json"), options: .atomic)
    try Data("{}\n".utf8).write(to: themeURL.appendingPathComponent("light.json"), options: .atomic)
    try Data("MIT\n".utf8).write(to: runtimeURL.appendingPathComponent("LICENSE"), options: .atomic)
    try Data("Self-check fixture only.\n".utf8)
        .write(to: runtimeURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"), options: .atomic)
    let manifest = #"{"schemaVersion":1,"piVersion":"0.82.1","sourceRepository":"self-check","sourceCommit":"0000000000000000000000000000000000000000","license":"MIT"}"#
    try Data(manifest.utf8).write(to: runtimeURL.appendingPathComponent("manifest.json"), options: .atomic)

    let executableData = try Data(contentsOf: executableURL)
    let hash = SHA256.hash(data: executableData).map { String(format: "%02x", $0) }.joined()
    try Data("\(hash)\n".utf8).write(to: runtimeURL.appendingPathComponent("binary.sha256"), options: .atomic)

    return PiTerminalRuntimeFixture(rootURL: rootURL, executableURL: executableURL)
}

private func runPiFixtureCommand(executableURL: URL, arguments: [String]) throws {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let detail = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw PiTerminalRuntimeSelfCheckError.failed(
            "fixture command failed: \(executableURL.lastPathComponent) \(detail)"
        )
    }
}

private let fakePiTerminalSource = #"""
#include <signal.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static pid_t emitter_pid = -1;
static int cancel_mode = 0;
static int late_cancel_mode = 0;
static int session_mode = 0;
static int wrong_state_mode = 0;
static int unreadable_state_mode = 0;
static int session_turn = 0;
static char session_id[128] = "";
static char session_directory[PATH_MAX] = "";
static char trace_path[PATH_MAX] = "";

static void load_session_turn(void) {
    if (session_directory[0] == '\0') return;
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/fake-turn-count", session_directory);
    FILE *file = fopen(path, "r");
    if (file == NULL) return;
    fscanf(file, "%d", &session_turn);
    fclose(file);
}

static void save_session_turn(void) {
    if (session_directory[0] == '\0') return;
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/fake-turn-count", session_directory);
    FILE *file = fopen(path, "w");
    if (file == NULL) return;
    fprintf(file, "%d\n", session_turn);
    fclose(file);
}

static int json_value(const char *line, const char *key, char *output, size_t capacity) {
    char pattern[64];
    snprintf(pattern, sizeof(pattern), "\"%s\":\"", key);
    const char *start = strstr(line, pattern);
    if (start == NULL) return 0;
    start += strlen(pattern);
    const char *end = strchr(start, '\"');
    if (end == NULL) return 0;
    size_t length = (size_t)(end - start);
    if (length + 1 > capacity) return 0;
    memcpy(output, start, length);
    output[length] = '\0';
    return 1;
}

static void respond(const char *id, const char *command, const char *data) {
    printf("{\"id\":\"%s\",\"type\":\"response\",\"command\":\"%s\",\"success\":true,\"data\":%s}\n", id, command, data);
    fflush(stdout);
}

static void trace_line(const char *key, const char *value) {
    if (trace_path[0] == '\0') return;
    FILE *trace = fopen(trace_path, "a");
    if (trace == NULL) return;
    if (value == NULL) {
        fprintf(trace, "%s\n", key);
    } else {
        fprintf(trace, "%s=%s\n", key, value);
    }
    fclose(trace);
}

static int read_context(char **output) {
    const char *path = getenv("WEIBEI_AGENT_CONTEXT_FILE");
    if (path == NULL) return 0;
    FILE *file = fopen(path, "r");
    if (file == NULL) return 0;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return 0;
    }
    long length = ftell(file);
    if (length < 0 || length > 1024 * 1024 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
    char *buffer = calloc((size_t)length + 1, 1);
    if (buffer == NULL) {
        fclose(file);
        return 0;
    }
    size_t read_length = fread(buffer, 1, (size_t)length, file);
    fclose(file);
    buffer[read_length] = '\0';
    *output = buffer;
    return 1;
}

static void stop_emitter(void) {
    if (emitter_pid <= 0) return;
    kill(emitter_pid, SIGTERM);
    waitpid(emitter_pid, NULL, 0);
    emitter_pid = -1;
}

static void terminate_fixture(int signal_number) {
    (void)signal_number;
    if (emitter_pid > 0) kill(emitter_pid, SIGTERM);
    if (late_cancel_mode) {
        usleep(200000);
        const char *late_events =
            "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"A 的迟到正文\"}}\n"
            "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"A 的迟到终止事件\"}],\"stopReason\":\"stop\"}]}\n";
        write(STDOUT_FILENO, late_events, strlen(late_events));
    }
    _exit(0);
}

static void start_emitter(void) {
    if (emitter_pid > 0) return;
    char cwd[PATH_MAX];
    getcwd(cwd, sizeof(cwd));
    late_cancel_mode = strstr(cwd, "LateCancelMode") != NULL;
    cancel_mode = strstr(cwd, "CancelMode") != NULL;
    int error_mode = strstr(cwd, "ErrorMode") != NULL;
    int thinking_mode = strstr(cwd, "ThinkingMode") != NULL;
    int rich_fallback_mode = strstr(cwd, "RichFallbackMode") != NULL;
    int direct_answer_mode = strstr(cwd, "DirectAnswerMode") != NULL;
    int relation_proposal_mode = strstr(cwd, "RelationProposalMode") != NULL;
    int focus_answer_mode = strstr(cwd, "FocusAnswerMode") != NULL;
    int bridge_mode = strstr(cwd, "BridgeProject") != NULL;
    emitter_pid = fork();
    if (emitter_pid != 0) return;

    if (error_mode) {
        for (int index = 0; index < 256; index++) {
            printf("{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"临时文本\"}}\n");
        }
        printf("{\"type\":\"message_end\",\"message\":{\"role\":\"assistant\",\"stopReason\":\"error\",\"errorMessage\":\"真实终止错误\"}}\n");
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[],\"stopReason\":\"error\",\"diagnostics\":[{\"error\":{\"message\":\"真实终止错误\"}}]}]}\n");
        fflush(stdout);
        _exit(0);
    }

    if (thinking_mode) {
        for (int index = 0; index < 6; index++) {
            if (index == 1 || index == 2) {
                printf("{\"type\":\"tool_execution_update\",\"toolCallId\":\"tool-long\",\"toolName\":\"weibei_course_search\"}\n");
            } else if (index == 3) {
                printf("{\"type\":\"auto_retry_start\",\"attempt\":2}\n");
            } else {
                printf("{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"thinking_delta\",\"delta\":\"核对中\"}}\n");
            }
            fflush(stdout);
            usleep(120000);
        }
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"[材料：测试材料] 思考完成\"}],\"stopReason\":\"stop\"}]}\n");
        fflush(stdout);
        _exit(0);
    }

    if (rich_fallback_mode) {
        printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"rich-fallback\",\"toolName\":\"weibei_rich_answer\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"rich_answer\",\"contextRevision\":\"rich-fallback-test\",\"envelope\":{\"schemaVersion\":2,\"contextRevision\":\"rich-fallback-test\",\"narrative\":\"[材料：测试材料] 应保留的正文\",\"expressionPlan\":{\"action\":\"explain\",\"summary\":\"安全降级\",\"families\":[\"textAndAlignment\"],\"preferredSurface\":\"inline\",\"directManipulation\":false},\"scenes\":[{\"id\":\"rejected-scene\",\"title\":\"无效场景\",\"family\":\"textAndAlignment\",\"objects\":[],\"evidenceIDs\":[\"missing-evidence\"]}],\"evidenceLedger\":[],\"fallback\":{\"text\":\"[材料：测试材料] 安全正文\",\"reason\":\"场景被拒绝\"}}}}}\n");
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"模型收尾文字\"}],\"stopReason\":\"stop\"}]}\n");
        fflush(stdout);
        _exit(0);
    }

    if (direct_answer_mode) {
        char *context = NULL;
        int has_chat_id = read_context(&context)
            && strstr(context, "\"chatID\":\"") != NULL
            && strstr(context, "\"chatID\":\"\"") == NULL;
        free(context);
        printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"invalid-note\",\"toolName\":\"weibei_note_proposal\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"note_proposal\",\"markdown\":\"不应写入\",\"evidence\":[],\"contextRevision\":\"stale-revision\"}}}\n");
        printf(
            "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"%s\"}}\n",
            has_chat_id ? "普通回答没有来源也能显示。" : "默认全局 Chat 身份缺失。"
        );
        printf(
            "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"%s\"}],\"stopReason\":\"stop\"}]}\n",
            has_chat_id ? "普通回答没有来源也能显示。" : "默认全局 Chat 身份缺失。"
        );
        fflush(stdout);
        _exit(0);
    }

    if (relation_proposal_mode) {
        printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"existing-relation\",\"toolName\":\"weibei_relation_proposal\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"relation_proposal\",\"noteItemID\":\"course-item-1\",\"sourceItemID\":\"course-item-2\",\"contextRevision\":\"relation-proposal-test\"}}}\n");
        printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"swapped-relation\",\"toolName\":\"weibei_relation_proposal\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"relation_proposal\",\"noteItemID\":\"course-item-2\",\"sourceItemID\":\"course-item-1\",\"contextRevision\":\"relation-proposal-test\"}}}\n");
        printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"valid-relation\",\"toolName\":\"weibei_relation_proposal\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"relation_proposal\",\"noteItemID\":\"course-item-1\",\"sourceItemID\":\"course-item-3\",\"contextRevision\":\"relation-proposal-test\"}}}\n");
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"关系建议不影响正文。\"}],\"stopReason\":\"stop\"}]}\n");
        fflush(stdout);
        _exit(0);
    }

    if (focus_answer_mode) {
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"[选区：2 个已选文本片段] 当前选区可直接回答。\"}],\"stopReason\":\"stop\"}]}\n");
        fflush(stdout);
        _exit(0);
    }

    if (bridge_mode) {
        char *context = NULL;
        char revision[128] = "";
        char request_id[128] = "";
        if (read_context(&context)) {
            json_value(context, "contextRevision", revision, sizeof(revision));
            json_value(context, "requestID", request_id, sizeof(request_id));
            free(context);
        }
        printf("{\"type\":\"tool_execution_start\",\"toolCallId\":\"bridge-read\",\"toolName\":\"weibei_course_read\",\"args\":{\"itemID\":\"course-item-1\",\"query\":\"\",\"limit\":5}}\n");
        fflush(stdout);
        const char *response_root = getenv("WEIBEI_AGENT_TOOL_RESPONSE_DIR");
        char response_path[PATH_MAX];
        snprintf(
            response_path,
            sizeof(response_path),
            "%s/%s/d1c5a80cf77478cb5f65bc199c19d5a52ff009dbfd8ad53ec443b5b55e7c6c3e.json",
            response_root == NULL ? "" : response_root,
            request_id
        );
        int ready = 0;
        for (int index = 0; index < 250; index++) {
            FILE *response = fopen(response_path, "r");
            if (response != NULL) {
                char buffer[8192] = "";
                size_t length = fread(buffer, 1, sizeof(buffer) - 1, response);
                fclose(response);
                buffer[length] = '\0';
                ready = strstr(buffer, "\"success\":true") != NULL
                    && strstr(buffer, "\"toolCallID\":\"bridge-read\"") != NULL
                    && strstr(buffer, "\"id\":\"course-item-1\"") != NULL
                    && strstr(buffer, "FULL_ARTICLE_TAIL_TOKEN") != NULL;
                break;
            }
            usleep(20000);
        }
        printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"bridge-read\",\"toolName\":\"weibei_course_read\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"course_read\",\"contextRevision\":\"%s\",\"results\":[{\"id\":\"course-item-1\",\"title\":\"利率的含义\",\"role\":\"material\",\"searchText\":\"利率是资金的价格。FULL_ARTICLE_TAIL_TOKEN\"}],\"evidenceLabels\":[\"[材料：利率的含义]\"],\"jumpEvidence\":{}}}}\n", revision);
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"%s\"}],\"stopReason\":\"stop\"}]}\n", ready ? "宿主课程全文读取可用。" : "宿主课程全文读取缺失。");
        fflush(stdout);
        _exit(0);
    }

    for (;;) {
        printf("{\"type\":\"future_event\"}\n");
        fflush(stdout);
        usleep(20000);
    }
}

int main(int argc, char **argv) {
    signal(SIGTERM, terminate_fixture);
    setvbuf(stdout, NULL, _IOLBF, 0);
    char cwd[PATH_MAX];
    getcwd(cwd, sizeof(cwd));
    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--session-id") == 0 && index + 1 < argc) {
            snprintf(session_id, sizeof(session_id), "%s", argv[index + 1]);
        } else if (strcmp(argv[index], "--session-dir") == 0 && index + 1 < argc) {
            snprintf(session_directory, sizeof(session_directory), "%s", argv[index + 1]);
        }
    }
    wrong_state_mode = strstr(cwd, "WrongStateProject") != NULL;
    unreadable_state_mode = strstr(cwd, "UnreadableStateProject") != NULL;
    session_mode = strstr(cwd, "SessionProject") != NULL
        || strstr(cwd, "RecoveryProject") != NULL
        || strstr(cwd, "ProxyProject") != NULL
        || wrong_state_mode
        || unreadable_state_mode;
    load_session_turn();
    if (session_mode) {
        snprintf(trace_path, sizeof(trace_path), "%s/.fake-pi-trace.log", cwd);
        trace_line("launch", NULL);
        trace_line("cwd", cwd);
        if (strstr(cwd, "ProxyProject") != NULL) {
            trace_line("all_proxy", getenv("all_proxy"));
        }
        for (int index = 1; index < argc; index++) {
            if (strcmp(argv[index], "--session-id") == 0 && index + 1 < argc) {
                trace_line("arg", argv[index]);
                trace_line("arg", argv[index + 1]);
            } else if (strcmp(argv[index], "--session-dir") == 0 && index + 1 < argc) {
                trace_line("arg", argv[index]);
                trace_line("arg", argv[index + 1]);
            } else if ((strcmp(argv[index], "--provider") == 0
                        || strcmp(argv[index], "--model") == 0)
                       && index + 1 < argc) {
                trace_line("arg", argv[index]);
                trace_line("arg", argv[index + 1]);
            } else if (strcmp(argv[index], "--no-session") == 0) {
                trace_line("arg", argv[index]);
            }
        }
    }
    char *line = NULL;
    size_t line_capacity = 0;
    while (getline(&line, &line_capacity, stdin) >= 0) {
        char id[128];
        char type[64];
        if (!json_value(line, "id", id, sizeof(id)) || !json_value(line, "type", type, sizeof(type))) continue;
        if (session_mode) trace_line("command", type);
        if (strcmp(type, "get_state") == 0) {
            char state[PATH_MAX + 512];
            const char *reported_session_id = session_id;
            if (unreadable_state_mode) {
                char marker_path[PATH_MAX];
                snprintf(marker_path, sizeof(marker_path), "%s/.fake-pi-returned-unreadable-state", cwd);
                if (access(marker_path, F_OK) != 0) {
                    FILE *marker = fopen(marker_path, "w");
                    if (marker != NULL) fclose(marker);
                    trace_line("state-session", "unreadable");
                    printf("{\"id\":\"%s\",\"type\":\"response\",\"command\":\"%s\",\"success\":false,\"error\":\"corrupt session\"}\n", id, type);
                    fflush(stdout);
                    continue;
                }
                trace_line("state-session", "correct");
            }
            if (wrong_state_mode) {
                char marker_path[PATH_MAX];
                snprintf(marker_path, sizeof(marker_path), "%s/.fake-pi-returned-wrong-state", cwd);
                if (access(marker_path, F_OK) != 0) {
                    FILE *marker = fopen(marker_path, "w");
                    if (marker != NULL) fclose(marker);
                    reported_session_id = "00000000-0000-0000-0000-000000000000";
                    trace_line("state-session", "wrong");
                } else {
                    trace_line("state-session", "correct");
                }
            }
            if (session_mode) {
                char message_count[32];
                snprintf(message_count, sizeof(message_count), "%d", session_turn * 2);
                trace_line("state-message-count", message_count);
            }
            snprintf(
                state,
                sizeof(state),
                "{\"isStreaming\":false,\"sessionId\":\"%s\",\"messageCount\":%d,\"pendingMessageCount\":0,\"sessionFile\":\"%s/session.jsonl\"}",
                reported_session_id,
                session_turn * 2,
                session_directory
            );
            respond(id, type, state);
        } else if (strcmp(type, "get_commands") == 0) {
            respond(id, type, "{\"commands\":[{\"name\":\"skill:rich-answer-director\"},{\"name\":\"skill:professional-visualization\"},{\"name\":\"skill:deep-interaction-components\"},{\"name\":\"skill:generative-composition\"}]}");
        } else if (strcmp(type, "prompt") == 0) {
            char prompt_message[1024];
            if (json_value(line, "message", prompt_message, sizeof(prompt_message))) {
                trace_line("prompt-message", prompt_message);
            }
            respond(id, type, "{}");
            if (session_mode) {
                session_turn += 1;
                save_session_turn();
                char *context = NULL;
                read_context(&context);
                trace_line(
                    "recent",
                    context != NULL && strstr(context, "\"recentMessages\"") == NULL
                        ? "absent"
                        : "present"
                );
                free(context);
                printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"[材料：测试材料] 第 %d 次回答\"}],\"stopReason\":\"stop\"}]}\n", session_turn);
                fflush(stdout);
            } else {
                start_emitter();
            }
        } else if (strcmp(type, "abort") == 0) {
            if (cancel_mode) continue;
            stop_emitter();
            respond(id, type, "{}");
        } else {
            respond(id, type, "{}");
        }
    }
    stop_emitter();
    free(line);
    return 0;
}
"""#
