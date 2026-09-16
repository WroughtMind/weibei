import Foundation

public enum NativeModelCallPurpose: String, Codable, Sendable {
    case answer, title, compaction
}

/// Latest snapshot per ID is the accounting record; streamed usage is cumulative.
/// A missing usage is unknown, and an interrupted snapshot is only a lower bound.
public struct NativeModelCallUsage: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case running, completed, incomplete, failed, cancelled
    }

    public var id: UUID = UUID()
    public var requestID: UUID
    public var provider: String?
    public var family: String
    public var model: String
    public var purpose: NativeModelCallPurpose
    public var contextWindow: Int?
    public var startedAt: Date = Date()
    public var updatedAt: Date = Date()
    public var state: State = .running
    public var finishReason: NativeFinishReason?
    public var usage: NativeTokenUsage?
}

/// One writer also covers detached titles from an earlier runtime instance.
private actor NativeUsageJournal {
    // ponytail: small metadata writes serialize here; shard by session if contention is measured.
    static let shared = NativeUsageJournal()

    func append(_ record: NativeModelCallUsage, to url: URL) throws {
        try NativeAgentLedger.ensureSafeParent(for: url)
        if FileManager.default.fileExists(atPath: url.path),
           try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw NativeLLMFailure(code: "unsafe_agent_directory", message: "用量记录路径不安全")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(record)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

struct NativeMeteredLLMAdapter: NativeLLMAdapter {
    var base: NativeLLMAdapter
    var providerID: String?
    var requestID: UUID
    var usageURL: URL
    var contextWindow: Int?
    var family: String { base.family }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var record = NativeModelCallUsage(
                    requestID: requestID, provider: providerID, family: family,
                    model: request.model, purpose: request.purpose, contextWindow: contextWindow
                )
                do {
                    try await NativeUsageJournal.shared.append(record, to: usageURL)
                    try Task.checkCancellation()
                    for try await chunk in base.stream(request) {
                        switch chunk {
                        case let .usage(usage):
                            record.usage = record.usage?.merging(usage) ?? usage
                            record.updatedAt = Date()
                            try await NativeUsageJournal.shared.append(record, to: usageURL)
                        case let .finish(reason, _):
                            record.finishReason = reason
                        default: break
                        }
                        try Task.checkCancellation()
                        if case .terminated = continuation.yield(chunk) { throw CancellationError() }
                    }
                    try Task.checkCancellation()
                    switch record.finishReason {
                    case .stop, .toolCalls, .length: record.state = .completed
                    case .aborted: record.state = .cancelled
                    case .error: record.state = .failed
                    case nil: record.state = .incomplete
                    }
                    record.updatedAt = Date()
                    try await NativeUsageJournal.shared.append(record, to: usageURL)
                    continuation.finish()
                } catch {
                    if let usage = (error as? NativeLLMFailure)?.usage {
                        record.usage = record.usage?.merging(usage) ?? usage
                    }
                    record.state = Task.isCancelled || error is CancellationError
                        || (error as? NativeLLMFailure)?.asAgentFailureKind == .cancelled
                        ? .cancelled : .failed
                    record.updatedAt = Date()
                    do {
                        try await NativeUsageJournal.shared.append(record, to: usageURL)
                        continuation.finish(throwing: error)
                    } catch {
                        // Do not turn a failed disk write into a successful accounting record.
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
