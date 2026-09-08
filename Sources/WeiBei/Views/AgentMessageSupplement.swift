import SwiftUI
import WeiBeiCore

/// Message controls stay small; the main conversation's text is owned by AppKit.
struct AgentMessageSupplement: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.openWindow) private var openSettingsWindow
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    var message: AgentMessage
    var citations: [AgentCitation]
    var drafts: [UUID: AgentReplyActionDraft] = [:]
    var onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.sources.isEmpty {
                AgentReplySourceTagRow(sources: message.sources) { source in
                    activateSource(source)
                }
            }

            if !citations.isEmpty {
                AgentCitationTagRow(citations: citations) { citation in
                    activateCitation(citation)
                }
            }

            if !message.actions.isEmpty {
                ForEach(message.actions) { action in
                    AgentReplyActionCard(
                        messageID: message.id,
                        action: action,
                        draft: drafts[action.id]
                    )
                }
            }

            if message.origin?.courseID != nil,
               let memoryUpdate = message.memoryUpdate,
               !memoryUpdate.memoryIDs.isEmpty {
                AgentReplyMemoryUpdateTag(
                    message: message,
                    update: memoryUpdate
                )
                .transition(WeiBeiTransition.floating)
            }

            if message.origin?.courseID != nil,
               let profileUpdate = message.profileUpdate,
               !profileUpdate.entryIDs.isEmpty {
                AgentReplyProfileUpdateTag(update: profileUpdate)
                    .transition(WeiBeiTransition.floating)
            }

            if message.completionState == .interrupted && !isFailureMessage {
                HStack(spacing: 6) {
                    Text(store.ui("回答已中断，已保留现有内容", "Response interrupted; existing content was kept"))
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    if store.canRetryAgentRequest(
                        question: message.retryQuestion,
                        failureKind: message.failureKind
                    ), let question = message.retryQuestion {
                        Button(store.ui("重试", "Retry")) {
                            store.retryAgentRequest(
                                question,
                                targetCourseID: message.origin?.courseID
                            )
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                }
                .padding(.top, 2)
            } else if isFailureMessage {
                HStack(spacing: 6) {
                    if store.canRetryAgentRequest(
                        question: message.retryQuestion,
                        failureKind: message.failureKind
                    ), let question = message.retryQuestion {
                        Button(store.ui("重试", "Retry")) {
                            store.retryAgentRequest(
                                question,
                                targetCourseID: message.origin?.courseID
                            )
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                    if let question = message.retryQuestion, !question.isEmpty {
                        Button(store.ui("回填问题", "Restore question")) {
                            store.agentDraft = question
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    if message.failureKind == .unauthorized
                        || !AgentProviderReadiness.isConfigured(for: store) {
                        Button(store.ui("去设置", "Open Settings")) {
                            if let onOpenSettings { onOpenSettings() }
                            else { openSettingsWindow(id: "weibei-settings") }
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                .padding(.top, 2)
            } else if message.id == store.lastUsableAgentAnswerID,
                      store.selectionContext != nil || store.canReplaceNoteSelection {
                HStack(spacing: 6) {
                    if store.selectionContext != nil {
                        Button(store.ui("摘录", "Excerpt")) {
                            store.appendSelectionToNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    if store.canReplaceNoteSelection {
                        Button(store.ui("替换", "Replace")) {
                            store.replaceSelectionWithLastAgentAnswer()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func activateSource(_ source: AgentReplySource) {
        withAnimation(WeiBeiMotion.panel) {
            _ = store.openAgentReplySource(source)
        }
    }

    private func activateCitation(_ citation: AgentCitation) {
        switch citation.kind {
        case .material:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "material", value: citation.value)
            }
        case .note:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "note", value: citation.value)
            }
        case .selection:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "selection", value: citation.value)
            }
        case .learningRecord:
            withAnimation(WeiBeiMotion.panel) {
                store.resumePreviousStudy()
            }
        case .learningMemory:
            if let courseID = message.origin?.courseID {
                withAnimation(WeiBeiMotion.panel) {
                    store.presentCourseWorkspace(.memory, courseID: courseID)
                }
            }
        case .session:
            break
        }
    }


    private var isUser: Bool { message.role == .user }
    private var isFailureMessage: Bool {
        message.role == .assistant && WorkspaceStore.isAgentFailureMessage(message.text)
    }
}
