import Foundation

struct NativeProjectedMessage: Sendable {
    var message: NativeModelMessage
    var firstSeq: Int
    var lastSeq: Int
    var usage: NativeTokenUsage?
}

struct NativeLedgerProjection: Sendable {
    var summaryMessage: NativeModelMessage?
    var records: [NativeProjectedMessage]
    var turnCutSeqs: [Int]
    var stepCutSeqs: [Int]

    var messages: [NativeModelMessage] {
        (summaryMessage.map { [$0] } ?? []) + records.map(\.message)
    }

    var latestUsageRecordIndex: Int? {
        records.lastIndex { ($0.usage?.contextTokens ?? 0) > 0 }
    }

    var latestUsage: NativeTokenUsage? {
        latestUsageRecordIndex.flatMap { records[$0].usage }
    }

    var recordsAfterLatestUsage: ArraySlice<NativeProjectedMessage> {
        guard let latestUsageRecordIndex else { return records[...] }
        return records.suffix(from: records.index(after: latestUsageRecordIndex))
    }

    func exitingMessages(before firstKeptSeq: Int) -> [NativeModelMessage] {
        (summaryMessage.map { [$0] } ?? [])
            + records.filter { $0.lastSeq < firstKeptSeq }.map(\.message)
    }

    func keptMessages(from firstKeptSeq: Int) -> [NativeModelMessage] {
        records.filter { $0.firstSeq >= firstKeptSeq }.map(\.message)
    }

    func hasNewHistory(before firstKeptSeq: Int) -> Bool {
        records.contains { $0.lastSeq < firstKeptSeq }
    }
}

/// Append-only JSONL session ledger. Model-visible history is a projection.
public actor NativeAgentLedger {
    public let fileURL: URL
    private var events: [NativeSessionEvent] = []
    private var nextSeq = 1
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        try Self.ensureSafeParent(for: fileURL)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if !data.isEmpty {
                var loaded: [NativeSessionEvent] = []
                var offset = data.startIndex
                while offset < data.endIndex {
                    let slice: Data
                    if let newline = data[offset...].firstIndex(of: 0x0A) {
                        slice = data[offset..<newline]
                        offset = data.index(after: newline)
                    } else {
                        slice = data[offset...]
                        offset = data.endIndex
                    }
                    if slice.isEmpty { continue }
                    loaded.append(try decoder.decode(NativeSessionEvent.self, from: slice))
                }
                events = loaded
                nextSeq = (loaded.map(\.seq).max() ?? 0) + 1
            }
        }
    }

    private static func ensureSafeParent(for fileURL: URL) throws {
        let sessionDirectory = fileURL.deletingLastPathComponent()
        let ledgerRoot = sessionDirectory.deletingLastPathComponent()
        let workspaceRoot = ledgerRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        do {
            try WeiBeiAgentDataPaths.ensureOwnedDirectory(
                sessionDirectory,
                inside: workspaceRoot
            )
        } catch WeiBeiAgentDataPathError.outsideWorkspace {
            WeiBeiLog.workspace.error(
                "code=unsafe_agent_ledger_directory"
            )
            throw NativeLLMFailure(
                code: "unsafe_agent_directory",
                message: "Agent 本地目录不安全，未写入运行记录"
            )
        }
    }

    public func append(_ builder: (Int, Int64) -> NativeSessionEvent) throws -> NativeSessionEvent {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let event = builder(nextSeq, now)
        events.append(event)
        nextSeq += 1
        var line = try encoder.encode(event)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: Data.WritingOptions.atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        }
        return event
    }

    public func allEvents() -> [NativeSessionEvent] {
        events
    }

    public func deriveMessages() -> [NativeModelMessage] {
        deriveProjection().messages
    }

    func deriveProjection() -> NativeLedgerProjection {
        let checkpoint = events.last { $0.type == .contextCompaction }
        let firstVisibleSeq = checkpoint?.firstKeptSeq ?? Int.min
        let visibleEvents = events.filter {
            $0.type != .contextCompaction && $0.seq >= firstVisibleSeq
        }
        var records: [NativeProjectedMessage] = []
        var pendingAssistant = ""
        var pendingCalls: [NativeToolCall] = []
        var pendingFirstSeq: Int?
        var pendingLastSeq: Int?
        var pendingUsage: NativeTokenUsage?

        func flushAssistant() {
            guard !pendingAssistant.isEmpty || !pendingCalls.isEmpty || pendingUsage != nil,
                  let firstSeq = pendingFirstSeq,
                  let lastSeq = pendingLastSeq else { return }
            records.append(
                NativeProjectedMessage(
                    message: NativeModelMessage(
                        role: .assistant,
                        content: pendingAssistant,
                        toolCalls: pendingCalls.isEmpty ? nil : pendingCalls
                    ),
                    firstSeq: firstSeq,
                    lastSeq: lastSeq,
                    usage: pendingUsage
                )
            )
            pendingAssistant = ""
            pendingCalls = []
            pendingFirstSeq = nil
            pendingLastSeq = nil
            pendingUsage = nil
        }

        for event in visibleEvents {
            switch event.type {
            case .userMessage:
                flushAssistant()
                records.append(
                    NativeProjectedMessage(
                        message: NativeModelMessage(role: .user, content: event.text ?? ""),
                        firstSeq: event.seq,
                        lastSeq: event.seq,
                        usage: nil
                    )
                )
            case .assistantMessage:
                pendingFirstSeq = pendingFirstSeq ?? event.seq
                pendingLastSeq = event.seq
                pendingAssistant += event.text ?? ""
                if let usage = event.usage,
                   checkpoint.map({ event.seq > $0.seq }) ?? true {
                    pendingUsage = pendingUsage?.merging(usage) ?? usage
                }
            case .toolCall:
                if let id = event.toolCallID, let name = event.toolName {
                    pendingFirstSeq = pendingFirstSeq ?? event.seq
                    pendingLastSeq = event.seq
                    pendingCalls.append(
                        NativeToolCall(id: id, name: name, arguments: event.argumentsJSON ?? "{}")
                    )
                }
            case .toolResult:
                flushAssistant()
                records.append(
                    NativeProjectedMessage(
                        message: NativeModelMessage(
                            role: .tool,
                            content: event.text ?? "",
                            toolCallID: event.toolCallID,
                            images: event.imagePart.map { [$0] } ?? []
                        ),
                        firstSeq: event.seq,
                        lastSeq: event.seq,
                        usage: nil
                    )
                )
            case .turnStart, .turnEnd, .stepStart, .stepEnd, .assistantChunk,
                 .contextCompaction, .closer:
                break
            }
        }
        flushAssistant()

        let summaryMessage: NativeModelMessage?
        if let summary = checkpoint?.summary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaryMessage = NativeContextCompaction.summaryMessage(summary)
        } else {
            summaryMessage = nil
        }
        let nextSeqAfterCheckpoint = nextSeq + 1
        func cut(after event: NativeSessionEvent) -> Int {
            visibleEvents.first { $0.seq > event.seq }?.seq ?? nextSeqAfterCheckpoint
        }
        let turnCuts = visibleEvents
            .filter { $0.type == .turnEnd }
            .map(cut)
        let stepCuts = visibleEvents
            .filter { $0.type == .stepEnd }
            .map(cut)
        return NativeLedgerProjection(
            summaryMessage: summaryMessage,
            records: records,
            turnCutSeqs: Array(Set(turnCuts)).sorted(),
            stepCutSeqs: Array(Set(stepCuts)).sorted()
        )
    }

    public func closeTurn(turn: Int, reason: NativeTurnEndReason) throws {
        if events.last?.type != .turnEnd {
            _ = try append { seq, time in
                NativeSessionEvent(
                    type: .turnEnd,
                    seq: seq,
                    timeMS: time,
                    turn: turn,
                    finishReason: reason
                )
            }
        }
    }

    /// Crash recovery: synthesize a closer using the last real timestamp.
    public func synthesizeCloserIfNeeded() throws {
        guard let last = events.last, last.type != .closer, last.type != .turnEnd else { return }
        let time = last.timeMS
        let event = NativeSessionEvent(
            type: .closer,
            seq: nextSeq,
            timeMS: time,
            text: "synthesized closer",
            finishReason: .error
        )
        events.append(event)
        nextSeq += 1
        var line = try encoder.encode(event)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: Data.WritingOptions.atomic)
        }
    }

    /// Fork = completed-turn prefix snapshot.
    public func forkPrefix(upToTurn turn: Int, to url: URL) throws -> NativeAgentLedger {
        let prefix = events.filter { event in
            guard let eventTurn = event.turn else { return event.type == .closer }
            return eventTurn <= turn && event.type != .turnStart || eventTurn < turn
                ? true
                : eventTurn <= turn && event.type == .turnEnd
        }
        try Self.ensureSafeParent(for: url)
        var data = Data()
        for event in events where (event.turn ?? 0) <= turn {
            if event.type == .turnStart, event.turn == turn { break }
            var line = try encoder.encode(event)
            line.append(0x0A)
            data.append(line)
        }
        _ = prefix
        try data.write(to: url, options: Data.WritingOptions.atomic)
        return try NativeAgentLedger(fileURL: url)
    }
}
