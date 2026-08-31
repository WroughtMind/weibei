import Foundation

#if DEBUG
protocol NativeContextWindowTestingAdapter: NativeLLMAdapter {
    var contextWindowForTesting: Int { get }
}
#endif

struct NativeContextCompactionCandidate: Sendable {
    var summary: String
    var firstKeptSeq: Int
    var request: NativeLLMRequest
}

enum NativeContextCompaction {
    static let maximumSummaryTokens = 8_192
    static let maximumRecentTokens = 20_000

    static let summarySystemPrompt = """
    把更早的对话压缩成一份用于继续当前会话的滚动摘要。只保留真实存在且后续仍有用的内容：正在讨论的问题、用户表现出的理解与困惑、用户给出的纠正（最新纠正优先）、已经解释或尝试过的内容及效果、尚未结束的问题，以及资料位置、名称、数字和来源。没有的内容不要写，不要虚构目标、进度、结论或下一步。输出普通文本或 Markdown，不输出 JSON。
    """

    static func summaryMessage(_ summary: String) -> NativeModelMessage {
        NativeModelMessage(
            role: .user,
            content: "此前对话的滚动摘要如下；后续原始消息和用户最新纠正优先：\n\n\(summary)"
        )
    }

    static func prepareCandidate(
        request: NativeLLMRequest,
        projection: NativeLedgerProjection,
        adapter: NativeLLMAdapter,
        contextWindow: Int
    ) async throws -> NativeContextCompactionCandidate? {
        let warningLine = contextWindow - min(16_384, contextWindow / 4)
        guard let usage = projection.latestUsage,
              usage.contextTokens + roughEstimatedTokens(projection.recordsAfterLatestUsage) > warningLine else {
            return nil
        }
        return try await makeCandidate(
            request: request,
            projection: projection,
            adapter: adapter,
            recentBudget: max(
                0,
                min(maximumRecentTokens, warningLine - maximumSummaryTokens)
            )
        )
    }

    static func prepareOverflowCandidate(
        request: NativeLLMRequest,
        projection: NativeLedgerProjection,
        adapter: NativeLLMAdapter,
        contextWindow: Int?
    ) async throws -> NativeContextCompactionCandidate? {
        let recentBudget: Int
        if let contextWindow {
            let warningLine = contextWindow - min(16_384, contextWindow / 4)
            recentBudget = max(0, min(maximumRecentTokens, warningLine - maximumSummaryTokens))
        } else {
            recentBudget = maximumRecentTokens
        }
        return try await makeCandidate(
            request: request,
            projection: projection,
            adapter: adapter,
            recentBudget: recentBudget
        )
    }

    private static func makeCandidate(
        request: NativeLLMRequest,
        projection: NativeLedgerProjection,
        adapter: NativeLLMAdapter,
        recentBudget: Int
    ) async throws -> NativeContextCompactionCandidate? {
        guard let firstKeptSeq = selectCut(
            projection: projection,
            recentBudget: recentBudget
        ) else { return nil }
        let history = projection.exitingMessages(before: firstKeptSeq)
        guard !history.isEmpty else { return nil }
        let summary = try await generateSummary(
            history: history,
            adapter: adapter,
            model: request.model
        )
        var candidate = request
        candidate.messages = request.messages.filter { $0.role == .system }
            + [summaryMessage(summary)]
            + projection.keptMessages(from: firstKeptSeq)
        return NativeContextCompactionCandidate(
            summary: summary,
            firstKeptSeq: firstKeptSeq,
            request: candidate
        )
    }

    private static func selectCut(
        projection: NativeLedgerProjection,
        recentBudget: Int
    ) -> Int? {
        func firstSafeCut(in cuts: [Int]) -> Int? {
            cuts.first { cut in
                guard projection.hasNewHistory(before: cut) else { return false }
                return roughEstimatedTokens(
                    projection.records.filter { $0.firstSeq >= cut }
                ) <= recentBudget
            }
        }

        return firstSafeCut(in: projection.turnCutSeqs)
            ?? firstSafeCut(in: projection.stepCutSeqs)
    }

    private static func generateSummary(
        history: [NativeModelMessage],
        adapter: NativeLLMAdapter,
        model: String
    ) async throws -> String {
        var messages = [NativeModelMessage(role: .system, content: summarySystemPrompt)]
        messages.append(contentsOf: history)
        messages.append(
            NativeModelMessage(
                role: .user,
                content: "请依据上面的真实对话生成新的延续摘要。"
            )
        )
        let request = NativeLLMRequest(
            model: model,
            messages: messages,
            tools: [],
            reasoningEffort: "low",
            enableNativeWebSearch: false,
            maxTokens: maximumSummaryTokens
        )
        var text = ""
        var finish: NativeFinishReason?
        for try await chunk in adapter.stream(request) {
            switch chunk {
            case let .textDelta(_, delta):
                text += delta
            case let .finish(reason, _):
                finish = reason
            default:
                break
            }
        }
        let summary = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard finish == .stop, !summary.isEmpty else {
            throw NativeLLMFailure(
                code: "context_compaction_failed",
                message: "上下文摘要未正常完成"
            )
        }
        return summary
    }

    /// Pi's single characters/4 estimate is used only for the short unmetered
    /// text tail and safe-cut selection. It never estimates the full request.
    private static func roughEstimatedTokens<S: Sequence>(_ records: S) -> Int
    where S.Element == NativeProjectedMessage {
        let characters = records.reduce(into: 0) { total, record in
            let message = record.message
            total += message.content.count
            total += message.toolCallID?.count ?? 0
            for call in message.toolCalls ?? [] {
                total += call.id.count
                total += call.name.count
                total += call.arguments.count
            }
        }
        let division = characters.quotientAndRemainder(dividingBy: 4)
        return division.quotient + (division.remainder == 0 ? 0 : 1)
    }
}
