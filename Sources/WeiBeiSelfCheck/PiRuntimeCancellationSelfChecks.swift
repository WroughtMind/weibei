import CryptoKit
import Foundation
import WeiBeiCore

private struct FakePiRuntimeFixture {
    var rootURL: URL
    var executableURL: URL
    var workingDirectoryURL: URL
    var progressWorkingDirectoryURL: URL
}

private enum PiRuntimeCancellationSelfCheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

func checkPiRunCancellationControl() async throws {
    let fixture = try makeNeverEndingPiRuntime()
    defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

    let runtime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: fixture.workingDirectoryURL
    )
    let request = StudyAgentRequest(
        purpose: .conversation,
        question: "你叫什么？",
        materialTitle: "空材料",
        materialText: "",
        noteTitle: "空笔记",
        noteText: "",
        contextRevision: "stall-test"
    )

    let stalledRun = Task { await runOutcome(runtime: runtime, request: request) }
    try? await Task.sleep(nanoseconds: 400_000_000)
    await runtime.cancel()
    let outcome = await stalledRun.value
    await runtime.shutdown()

    guard outcome.contains("PI 请求已取消") else {
        throw PiRuntimeCancellationSelfCheckError.failed(
            "PI run did not remain user-cancellable while receiving non-terminal events (\(outcome))"
        )
    }

    let progressRuntime = PiAgentRuntime(
        executableURL: fixture.executableURL,
        runtimeDirectory: fixture.progressWorkingDirectoryURL
    )
    let progressRequest = StudyAgentRequest(
        purpose: .conversation,
        question: "你叫什么？",
        materialTitle: "空材料",
        materialText: "",
        noteTitle: "空笔记",
        noteText: "",
        contextRevision: "progress-test"
    )
    let progressOutcome = await runOutcome(runtime: progressRuntime, request: progressRequest)
    await progressRuntime.shutdown()
    guard progressOutcome == "reply:我叫魏碑" else {
        throw PiRuntimeCancellationSelfCheckError.failed(
            "PI run did not complete after a long sequence of non-terminal progress events (\(progressOutcome))"
        )
    }
}

private func runOutcome(runtime: PiAgentRuntime, request: StudyAgentRequest) async -> String {
    do {
        let reply = try await runtime.respond(to: request, progress: nil)
        return "reply:\(reply.text)"
    } catch {
        return "runtime-error:\(error.localizedDescription)"
    }
}

private func makeNeverEndingPiRuntime() throws -> FakePiRuntimeFixture {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("weibei-pi-cancellation-\(UUID().uuidString)", isDirectory: true)
    let runtimeURL = rootURL.appendingPathComponent("PiRuntime", isDirectory: true)
    let binURL = runtimeURL.appendingPathComponent("bin", isDirectory: true)
    let themeURL = binURL.appendingPathComponent("theme", isDirectory: true)
    let executableURL = binURL.appendingPathComponent("pi")
    let sourceURL = rootURL.appendingPathComponent("fake-pi.c")
    let workingDirectoryURL = rootURL.appendingPathComponent("Working", isDirectory: true)
    let progressWorkingDirectoryURL = rootURL.appendingPathComponent("MeaningfulProgress", isDirectory: true)

    try fileManager.createDirectory(at: themeURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: progressWorkingDirectoryURL, withIntermediateDirectories: true)
    try Data(fakePiSource.utf8).write(to: sourceURL, options: .atomic)
    try runFixtureCommand(
        executableURL: URL(fileURLWithPath: "/usr/bin/clang"),
        arguments: [sourceURL.path, "-O0", "-o", executableURL.path]
    )
    try runFixtureCommand(
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

    return FakePiRuntimeFixture(
        rootURL: rootURL,
        executableURL: executableURL,
        workingDirectoryURL: workingDirectoryURL,
        progressWorkingDirectoryURL: progressWorkingDirectoryURL
    )
}

private func runFixtureCommand(executableURL: URL, arguments: [String]) throws {
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
        throw PiRuntimeCancellationSelfCheckError.failed(
            "fixture command failed: \(executableURL.lastPathComponent) \(detail)"
        )
    }
}

private let fakePiSource = #"""
#include <signal.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static pid_t emitter_pid = -1;

static int json_value(const char *line, const char *key, char *output, size_t capacity) {
    char pattern[64];
    snprintf(pattern, sizeof(pattern), "\"%s\":\"", key);
    const char *start = strstr(line, pattern);
    if (start == NULL) return 0;
    start += strlen(pattern);
    const char *end = strchr(start, '"');
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

static void start_emitter(void) {
    if (emitter_pid > 0) return;
    char working_directory[PATH_MAX];
    int progress_mode = getcwd(working_directory, sizeof(working_directory)) != NULL
        && strstr(working_directory, "MeaningfulProgress") != NULL;
    emitter_pid = fork();
    if (emitter_pid != 0) return;
    const char *revision = progress_mode ? "progress-test" : "stall-test";
    printf("{\"type\":\"tool_execution_end\",\"toolCallId\":\"ctx\",\"toolName\":\"weibei_context\",\"isError\":false,\"result\":{\"details\":{\"kind\":\"weibei_context\",\"contextRevision\":\"%s\"}}}\n", revision);
    fflush(stdout);
    if (progress_mode) {
        for (int index = 0; index < 12; index++) {
            printf("{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"thinking_delta\"}}\n");
            fflush(stdout);
            usleep(50000);
        }
        printf("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"我叫魏碑\"}],\"stopReason\":\"stop\"}]}\n");
        fflush(stdout);
        _exit(0);
    }
    for (;;) {
        printf("{\"type\":\"future_event\"}\n");
        fflush(stdout);
        usleep(50000);
    }
}

static void stop_emitter(void) {
    if (emitter_pid <= 0) return;
    kill(emitter_pid, SIGTERM);
    waitpid(emitter_pid, NULL, 0);
    emitter_pid = -1;
}

int main(void) {
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
