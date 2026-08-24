import Foundation

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
        var messages: [NativeModelMessage] = []
        var pendingAssistant = ""
        var pendingCalls: [NativeToolCall] = []
        for event in events {
            switch event.type {
            case .userMessage:
                if !pendingAssistant.isEmpty || !pendingCalls.isEmpty {
                    messages.append(
                        NativeModelMessage(
                            role: .assistant,
                            content: pendingAssistant,
                            toolCalls: pendingCalls.isEmpty ? nil : pendingCalls
                        )
                    )
                    pendingAssistant = ""
                    pendingCalls = []
                }
                messages.append(NativeModelMessage(role: .user, content: event.text ?? ""))
            case .assistantMessage:
                pendingAssistant += event.text ?? ""
            case .toolCall:
                if let id = event.toolCallID, let name = event.toolName {
                    pendingCalls.append(
                        NativeToolCall(id: id, name: name, arguments: event.argumentsJSON ?? "{}")
                    )
                }
            case .toolResult:
                if !pendingAssistant.isEmpty || !pendingCalls.isEmpty {
                    messages.append(
                        NativeModelMessage(
                            role: .assistant,
                            content: pendingAssistant,
                            toolCalls: pendingCalls.isEmpty ? nil : pendingCalls
                        )
                    )
                    pendingAssistant = ""
                    pendingCalls = []
                }
                messages.append(
                    NativeModelMessage(
                        role: .tool,
                        content: event.text ?? "",
                        toolCallID: event.toolCallID
                    )
                )
            case .surfaceReplace:
                if let start = event.replaceStart, let end = event.replaceEnd,
                   start >= 0, end < messages.count, start <= end {
                    let replacement = NativeModelMessage(
                        role: .assistant,
                        content: event.text ?? "[truncated]"
                    )
                    messages.replaceSubrange(start...end, with: [replacement])
                }
            case .turnStart, .turnEnd, .stepStart, .stepEnd, .assistantChunk, .closer:
                break
            }
        }
        if !pendingAssistant.isEmpty || !pendingCalls.isEmpty {
            messages.append(
                NativeModelMessage(
                    role: .assistant,
                    content: pendingAssistant,
                    toolCalls: pendingCalls.isEmpty ? nil : pendingCalls
                )
            )
        }
        return messages
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
