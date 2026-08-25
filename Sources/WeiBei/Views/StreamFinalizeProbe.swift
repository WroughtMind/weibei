import Foundation
import SwiftUI
import WeiBeiCore

/// TEMPORARY diagnostics for the streaming-completion flash/shift investigation.
/// Enabled with WEIBEI_STREAM_PROBE=1. Logs go to stderr with uptime ms.
/// REMOVE before shipping.
enum StreamFinalizeProbe {
    static let enabled = ProcessInfo.processInfo.environment["WEIBEI_STREAM_PROBE"] == "1"
    private static let t0 = DispatchTime.now().uptimeNanoseconds

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000
        fputs("[STREAM-PROBE] \(String(format: "%9.1f", ms))ms \(message())\n", stderr)
        fflush(stderr)
    }
}

/// TEMPORARY: row frame probe for the streaming-completion investigation.
struct StreamFinalizeProbeFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Headless reproduction harness (TEMPORARY)

/// Hosts the REAL AgentPaneView with a scratch WorkspaceStore and drives the
/// exact streaming-completion sequence the native runtime produces, while the
/// probe logs every height/position transition. Enabled with
/// WEIBEI_STREAM_PROBE_SCENARIO=<name>.
struct StreamFinalizeHarnessView: View {
    // Scratch store in a temp dir — never touch the real workspace on disk.
    @StateObject private var store = WorkspaceStore(
        workspaceDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiStreamProbe-\(UUID().uuidString)", isDirectory: true),
        startsAtBlankEntries: true,
        startsCourseFileMaintenance: false
    )
    @State private var started = false

    var body: some View {
        AgentPaneView(showsPaneHeader: false)
            .environmentObject(store)
            .environmentObject(store.paneState)
            .environmentObject(store.interaction)
            .frame(width: 420, height: 720)
            .onAppear {
                guard !started else { return }
                started = true
                Task { @MainActor in
                    await runScenario()
                }
            }
    }

    @MainActor
    private func runScenario() async {
        let scenario = ProcessInfo.processInfo.environment["WEIBEI_STREAM_PROBE_SCENARIO"] ?? "plain"
        StreamFinalizeProbe.log("HARNESS scenario=\(scenario)")
        // Let the window settle and the chat surface mount before streaming.
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        guard let session = store.createStudySession(courseID: nil) else {
            StreamFinalizeProbe.log("HARNESS no session")
            return
        }
        let chatID = session.id
        store.appendAgentMessage(AgentMessage(role: .user, text: "测试问题", source: nil))

        let answer = Self.answer(for: scenario)
        let requestID = UUID()
        let reply = AgentMessage(
            role: .assistant,
            text: "",
            source: nil,
            backend: .native,
            completionState: .generating,
            origin: AgentReplyOrigin(requestID: requestID, chatID: chatID, courseID: nil),
            retryQuestion: "测试问题"
        )
        let replyID = reply.id
        store.appendAgentMessage(reply)
        // Mirror performAgentRequest's running-state lifecycle exactly.
        store.isAskingAgent = true
        store.activeAgentRequestID = requestID
        store.activeAgentReplyMessageID = replyID
        store.activeAgentReplyChatID = chatID
        store.agentStreaming.begin(messageID: replyID, chatID: chatID)
        StreamFinalizeProbe.log("HARNESS streaming begin")

        // Wait for the row's WKWebView to boot before pushing text (the real
        // app has network latency covering this).
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Feed the answer through the REAL display pump at the real cadence:
        // cumulative snapshots, one per progress event (~30Hz from the runtime).
        var shown = 0
        var tick = 0
        while shown < answer.count {
            shown = min(answer.count, shown + 12)
            let cumulative = String(answer.prefix(shown))
            store.latestAgentStreamingText = cumulative
            store.agentStreamingDisplayPump.enqueue(cumulativeText: cumulative)
            tick += 1
            if tick % 5 == 1 {
                StreamFinalizeProbe.log("HARNESS tick=\(tick) shown=\(shown)/\(answer.count) streamingText=\(store.agentStreaming.text.count) pumpPending=\(store.agentStreamingDisplayPump.pendingCharacterCount)")
            }
            try? await Task.sleep(nanoseconds: 99_000_000)
        }
        StreamFinalizeProbe.log("HARNESS feed loop complete")

        // Network completion: persist the final reply exactly like
        // performAgentRequest does, then finish the pump, then the defer
        // clears the running state while the pump keeps typing.
        StreamFinalizeProbe.log("HARNESS network-complete (persist + finish pump)")
        store.latestAgentStreamingText = answer
        _ = store.updateAgentMessage(replyID, in: chatID) {
            $0.text = answer
            $0.completionState = .completed
            $0.sources = Self.sources(for: scenario)
        }
        store.agentStreamingDisplayPump.finish(cumulativeText: answer)
        store.activeAgentRequestID = nil
        store.activeAgentReplyMessageID = nil
        store.activeAgentReplyChatID = nil
        store.isAskingAgent = false
        store.agentStreaming.activityText = nil

        // Keep the window alive so late height reports / finalize land.
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        StreamFinalizeProbe.log("HARNESS done")
    }

    private static func answer(for scenario: String) -> String {
        switch scenario {
        case "long":
            return """
            魏碑体是中国书法史上承前启后的重要书体，主要从北魏时期的碑刻、造像记、墓志铭中发展而来。下面从几个维度详细说明：

            ## 一、笔法特征

            1. **方笔为主**：起笔、收笔多见方切，棱角分明，如刀削斧劈；
            2. **中锋铺毫**：行笔中段饱满，线条浑厚有力；
            3. **提按分明**：转折处多见明显的提按动作，形成强烈的节奏感。

            ## 二、结构特点

            - **中宫收紧**：字的中心部分紧凑，向外辐射；
            - **撇捺舒展**：长撇大捺向外伸展，形成开张之势；
            - **欹侧相生**：字形多取斜势，险中求稳，如《张猛龙碑》。

            ## 三、代表碑刻

            | 碑名 | 风格 | 适合阶段 |
            | --- | --- | --- |
            | 《始平公造像记》 | 方峻雄强 | 入门 |
            | 《张猛龙碑》 | 险峻变化 | 进阶 |
            | 《郑文公碑》 | 圆浑蕴藉 | 深入 |

            ## 四、练习建议

            练习时建议先从《始平公造像记》入手，注意**逆锋起笔**与**提按转折**的配合。每天保持半小时悬腕练习，先求形似，再追神似。临摹时要特别注意观察原碑的**刀味**与**金石气**，这是魏碑区别于唐楷的关键所在。

            此外，可以对照《龙门二十品》整体感受北魏书风的多样性，理解同一时代不同刻工、不同用途带来的风格差异。坚持三个月，必有可观进步。
            """
        case "math":
            return """
            好的，我们来看泰勒公式：

            \\[\ne^x = \\sum_{n=0}^{\\infty} \\frac{x^n}{n!}\n\\]

            **关键点**在于展开项数越多，逼近越精确。例如 $e^{0.5}$ 取前 4 项：

            $$\ne^{0.5} \\approx 1 + 0.5 + \\frac{0.125}{2} + 0.0208\n$$

            可以看到误差已经很小。
            """
        case "sources":
            return """
            根据你的资料[材料：书法笔记]，魏碑体的特点主要有三点：

            1. **方笔为主**：起笔、收笔多见方切，棱角分明[材料：张猛龙碑拓片]；
            2. **结构险峻**：中宫收紧而撇捺舒展，如《张猛龙碑》；
            3. **气韵生动**：看似拙朴，实则变化丰富。

            练习时建议先从《始平公造像记》入手[笔记：临帖心得]，注意**逆锋起笔**与**提按转折**的配合。
            """
        case "currency":
            return """
            这套字帖的价格是 $128，配套课程 $199 起。

            如果预算有限，单买字帖即可；想要系统学习再考虑 $299 的完整套装。

            注意区分：这里的 $x$ 表示未知数，不是价格。
            """
        case "inlinemath":
            return """
            先看单行定界符：\\[e^x = 1 + x + o(x)\\] 这是泰勒展开。

            行内公式 \\(e^{i\\pi} = -1\\) 也很常见，还有单行块 $$x^2 + y^2 = r^2$$ 在后面接文字。

            帽子符号 \\hat x 与 \\hat \\beta 会触发转换。换行<br>之后的文本继续。
            """
        case "mathline":
            return """
            求和公式如下：

            [e^x = \\sum_{n=0}^{\\infty} \\frac{x^n}{n!}]

            这是行首方括号数学，闭合后接普通文字继续。
            """
        default:
            return """
            可以的。魏碑体的特点主要有三点：

            1. **方笔为主**：起笔、收笔多见方切，棱角分明；
            2. **结构险峻**：中宫收紧而撇捺舒展，如《张猛龙碑》；
            3. **气韵生动**：看似拙朴，实则变化丰富。

            练习时建议先从《始平公造像记》入手，注意**逆锋起笔**与**提按转折**的配合，每天保持半小时悬腕练习。
            """
        }
    }

    private static func sources(for scenario: String) -> [AgentReplySource] {
        guard scenario == "sources" else { return [] }
        return [
            AgentReplySource(
                itemID: nil,
                kind: .note,
                title: "书法笔记",
                label: "笔记",
                excerpt: "魏碑体方笔为主……"
            ),
        ]
    }
}
