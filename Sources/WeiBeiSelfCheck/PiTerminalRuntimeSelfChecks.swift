import CryptoKit
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

    try Data(#"{"version":"0.80.2"}"#.utf8)
        .write(to: binURL.appendingPathComponent("package.json"), options: .atomic)
    try Data("{}\n".utf8).write(to: themeURL.appendingPathComponent("dark.json"), options: .atomic)
    try Data("{}\n".utf8).write(to: themeURL.appendingPathComponent("light.json"), options: .atomic)
    try Data("MIT\n".utf8).write(to: runtimeURL.appendingPathComponent("LICENSE"), options: .atomic)
    try Data("Self-check fixture only.\n".utf8)
        .write(to: runtimeURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"), options: .atomic)
    let manifest = #"{"schemaVersion":1,"piVersion":"0.80.2","sourceRepository":"self-check","sourceCommit":"0000000000000000000000000000000000000000","license":"MIT"}"#
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

    emit_context(cancel_mode ? "cancel-test" : "heartbeat-test");
    for (;;) {
        printf("{\"type\":\"future_event\"}\n");
        fflush(stdout);
        usleep(20000);
    }
}

int main(void) {
    signal(SIGTERM, terminate_fixture);
    setvbuf(stdout, NULL, _IOLBF, 0);
    char *line = NULL;
    size_t line_capacity = 0;
    while (getline(&line, &line_capacity, stdin) >= 0) {
        char id[128];
        char type[64];
        if (!json_value(line, "id", id, sizeof(id)) || !json_value(line, "type", type, sizeof(type))) continue;
        if (strcmp(type, "get_state") == 0) {
            respond(id, type, "{\"isStreaming\":false}");
        } else if (strcmp(type, "get_commands") == 0) {
            respond(id, type, "{\"commands\":[{\"name\":\"skill:weibei-study-companion\"},{\"name\":\"skill:weibei-course-wayfinding\"},{\"name\":\"skill:weibei-close-reading\"},{\"name\":\"skill:weibei-note-making\"},{\"name\":\"skill:weibei-recall-practice\"},{\"name\":\"skill:weibei-interactive-study\"}]}");
        } else if (strcmp(type, "prompt") == 0) {
            respond(id, type, "{}");
            start_emitter();
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
