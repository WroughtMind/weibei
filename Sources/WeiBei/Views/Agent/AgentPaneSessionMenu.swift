import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

extension AgentPaneView {
    var agentSessionCatalogMenu: some View {
        Menu {
            sessionCatalogContent
        } label: {
            Label {
                Text(store.ui("目录", "Catalog"))
                    .font(.system(size: 11, weight: .medium))
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(Text(store.ui("对话目录", "Conversation catalog")))
        .help(store.ui("按资料或实践切换历史会话", "Switch history by material or practice"))
    }

    var sessionMenu: some View {
        Menu {
            sessionCatalogContent
        } label: {
            Image(systemName: "list.bullet.rectangle")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 24))
        .accessibilityLabel(Text(store.ui("学习会话", "Study Sessions")))
        .help(store.ui("按资料查看、新建或切换对话", "Browse by material, create, or switch conversations"))
    }

    @ViewBuilder
    var sessionCatalogContent: some View {
        Button {
            store.createStudySession()
        } label: {
            Label(store.ui("新对话", "New Conversation"), systemImage: "plus")
        }

        Button {
            store.setShowAllStudySessions(!store.showAllStudySessions)
        } label: {
            Label(
                store.showAllStudySessions
                    ? store.ui("仅当前资料", "Current Material Only")
                    : store.ui("全部资料 / 实践", "All Materials / Practice"),
                systemImage: store.showAllStudySessions ? "folder" : "books.vertical"
            )
        }

        Divider()

        if store.showAllStudySessions {
            ForEach(Array(store.studySessionsGroupedByMaterial.enumerated()), id: \.offset) { _, group in
                Section(group.title) {
                    ForEach(group.sessions.prefix(12)) { session in
                        sessionMenuButton(session)
                    }
                }
            }
        } else {
            Section(store.ui("与当前资料相关", "Related to Current Material")) {
                ForEach(store.studySessionsForMenu.prefix(16)) { session in
                    sessionMenuButton(session)
                }
            }
        }

        if !store.orderedLearningMemoryEntries.isEmpty {
            Divider()
            Menu {
                ForEach(Array(store.orderedLearningMemoryEntries.prefix(20))) { memory in
                    if memory.status == .resolved {
                        Button {
                            store.restoreLearningMemory(memory.id)
                        } label: {
                            Label(
                                "\(store.learningMemoryKindLabel(memory.kind))：\(String(memory.text.prefix(64)))",
                                systemImage: "arrow.uturn.backward"
                            )
                        }
                    } else if memory.kind == .goal || memory.kind == .confusion || memory.kind == .nextStep {
                        Button {
                            store.resolveLearningMemory(memory.id)
                        } label: {
                            Label(
                                "\(store.learningMemoryKindLabel(memory.kind))：\(String(memory.text.prefix(64)))",
                                systemImage: "checkmark.circle"
                            )
                        }
                    } else {
                        Label(
                            "\(store.learningMemoryKindLabel(memory.kind))：\(String(memory.text.prefix(64)))",
                            systemImage: "brain.head.profile"
                        )
                    }
                }
            } label: {
                Label(store.ui("学习记忆", "Learning Memory"), systemImage: "brain.head.profile")
            }
        }

        if store.hasCurrentSessionInferredMemory {
            Divider()
            Button(role: .destructive) {
                store.clearCurrentSessionInferredMemory()
            } label: {
                Label(store.ui("清除本会话推断记忆", "Clear Inferred Memory"), systemImage: "brain.head.profile")
            }
        }

        if let activeID = store.activeStudySessionID, store.studySessions.count > 1 {
            Button(role: .destructive) {
                store.deleteStudySession(activeID)
            } label: {
                Label(store.ui("删除当前会话", "Delete Current Session"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    func sessionMenuButton(_ session: StudySession) -> some View {
        Button {
            store.activateStudySession(session.id)
        } label: {
            if session.id == store.activeStudySessionID {
                Label(session.title, systemImage: "checkmark")
            } else {
                Text(session.title)
            }
        }
    }

}
