import Foundation

/// SSE framer: CRLF, UTF-8 split code units, oversize-line cap.
public struct NativeSSEFramer: Sendable {
    public var maximumLineBytes: Int
    private var buffer = Data()

    public init(maximumLineBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumLineBytes = maximumLineBytes
    }

    public mutating func append(_ data: Data) throws -> [String] {
        buffer.append(data)
        if buffer.count > maximumLineBytes && !buffer.contains(0x0A) {
            throw NativeLLMFailure(code: "sse_line_too_large", message: "SSE line exceeded the size limit")
        }
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            if line.count > maximumLineBytes {
                throw NativeLLMFailure(code: "sse_line_too_large", message: "SSE line exceeded the size limit")
            }
            if line.isEmpty { continue }
            guard let text = String(data: line, encoding: .utf8) else {
                // Incomplete UTF-8 code unit: push back and wait.
                buffer.insert(contentsOf: line + Data([0x0A]), at: 0)
                break
            }
            if text.hasPrefix("data:") {
                let payload = text.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { continue }
                lines.append(payload)
            }
        }
        if buffer.count > maximumLineBytes {
            throw NativeLLMFailure(code: "sse_line_too_large", message: "SSE line exceeded the size limit")
        }
        return lines
    }

    public mutating func finish() throws -> [String] {
        if buffer.isEmpty { return [] }
        let leftover = buffer
        buffer.removeAll()
        guard let text = String(data: leftover, encoding: .utf8) else {
            throw NativeLLMFailure(code: "sse_incomplete", message: "SSE ended on a split UTF-8 sequence")
        }
        if text.hasPrefix("data:") {
            let payload = text.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload != "[DONE]" { return [payload] }
        }
        return []
    }
}

/// Assembles streamed tool-call argument fragments. Incomplete JSON is refused.
public struct NativeToolCallAssembler: Sendable {
    private var calls: [Int: NativeToolCall] = [:]
    private var buffers: [Int: String] = [:]

    public init() {}

    public mutating func apply(_ chunk: NativeStreamChunk) {
        switch chunk {
        case let .toolCallDelta(index, id, name, argumentsDelta):
            var current = calls[index] ?? NativeToolCall(id: id, name: name ?? "", arguments: "")
            if let name, !name.isEmpty { current.name = name }
            if current.id.isEmpty { current.id = id }
            buffers[index, default: ""] += argumentsDelta
            current.arguments = buffers[index] ?? ""
            calls[index] = current
        case let .blockEnd(_, .toolCall(id, name, arguments)):
            if let index = calls.first(where: { $0.value.id == id })?.key {
                calls[index] = NativeToolCall(id: id, name: name, arguments: arguments)
            }
        default:
            break
        }
    }

    public func callResults() -> [(call: NativeToolCall, failure: NativeLLMFailure?)] {
        calls.keys.sorted().compactMap { index -> (call: NativeToolCall, failure: NativeLLMFailure?)? in
            guard var call = calls[index] else { return nil }
            let raw = buffers[index] ?? call.arguments
            call.arguments = raw
            guard NativeToolCallAssembler.isCompleteJSONObject(raw) else {
                return (
                    call,
                    NativeLLMFailure(
                        code: "incomplete_tool_arguments",
                        message: "refusing to execute a tool call with incomplete JSON arguments"
                    )
                )
            }
            return (call, nil)
        }
    }

    public func completedCalls() throws -> [NativeToolCall] {
        try callResults().map { result in
            if let failure = result.failure { throw failure }
            return result.call
        }
    }

    public static func isCompleteJSONObject(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return object is [String: Any]
    }
}
