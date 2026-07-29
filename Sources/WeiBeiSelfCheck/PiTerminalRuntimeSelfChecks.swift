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
    private var reachedReadingContext = false

    func record(_ event: StudyAgentProgress) {
        if event == .readingContext {
            reachedReadingContext = true
        }
    }

    func waitForReadingContext() async -> Bool {
        for _ in 0..<250 {
            if reachedReadingContext { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }
}

func runPiTerminalRuntimeSelfChecks() async throws {
    let fixture = try makePiTerminalRuntimeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

    try await checkUserStopReturnsImmediately(fixture)
    try await checkTerminalErrorBypassesSlowProgress(fixture)
    try await checkGenericEventsDoNotDefeatWatchdog(fixture)
    try await checkMeaningfulThinkingKeepsRunAlive(fixture)
    try await checkRejectedRichAnswerKeepsSafeNarrative(fixture)
    try await checkRejectedActionKeepsOrdinaryAnswer(fixture)
    try await checkContextSnapshotLivesUntilProcessShutdown(fixture)
    try await checkConversationBindingLaunchContract(fixture)
    try await checkMissingSessionRecoversVisibleHistory(fixture)
    try await checkWrongSessionStateRebuildsOnlyRequestedChat(fixture)
    try await checkUnreadableStoredSessionRebuildsOnce(fixture)
    try await checkStandardProxyEnvironmentIsForwarded(fixture)
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
    guard await probe.waitForReadingContext() else {
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
        workflow: .studyCompanion,
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

private func checkContextSnapshotLivesUntilProcessShutdown(_ fixture: PiTerminalRuntimeFixture) async throws {
    let runtimeDirectory = try fixture.workingDirectory(named: "ThinkingModeContext")
    let contextURL = runtimeDirectory.appendingPathComponent("context.json")
    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: runtimeDirectory,
        runInactivityTimeoutNanoseconds: 2_000_000_000
    )
    let outcome = await terminalOutcome(runtime: runtime, revision: "thinking-test", progress: nil)

    guard outcome == "reply:[材料：测试材料] 思考完成",
          let contextData = try? Data(contentsOf: contextURL),
          let context = try? JSONSerialization.jsonObject(with: contextData) as? [String: Any],
          context["contextRevision"] as? String == "thinking-test" else {
        await runtime.shutdown()
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI context snapshot disappeared before the persistent process finished its post-turn hooks"
        )
    }

    await runtime.shutdown()
    guard !FileManager.default.fileExists(atPath: contextURL.path) else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "PI context snapshot was not removed when the persistent process shut down"
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
            recentMessages: turn == 2
                ? [
                    AgentMessage(
                        role: .assistant,
                        text: "上一轮可见回答",
                        source: nil,
                        backend: .pi
                    ),
                    AgentMessage(
                        role: .assistant,
                        text: "课程文件夹暂时不可用",
                        source: nil
                    ),
                ]
                : [],
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
    let expectedSessionDirectory = runtimeDirectory
        .appendingPathComponent("Sessions", isDirectory: true)
        .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
        .path
    let expectedSecondSessionDirectory = runtimeDirectory
        .appendingPathComponent("Sessions", isDirectory: true)
        .appendingPathComponent(secondSessionID.uuidString.lowercased(), isDirectory: true)
        .path
    let expectedWorkingDirectories = [
        projectDirectory.path,
        projectDirectory.path.hasPrefix("/private/")
            ? String(projectDirectory.path.dropFirst("/private".count))
            : "/private\(projectDirectory.path)",
    ]
    guard trace.components(separatedBy: "launch\n").count - 1 == 3,
          expectedWorkingDirectories.contains(where: { trace.contains("cwd=\($0)\n") }),
          trace.components(
              separatedBy: "arg=--session-id\narg=\(sessionID.uuidString.lowercased())\n"
          ).count - 1 == 2,
          trace.contains("arg=--session-id\narg=\(secondSessionID.uuidString.lowercased())\n"),
          trace.contains("arg=--session-dir\narg=\(expectedSessionDirectory)\n"),
          trace.contains("arg=--session-dir\narg=\(expectedSecondSessionDirectory)\n"),
          trace.components(
              separatedBy: "arg=--provider\narg=openai-codex\n"
          ).count - 1 == 3,
          trace.components(
              separatedBy: "arg=--model\narg=\(AgentModelListService.codexDefaultModel)\n"
          ).count - 1 == 3,
          !trace.contains("arg=--no-session\n"),
          !trace.contains("command=new_session\n"),
          trace.components(separatedBy: "command=prompt\n").count - 1 == 4,
          trace.components(separatedBy: "recent=empty\n").count - 1 == 4 else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "Chat 复用、切换隔离或原生历史合同不成立：\n\(trace)"
        )
    }
}

private func checkMissingSessionRecoversVisibleHistory(
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
    let visibleHistory = [
        AgentMessage(role: .user, text: "此前问题", source: nil),
        AgentMessage(
            role: .assistant,
            text: "[材料：测试材料] 此前回答",
            source: nil,
            backend: .pi
        ),
    ]
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "继续此前对话",
        materialTitle: "测试材料",
        materialText: "测试正文",
        noteTitle: "测试笔记",
        noteText: "",
        recentMessages: visibleHistory,
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
          trace.contains("recent=present\n") else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "Pi 会话缺失时没有只在恢复轮注入 App 可见历史：\n\(trace)"
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
    let visibleHistory = [
        AgentMessage(role: .user, text: "此前问题", source: nil),
        AgentMessage(role: .assistant, text: "此前回答", source: nil, backend: .pi),
    ]
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "从损坏会话继续",
        materialTitle: "测试材料",
        materialText: "测试正文",
        noteTitle: "测试笔记",
        noteText: "",
        recentMessages: visibleHistory,
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
          trace.contains("recent=present\n"),
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
        recentMessages: [
            AgentMessage(role: .user, text: "此前问题", source: nil),
            AgentMessage(role: .assistant, text: "此前回答", source: nil, backend: .pi),
        ],
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
          trace.contains("recent=present\n") else {
        throw PiTerminalRuntimeSelfCheckError.failed(
            "已有 Pi 会话无法读取时没有只重建一次并恢复可见历史：\n\(trace)"
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
static int session_mode = 0;
static int wrong_state_mode = 0;
static int unreadable_state_mode = 0;
static int session_turn = 0;
static char session_id[128] = "";
static char session_directory[PATH_MAX] = "";
static char trace_path[PATH_MAX] = "";

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
    _exit(0);
}

static void emit_context(const char *revision) {
    printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"ctx\",\"toolName\":\"weibei_context\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"weibei_context\",\"contextRevision\":\"%s\"}}}\n", revision);
    fflush(stdout);
}

static void start_emitter(void) {
    if (emitter_pid > 0) return;
    char cwd[PATH_MAX];
    getcwd(cwd, sizeof(cwd));
    cancel_mode = strstr(cwd, "CancelMode") != NULL;
    int error_mode = strstr(cwd, "ErrorMode") != NULL;
    int thinking_mode = strstr(cwd, "ThinkingMode") != NULL;
    int rich_fallback_mode = strstr(cwd, "RichFallbackMode") != NULL;
    int direct_answer_mode = strstr(cwd, "DirectAnswerMode") != NULL;
    emitter_pid = fork();
    if (emitter_pid != 0) return;

    if (error_mode) {
        emit_context("error-test");
        for (int index = 0; index < 256; index++) {
            printf("{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"临时文本\"}}\n");
        }
        printf("{\"type\":\"message_end\",\"message\":{\"role\":\"assistant\",\"stopReason\":\"error\",\"errorMessage\":\"真实终止错误\"}}\n");
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[],\"stopReason\":\"error\",\"diagnostics\":[{\"error\":{\"message\":\"真实终止错误\"}}]}]}\n");
        fflush(stdout);
        _exit(0);
    }

    if (thinking_mode) {
        emit_context("thinking-test");
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
        emit_context("rich-fallback-test");
        printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"rich-fallback\",\"toolName\":\"weibei_rich_answer\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"rich_answer\",\"contextRevision\":\"rich-fallback-test\",\"envelope\":{\"schemaVersion\":2,\"contextRevision\":\"rich-fallback-test\",\"narrative\":\"[材料：测试材料] 应保留的正文\",\"expressionPlan\":{\"action\":\"explain\",\"summary\":\"安全降级\",\"families\":[\"textAndAlignment\"],\"preferredSurface\":\"inline\",\"directManipulation\":false},\"scenes\":[{\"id\":\"rejected-scene\",\"title\":\"无效场景\",\"family\":\"textAndAlignment\",\"objects\":[],\"evidenceIDs\":[\"missing-evidence\"]}],\"evidenceLedger\":[],\"fallback\":{\"text\":\"[材料：测试材料] 安全正文\",\"reason\":\"场景被拒绝\"}}}}}\n");
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"模型收尾文字\"}],\"stopReason\":\"stop\"}]}\n");
        fflush(stdout);
        _exit(0);
    }

    if (direct_answer_mode) {
        printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"invalid-note\",\"toolName\":\"weibei_note_proposal\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"note_proposal\",\"markdown\":\"不应写入\",\"evidence\":[],\"contextRevision\":\"stale-revision\"}}}\n");
        printf("{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"普通回答没有来源也能显示。\"}}\n");
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"普通回答没有来源也能显示。\"}],\"stopReason\":\"stop\"}]}\n");
        fflush(stdout);
        _exit(0);
    }

    emit_context(cancel_mode ? "cancel-test" : "heartbeat-test");
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
            respond(id, type, "{\"commands\":[{\"name\":\"skill:weibei-study-companion\"},{\"name\":\"skill:weibei-course-wayfinding\"},{\"name\":\"skill:weibei-close-reading\"},{\"name\":\"skill:weibei-note-making\"},{\"name\":\"skill:weibei-recall-practice\"},{\"name\":\"skill:rich-answer-director\"},{\"name\":\"skill:professional-visualization\"},{\"name\":\"skill:deep-interaction-components\"},{\"name\":\"skill:generative-composition\"},{\"name\":\"skill:weibei-interactive-study\"}]}");
        } else if (strcmp(type, "prompt") == 0) {
            respond(id, type, "{}");
            if (session_mode) {
                session_turn += 1;
                char revision[64];
                char *context = NULL;
                if (!read_context(&context)
                    || !json_value(context, "contextRevision", revision, sizeof(revision))) {
                    snprintf(revision, sizeof(revision), "missing-revision");
                }
                trace_line(
                    "recent",
                    context != NULL && strstr(context, "\"recentMessages\":[]") == NULL
                        ? "present"
                        : "empty"
                );
                free(context);
                emit_context(revision);
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
