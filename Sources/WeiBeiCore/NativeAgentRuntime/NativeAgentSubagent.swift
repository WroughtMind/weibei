import Foundation

public struct NativeSubagentCapabilities: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let parentContext = NativeSubagentCapabilities(rawValue: 1 << 0)
    public static let hostTools = NativeSubagentCapabilities(rawValue: 1 << 1)
    public static let documents = NativeSubagentCapabilities(rawValue: 1 << 2)
    public static let nestedDelegate = NativeSubagentCapabilities(rawValue: 1 << 3)
    public static let supported: NativeSubagentCapabilities = [.parentContext, .hostTools, .documents]

    public static func parse(_ names: [String]) -> NativeSubagentCapabilities {
        var value = NativeSubagentCapabilities()
        for name in names {
            switch name {
            case "parentContext": value.insert(.parentContext)
            case "hostTools": value.insert(.hostTools)
            case "documents": value.insert(.documents)
            case "nestedDelegate": value.insert(.nestedDelegate)
            default: break
            }
        }
        return value
    }
}

public struct NativeSubagentRequest: Sendable {
    public var task: String
    public var capabilities: NativeSubagentCapabilities
    public var depth: Int

    public init(task: String, capabilities: NativeSubagentCapabilities, depth: Int) {
        self.task = task
        self.capabilities = capabilities
        self.depth = depth
    }
}

public struct NativeSubagentResult: Sendable {
    public var ok: Bool
    public var text: String
    public var partial: Bool
    public var toolTrace: [String]

    public init(ok: Bool, text: String, partial: Bool, toolTrace: [String]) {
        self.ok = ok
        self.text = text
        self.partial = partial
        self.toolTrace = toolTrace
    }
}

public enum NativeSubagentRunner {
    public static let maximumDepth = 2

    public static func start(
        _ request: NativeSubagentRequest,
        adapter: NativeLLMAdapter,
        model: String,
        contextWindow: Int? = nil,
        systemPrompt: String,
        ledgerRoot: URL,
        hostToolHandler: StudyAgentHostToolHandler?,
        liveStores: NativeLiveStores
    ) async -> NativeSubagentResult {
        if !NativeSubagentCapabilities.supported.contains(request.capabilities) {
            return NativeSubagentResult(
                ok: false,
                text: "子智能体请求了不受支持的能力，未静默降级。",
                partial: false,
                toolTrace: []
            )
        }
        if request.depth > maximumDepth {
            return NativeSubagentResult(
                ok: false,
                text: "子智能体深度超过 \(maximumDepth)，已拒绝。",
                partial: false,
                toolTrace: []
            )
        }
        let childRoot = ledgerRoot.appendingPathComponent("subagents/\(UUID().uuidString.lowercased())", isDirectory: true)
        let runtime = NativeStudyAgentRuntime(
            model: model,
            adapter: adapter,
            contextWindow: contextWindow,
            ledgerRoot: childRoot,
            systemPromptText: systemPrompt,
            hostToolHandler: request.capabilities.contains(.hostTools) ? hostToolHandler : nil,
            liveStores: liveStores,
            mode: .tutor,
            delegateDepth: request.depth
        )
        let question: String
        if request.capabilities.contains(.parentContext) {
            question = request.task
        } else {
            question = "不要使用父会话未授权的上下文。任务：\(request.task)"
        }
        do {
            let reply = try await runtime.respond(
                to: StudyAgentRequest(
                    purpose: .conversation,
                    question: question,
                    materialTitle: "",
                    materialText: "",
                    noteTitle: "",
                    noteText: "",
                    contextRevision: "delegate-\(request.depth)"
                ),
                progress: nil
            )
            let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return NativeSubagentResult(
                ok: true,
                text: text.isEmpty ? "(子智能体无文字输出，但已结束)" : text,
                partial: false,
                toolTrace: reply.toolTrace
            )
        } catch {
            return NativeSubagentResult(
                ok: false,
                text: "子智能体失败：\(error.localizedDescription)",
                partial: true,
                toolTrace: []
            )
        }
    }
}
