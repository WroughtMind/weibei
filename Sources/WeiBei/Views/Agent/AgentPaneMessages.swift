import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

extension AgentPaneView {
    func agentMessageRow(
        message: AgentMessage,
        geometryWidth: CGFloat,
        contentWidth: CGFloat,
        wide: Bool
    ) -> some View {
        let isUser = message.role == .user
        let wideFamilies: Set<RichAnswerCapabilityFamily> = [
            .quantityAndCoordinates,
            .processAndState,
            .timeAndSpace,
            .imageAndOverlay,
            .comparisonAndEvaluation,
        ]
        let needsWideCanvas = message.richAnswer?.scenes.contains {
            wideFamilies.contains($0.family)
        } == true

        // Native text rows: no per-message WKWebView height callbacks that thrash scroll.
        return agentReadingColumn(
            geometryWidth: geometryWidth,
            contentWidth: contentWidth,
            wideLayout: wide,
            canvasWide: needsWideCanvas,
            alignment: isUser ? .trailing : .leading
        ) {
            AgentBubble(message: message)
        }
        .id(message.id)
        .transition(WeiBeiTransition.message)
    }

    /// One centered reading column for messages, streaming, and loading.
    /// `geometryWidth` must be the live measured pane width — a stale full-window value
    /// mis-centers multi-pane text (the PreferenceKey bug we fixed above).
    func agentReadingColumn<Content: View>(
        geometryWidth: CGFloat,
        contentWidth: CGFloat,
        wideLayout: Bool,
        canvasWide: Bool = false,
        alignment: HorizontalAlignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let readingWidth: CGFloat = {
            let paneLimit = max(geometryWidth - (wideLayout ? 32 : 16), 1)
            if wideLayout {
                // Rich-answer canvas can use a slightly wider band inside the same axis.
                let limit = canvasWide ? min(contentWidth + 40, paneLimit) : contentWidth
                return min(min(contentWidth, limit), paneLimit)
            }
            let limit: CGFloat = canvasWide ? 540 : 500
            // contentWidth already fits the strip; never force a design ceiling wider than the pane.
            return min(min(max(contentWidth, 1), limit), paneLimit)
        }()
        let readingLeadingInset = max((geometryWidth - readingWidth) / 2, 0)
        return content()
            .frame(maxWidth: readingWidth, alignment: Alignment(horizontal: alignment, vertical: .center))
            .padding(.leading, readingLeadingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var agentRailTurns: [AgentRailTurn] {
        var turns: [AgentRailTurn] = []
        for (index, message) in store.messages.enumerated() {
            switch message.role {
            case .user:
                turns.append(AgentRailTurn(
                    id: message.id,
                    startMessageID: message.id,
                    startIndex: index,
                    question: message.text,
                    answer: ""
                ))
            case .assistant:
                if turns.isEmpty {
                    turns.append(AgentRailTurn(
                        id: message.id,
                        startMessageID: message.id,
                        startIndex: index,
                        question: store.ui("对话回复", "Response"),
                        answer: message.text
                    ))
                } else if turns[turns.count - 1].answer.isEmpty {
                    turns[turns.count - 1].answer = message.text
                } else {
                    turns[turns.count - 1].answer += "\n\n" + message.text
                }
            }
        }
        return turns
    }

    var agentRailItems: [ContentRailItem] {
        let turns = agentRailTurns
        return turns.enumerated().map { index, turn in
            ContentRailItem(
                id: "chat-turn-\(turn.id.uuidString)",
                position: turns.count > 1 ? CGFloat(index) / CGFloat(turns.count - 1) : 0,
                title: railText(turn.question, fallback: store.ui("第 \(index + 1) 轮对话", "Conversation \(index + 1)")),
                excerpt: railText(turn.answer, fallback: store.ui("等待回复", "Waiting for response")),
                metadata: store.ui("第 \(index + 1) / \(turns.count) 轮", "Turn \(index + 1) / \(turns.count)")
            )
        }
    }

    func activateAgentRailItem(_ item: ContentRailItem, railOnly: Bool, proxy: ScrollViewProxy) {
        guard let turn = agentRailTurns.first(where: { "chat-turn-\($0.id.uuidString)" == item.id }) else { return }
        activeAgentRailID = item.id
        agentFollowsLatest = false
        let navigate = {
            withAnimation(WeiBeiMotion.panel) {
                proxy.scrollTo(turn.startMessageID, anchor: .center)
            }
        }
        if railOnly {
            store.requestPaneExpansion(.agent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: navigate)
        } else {
            navigate()
        }
    }

    func updateAgentRailPosition(for messageID: UUID?) {
        guard let messageID,
              let visibleIndex = store.messages.firstIndex(where: { $0.id == messageID }) else { return }
        agentFollowsLatest = messageID == store.messages.last?.id
        if let turn = agentRailTurns.last(where: { $0.startIndex <= visibleIndex }) {
            activeAgentRailID = "chat-turn-\(turn.id.uuidString)"
        }
    }

    func railText(_ value: String, fallback: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: #"[`*_>#\[\]()]"#, with: "", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? fallback : String(collapsed.prefix(180))
    }

    var emptyAgentState: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: starterChipColumns, alignment: .leading, spacing: 6) {
                if store.canResumePreviousStudy {
                    starterChip(store.ui("继续上次", "Resume"), systemImage: "arrow.uturn.forward", help: store.ui("回顾上次学习位置并继续", "Review the last study location and continue")) {
                        store.resumePreviousStudy()
                        askWith(store.ui("上次学到哪了？请结合学习记忆告诉我当时的位置、还没解决的问题和现在最适合的下一步。", "Where did I stop last time? Use my learning memory to give the location, unresolved questions, and the best next step."))
                    }
                }
                if store.allItems.count > 1 {
                    starterChip(store.ui("关联", "Connections"), systemImage: "point.3.connected.trianglepath.dotted", help: store.ui("查找当前概念在课程里的关联", "Find related course materials and notes")) {
                        askWith(store.ui("请查找当前材料、选区或笔记在整个课程里的知识关联，说清为什么相关，并给出可跳转的来源。", "Find connections between the current material, selection, or note and the rest of the course. Explain each connection and provide jumpable sources."))
                    }
                }
                if store.hasSelectedMaterial {
                    starterChip(store.ui("梳理", "Outline"), systemImage: "text.alignleft", help: store.ui("梳理当前材料", "Outline current material")) {
                        askWith(store.ui("请基于当前材料提炼核心概念、关键公式和需要回看出处的位置。", "Extract the core concepts, key formulas, and places that need source review from the current material."))
                    }
                }
                starterChip(store.ui("整理", "Organize"), systemImage: "list.bullet.rectangle", help: store.ui("整理当前笔记", "Organize current note")) {
                    store.askToOrganizeNote()
                }
                if store.hasSelectedMaterial {
                    starterChip(store.ui("出题", "Quiz"), systemImage: "questionmark.square", help: store.ui("生成复习题", "Generate review questions")) {
                        askWith(store.ui("请根据当前材料和笔记生成 5 个复习问题，并标出每题依据。", "Generate 5 review questions from the current material and note, and cite the evidence for each question."))
                    }
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    func starterChip(_ title: String, systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        AgentStarterChip(title: title, systemImage: systemImage, help: help, action: action)
    }

    var starterChipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 56), spacing: 6, alignment: .leading)]
    }

    func askWith(_ prompt: String) {
        withAnimation(WeiBeiMotion.panel) {
            store.agentDraft = prompt
        }
        store.askAgent()
    }

    /// Compact catalog for immersive hover tab + pane header — material / practice history.
}
