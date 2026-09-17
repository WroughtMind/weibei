import UIKit
import Combine
import SwiftUI
import WeiBeiCore
import MarkdownView
import MarkdownParser

struct CatalystConversationView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var wideTypography = false
    var bodyWidth: CGFloat? = nil
    var displayedMessages: [AgentMessage]? = nil
    var floatingThreadID: UUID? = nil
    var onContentHeight: (CGFloat) -> Void = { _ in }
    var onFocusComposer: () -> Void
    var onReadingMessage: (UUID?) -> Void
    var body: some View { Bridge(workspace: store, streaming: store.streaming(in: floatingThreadID ?? store.activeStudySessionID), wideTypography: wideTypography, bodyWidth: bodyWidth,
        displayedMessages: displayedMessages, floatingThreadID: floatingThreadID, onContentHeight: onContentHeight,
        onFocusComposer: onFocusComposer, onReadingMessage: onReadingMessage).contentShape(Rectangle()) }
    private struct Bridge: UIViewControllerRepresentable {
        @Environment(\.weibeiReduceMotion) private var reduceMotion
        @ObservedObject var workspace: WorkspaceStore
        @ObservedObject var streaming: AgentStreamingState
        var wideTypography: Bool
        var bodyWidth: CGFloat?
        var displayedMessages: [AgentMessage]?
        var floatingThreadID: UUID?
        var onContentHeight: (CGFloat) -> Void
        var onFocusComposer: () -> Void
        var onReadingMessage: (UUID?) -> Void
        func makeCoordinator() -> Coordinator { Coordinator() }
        func makeUIViewController(context: Context) -> ConversationController {
            let controller = ConversationController(fixtureMode: false)
            controller.usesWorkspaceChrome = true
            controller.openSource = { [weak workspace] in _ = workspace?.openAgentReplySource($0) }
            controller.readingMessageChanged = onReadingMessage
            controller.contentHeightChanged = onContentHeight
            context.coordinator.observeNavigation(controller)
            context.coordinator.bind(workspace, controller: controller)
            return controller
        }
        func updateUIViewController(_ controller: ConversationController, context: Context) {
            controller.reduceMotion = reduceMotion
            controller.reservesReplySpace = floatingThreadID == nil
            controller.workspaceBodyWidth = bodyWidth
            controller.readingMessageChanged = onReadingMessage
            controller.contentHeightChanged = onContentHeight
            let coordinator = context.coordinator
            coordinator.wideTypography = wideTypography
            let fontSize = (wideTypography ? 16.0 : 14.0) * workspace.interfaceTextScale.multiplier
            var appearanceChanged = false
            if coordinator.fontSize != fontSize || coordinator.appearance != workspace.appearanceMode {
                coordinator.fontSize = fontSize; coordinator.appearance = workspace.appearanceMode
                appearanceChanged = controller.store.setTheme(.weiBei(fontSize: fontSize, appearance: workspace.appearanceMode))
            }
            if appearanceChanged { controller.updateJumpToLatestAppearance(workspace.appearanceMode) }
            controller.interfaceLanguage = workspace.interfaceLanguage
            let imageContext = (workspace.currentMarkdownBaseURL?.absoluteString ?? "") + "|" + (workspace.currentAttachmentDirectory?.path ?? "")
            if coordinator.imageContext != imageContext {
                coordinator.imageContext = imageContext
                let handler = MarkdownImageSchemeHandler()
                handler.update(markdownBaseURLString: workspace.currentMarkdownBaseURL?.absoluteString ?? "",
                    attachmentDirectory: workspace.currentAttachmentDirectory, appearanceMode: workspace.appearanceMode,
                    interfaceLanguage: workspace.interfaceLanguage)
                controller.setImages(LabImages(loader: handler))
            }
            controller.view.backgroundColor = .clear
            let targetID = floatingThreadID ?? workspace.activeStudySessionID
            controller.setAnswering(targetID.map { workspace.isAgentRunning(in: $0) } ?? false, status: streaming.activityText ?? "")
            controller.quoteText = { [weak workspace] text in
                guard let workspace, let targetID else { return }
                workspace.replaceComposerDraft("> " + text.replacingOccurrences(of: "\n", with: "\n> ") + "\n\n", for: targetID)
                workspace.focusedPane = .agent
                onFocusComposer()
            }
            let reveal = floatingThreadID == nil ? nil : workspace.selectionChatRevealMessageID
            let revealChanged = coordinator.requestedMessageID != reveal
            coordinator.requestedMessageID = reveal
            let changed = coordinator.needsSnapshot(workspace, streaming: streaming)
            let changedFloating = coordinator.floatingMessages != displayedMessages || coordinator.floatingThreadID != floatingThreadID
            coordinator.floatingMessages = displayedMessages; coordinator.floatingThreadID = floatingThreadID
            guard changed || changedFloating || appearanceChanged || revealChanged else { return }
            var session = workspace.activeStudySession ?? StudySession(id: Coordinator.emptyID, title: workspace.agentConversationSubtitle)
            session.id = floatingThreadID ?? session.id
            session.messages = displayedMessages ?? workspace.messages
            if let id = streaming.displayingMessageID,
               streaming.displayingChatID == targetID,
               let index = session.messages.firstIndex(where: { $0.id == id }) {
                session.messages[index] = streaming.applyingDisplayText(to: session.messages[index])
            }
            coordinator.enqueue(session, into: controller, refreshAppearance: appearanceChanged)
        }
        static func dismantleUIViewController(_ controller: ConversationController, coordinator: Coordinator) { coordinator.stop() }
    }
    @MainActor private final class Coordinator {
        static let emptyID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var displayedSessionID: UUID?
        var requestedMessageID: UUID?
        weak var workspace: WorkspaceStore?
        var previous: [UUID: AgentMessage] = [:]
        var pending: StudySession?
        var worker: Task<Void, Never>?
        var navigation: NSObjectProtocol?
        var imageContext: String?
        var messageSubscription: AnyCancellable?
        var messageRevision = 0
        var enqueuedRevision = -1
        var enqueuedSessionID: UUID?
        var enqueuedStreamingText = ""
        var enqueuedStreamingID: UUID?
        var refreshAppearance = false
        var wideTypography = false
        var fontSize: CGFloat = 0
        var appearance: WeiBeiAppearanceMode?
        var floatingMessages: [AgentMessage]?
        var floatingThreadID: UUID?
        var auxiliaryHosts: [String: CatalystHostingView] = [:]
        func needsSnapshot(_ store: WorkspaceStore, streaming: AgentStreamingState) -> Bool {
            let changed = enqueuedRevision != messageRevision || enqueuedSessionID != store.activeStudySessionID
                || enqueuedStreamingID != streaming.displayingMessageID || enqueuedStreamingText != streaming.text
            enqueuedRevision = messageRevision; enqueuedSessionID = store.activeStudySessionID
            enqueuedStreamingID = streaming.displayingMessageID; enqueuedStreamingText = streaming.text
            return changed
        }
        func bind(_ workspace: WorkspaceStore, controller: ConversationController) {
            self.workspace = workspace
            messageSubscription = workspace.$messages.sink { [weak self] _ in self?.messageRevision += 1 }
            controller.auxiliaryView = { [weak self, weak workspace, weak controller] message in
                guard let self, let workspace, let original = message.original else { return UIView() }
                let root = CatalystMessageFooter(initial: original,
                    streaming: original.completionState == .generating
                        ? workspace.streaming(in: original.origin?.chatID) : inertAgentStreamingState,
                    wideTypography: wideTypography, onHeight: { [weak controller, weak message] height in
                    // Geometry arrives during SwiftUI layout; resize the collection after that pass.
                    DispatchQueue.main.async {
                        guard let message else { return }
                        controller?.updateAuxiliaryHeight(height, for: message)
                    }
                }).environmentObject(workspace).environment(\.weiBeiTextScale, workspace.interfaceTextScale.multiplier)
                if let host = auxiliaryHosts[message.id] {
                    host.controller.rootView = AnyView(root)
                    return host
                }
                let host = CatalystHostingView(root)
                auxiliaryHosts[message.id] = host
                if auxiliaryHosts.count > 36 {
                    for id in Array(auxiliaryHosts.keys) where id != message.id && auxiliaryHosts[id]?.superview == nil {
                        auxiliaryHosts[id] = nil
                        if auxiliaryHosts.count <= 36 { break }
                    }
                }
                return host
            }
            controller.store.workspaceAttachment = { [weak workspace] block, identifier, height in
                guard let workspace, let messageID = UUID(uuidString: block.messageID) else { return UIView() }
                return CatalystHostingView(AgentNativeContentAttachment(messageID: messageID,
                    identifier: identifier, initialBlocks: workspace.studySessions.lazy.flatMap(\.messages).first { $0.id == messageID }?.contentBlocks ?? [],
                    onHeight: height).environmentObject(workspace)
                    .environment(\.weiBeiTextScale, workspace.interfaceTextScale.multiplier))
            }
            controller.messageLink = { [weak workspace, weak controller] url, message in
                guard let workspace, let controller else { return }
                let presentation = AgentReplySourceInlinePresentation(text: message.text, sources: message.sources, language: workspace.interfaceLanguage)
                if let source = presentation.source(for: url) { _ = workspace.openAgentReplySource(source) }
                else if !presentation.additionalSources(for: url).isEmpty {
                    let choices = presentation.additionalSources(for: url)
                    let sheet = UIAlertController(title: workspace.ui("引用来源", "Sources"), message: nil, preferredStyle: .actionSheet)
                    choices.forEach { source in sheet.addAction(UIAlertAction(title: source.label, style: .default) { _ in _ = workspace.openAgentReplySource(source) }) }
                    sheet.addAction(UIAlertAction(title: workspace.ui("取消", "Cancel"), style: .cancel))
                    sheet.popoverPresentationController?.sourceView = controller.view
                    sheet.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
                    controller.present(sheet, animated: true)
                } else if url.scheme == "weibei-note" {
                    workspace.openOrCreateWikiNote(title: String(url.absoluteString.dropFirst("weibei-note:".count)).removingPercentEncoding ?? url.path)
                } else if url.scheme == "weibei-source" {
                    workspace.openSourceReference(String(url.absoluteString.dropFirst("weibei-source:".count)).removingPercentEncoding ?? url.path)
                } else if url.isFileURL { _ = CatalystDesktopWindow.shared.open(url) }
                else if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
            }
        }
        func enqueue(_ session: StudySession, into controller: ConversationController, refreshAppearance: Bool) {
            self.refreshAppearance = self.refreshAppearance || refreshAppearance
            pending = session
            guard worker == nil else { return }
            worker = Task { [weak self, weak controller] in
                guard let self, let controller else { return }
                while let session = pending, !Task.isCancelled {
                    pending = nil
                    if displayedSessionID != session.id {
                        auxiliaryHosts.removeAll()
                        let firstTurn = displayedSessionID != nil && previous.isEmpty
                            && session.messages.contains { $0.completionState == .generating }
                        await controller.showSession(session, animateFirstTurn: firstTurn)
                        displayedSessionID = session.id
                    } else {
                        controller.updateSavedHistory(session.messages)
                        let existingIDs = Set(session.messages.map(\.id))
                        controller.removeMessages(except: existingIDs)
                        let loaded = Set(controller.messages.map(\.id))
                        for value in session.messages where previous[value.id] != value {
                            guard !Task.isCancelled else { break }
                            // Earlier saved history is prepared only when the user asks for that page.
                            if loaded.contains(value.id.uuidString) || previous[value.id] == nil {
                                await controller.display(value, streaming: value.completionState == .generating)
                            }
                        }
                    }
                    if self.refreshAppearance {
                        self.refreshAppearance = false
                        await controller.refreshAppearance()
                    }
                    previous = Dictionary(uniqueKeysWithValues: session.messages.map { ($0.id, $0) })
                    if let id = requestedMessageID,
                       session.messages.contains(where: { $0.id == id }) {
                        await controller.revealMessage(id)
                        requestedMessageID = nil
                        if workspace?.selectionChatRevealMessageID == id {
                            workspace?.selectionChatRevealMessageID = nil
                        }
                    }
                }
                worker = nil
            }
        }
        func observeNavigation(_ controller: ConversationController) {
            navigation = NotificationCenter.default.addObserver(forName: .weiBeiScrollAgentToMessage, object: nil, queue: .main) { [weak controller] note in
                guard let id = note.object as? UUID else { return }
                Task { @MainActor in await controller?.revealMessage(id) }
            }
        }
        func stop() { messageSubscription = nil; auxiliaryHosts.removeAll(); worker?.cancel(); worker = nil; pending = nil; if let navigation { NotificationCenter.default.removeObserver(navigation) }; navigation = nil }
        deinit { if let navigation { NotificationCenter.default.removeObserver(navigation) } }
    }
}

private struct CatalystMessageFooter: View {
    @EnvironmentObject var store: WorkspaceStore
    let initial: AgentMessage
    @ObservedObject var streaming: AgentStreamingState
    let wideTypography: Bool
    let onHeight: (CGFloat) -> Void
    private var message: AgentMessage { streaming.applyingDisplayText(to: store.messages.first { $0.id == initial.id } ?? initial) }
    var body: some View {
        let text = streaming.isDisplaying(message.id) ? streaming.text : message.text
        VStack(alignment: .leading, spacing: 8) {
            if message.role == .user {
                AgentBubble(message: message, isChatWideTypography: wideTypography)
            } else {
                if message.completionState == .generating && !message.toolActivities.contains(where: { $0.state == .running }) && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AgentThinkingIndicator(activityText: streaming.activityText, chatWideTypography: wideTypography)
                }
                AgentBubble(message: message, isChatWideTypography: wideTypography, showsBody: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { onHeight(max(8, geometry.size.height)) }
                    .onChange(of: geometry.size.height) { _, height in onHeight(max(8, height)) }
            }
        }
    }
}

/// The floating selection surface uses the same upstream UIKit text implementation.
struct CatalystMessageMarkdown: UIViewRepresentable {
    var markdown: String
    var fontSize: CGFloat
    var appearanceMode: WeiBeiAppearanceMode
    var openLink: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.throttleInterval = nil
        return view
    }
    func updateUIView(_ view: MarkdownTextView, context: Context) {
        view.linkHandler = { value, _, _ in
            switch value {
            case let .url(url): openLink(url)
            case let .string(value): if let url = URL(string: value) { openLink(url) }
            }
        }
        let coordinator = context.coordinator
        guard coordinator.markdown != markdown || coordinator.fontSize != fontSize || coordinator.appearance != appearanceMode else { return }
        coordinator.markdown = markdown; coordinator.fontSize = fontSize; coordinator.appearance = appearanceMode
        let theme = MarkdownTheme.weiBei(fontSize: fontSize, appearance: appearanceMode)
        let parsed = MarkdownParser().parse(markdown)
        let content = MarkdownContent(parserResult: parsed, theme: theme)
        view.setContentImmediately(content, theme: theme)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? uiView.bounds.width)
        return CGSize(width: width, height: max(1, uiView.boundingSize(for: width).height))
    }
    final class Coordinator {
        var markdown: String?
        var fontSize: CGFloat = 0
        var appearance: WeiBeiAppearanceMode?
    }
}
