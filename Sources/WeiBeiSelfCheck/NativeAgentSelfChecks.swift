import Foundation
import WeiBeiCore

func runNativeAgentSelfChecks() throws {
    try checkSSEFraming()
    try checkToolCallAssembly()
    try checkIncompleteArgumentsRejected()
    try checkLedgerRoundTrip()
    try checkCrashCloser()
    try checkCredentialFile()
    try checkFailureMapping()
}

private func nativeRequire(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else {
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }
}

private func checkSSEFraming() throws {
    var framer = NativeSSEFramer()
    let split = "data: {\"id\":\"".data(using: .utf8)! + Data([0xE6]) // split UTF-8 lead
    let first = try framer.append(split)
    try nativeRequire(first.isEmpty, "incomplete UTF-8 stays buffered")
    let rest = Data([0xB1, 0x89]) + "\"}\n".data(using: .utf8)!
    let second = try framer.append(rest)
    try nativeRequire(second.count == 1 && second[0].contains("id"), "UTF-8 split SSE line reassembles")

    var crlf = NativeSSEFramer()
    let lines = try crlf.append(Data("data: {\"a\":1}\r\ndata: {\"b\":2}\n".utf8))
    try nativeRequire(lines == ["{\"a\":1}", "{\"b\":2}"], "CRLF SSE lines parse")

    var capped = NativeSSEFramer(maximumLineBytes: 16)
    do {
        _ = try capped.append(Data(repeating: 0x61, count: 32))
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "oversize SSE line should throw",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "sse_line_too_large", "oversize SSE line maps to sse_line_too_large")
    }
}

private func checkToolCallAssembly() throws {
    var assembler = NativeToolCallAssembler()
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: "weibei_course_search", argumentsDelta: "{\"query\":"))
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: nil, argumentsDelta: "\"利率\"}"))
    let calls = try assembler.completedCalls()
    try nativeRequire(calls.count == 1 && calls[0].name == "weibei_course_search", "tool call fragments assemble")
}

private func checkIncompleteArgumentsRejected() throws {
    var assembler = NativeToolCallAssembler()
    assembler.apply(.toolCallDelta(index: 0, id: "call-1", name: "weibei_course_search", argumentsDelta: "{\"query\":\"利率\""))
    do {
        _ = try assembler.completedCalls()
        throw NSError(domain: "WeiBei.NativeAgentSelfCheck", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "incomplete JSON should refuse execution",
        ])
    } catch let failure as NativeLLMFailure {
        try nativeRequire(failure.code == "incomplete_tool_arguments", "incomplete tool JSON is refused")
    }
}

private func checkLedgerRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-ledger-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let ledger = try NativeAgentLedger(fileURL: url)
    _ = try waitFor { try await ledger.append { seq, time in
        NativeSessionEvent(type: .turnStart, seq: seq, timeMS: time, turn: 1)
    } }
    _ = try waitFor { try await ledger.append { seq, time in
        NativeSessionEvent(type: .userMessage, seq: seq, timeMS: time, turn: 1, text: "利率是什么")
    } }
    _ = try waitFor { try await ledger.append { seq, time in
        NativeSessionEvent(type: .assistantMessage, seq: seq, timeMS: time, turn: 1, text: "资金的价格")
    } }
    try waitFor { try await ledger.closeTurn(turn: 1, reason: .completed) }
    let reloaded = try NativeAgentLedger(fileURL: url)
    let messages = try waitFor { await reloaded.deriveMessages() }
    try nativeRequire(messages.count == 2, "ledger round-trip keeps user and assistant")
    try nativeRequire(messages[0].content == "利率是什么", "user message survives reload")
}

private func checkCrashCloser() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-closer-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let ledger = try NativeAgentLedger(fileURL: url)
    _ = try waitFor { try await ledger.append { seq, time in
        NativeSessionEvent(type: .userMessage, seq: seq, timeMS: time, turn: 1, text: "hi")
    } }
    try waitFor { try await ledger.synthesizeCloserIfNeeded() }
    let events = try waitFor { await ledger.allEvents() }
    try nativeRequire(events.last?.type == .closer, "crash closer is synthesized")
    try nativeRequire(events.last?.timeMS == events.first?.timeMS, "closer reuses last real timestamp")
}

private func checkCredentialFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-cred-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
    }
    let store = NativeAgentCredentialStore(fileURL: url)
    try store.upsert(NativeAgentCredentialRecord(provider: "deepseek", apiKey: "sk-test"))
    try nativeRequire(try store.posixPermissions() == 0o600, "credential file is 0600")
    try Data("{".utf8).write(to: url, options: .atomic)
    let restored = try store.load()
    try nativeRequire(restored["deepseek"]?.apiKey == "sk-test", "corrupt credential file restores from backup")
}

private func checkFailureMapping() throws {
    try nativeRequire(NativeLLMFailure(code: "unauthorized", status: 401, message: "no").asAgentFailureKind == .unauthorized, "401 maps unauthorized")
    try nativeRequire(NativeLLMFailure(code: "rate_limited", status: 429, message: "slow").asAgentFailureKind == .rateLimited, "429 maps rateLimited")
    try nativeRequire(NativeLLMFailure(code: "timeout", message: "idle").asAgentFailureKind == .timedOut, "timeout maps timedOut")
    try nativeRequire(NativeLLMFailure(code: "cancelled", message: "stop").asAgentFailureKind == .cancelled, "cancel maps cancelled")
}

private func waitFor<T>(_ body: @escaping () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            box.value = .success(try await body())
        } catch {
            box.value = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    switch box.value! {
    case let .success(value): return value
    case let .failure(error): throw error
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}
