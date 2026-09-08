import AppKit
import SwiftUI
import WeiBeiCore

#if CHAT_RENDERER_LAB
import ChatRendererKit

typealias AgentConversationMarkdownView = ChatRendererMarkdownView

struct ChatRendererMarkdownView: NSViewRepresentable {
    @Environment(\.chatRendererSession) private var session
    @Environment(\.chatRendererConversationID) private var conversationID
    var markdown: String
    var messageID: UUID?
    var fontSize: CGFloat
    var isDark: Bool
    var appearanceKey: String = ""
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    var placeholderHeight: CGFloat = 1
    var onOpenURL: (URL) -> Void
    var visualizationView: NativeChatVisualizationView?
    var imageLoader: ((String, @escaping (Data?) -> Void) -> Void)?

    @MainActor final class Coordinator {
        lazy var localDocument = CandidateDocument()
        var retainsSurface = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> CandidateTextView {
        let view: CandidateTextView
        if let session, let messageID {
            view = session.surface(for: messageID, in: conversationID)
            context.coordinator.retainsSurface = true
        } else { view = CandidateTextView() }
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: CandidateTextView, context: Context) {
        let document = messageID.flatMap { session?.state(for: $0, in: conversationID).document } ?? context.coordinator.localDocument
        view.onOpenURL = onOpenURL
        view.imageLoader = imageLoader
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        view.extensionView = { descriptor, width, onHeight in
            let nativeDescriptor: NativeChatAttachmentDescriptor
            switch descriptor {
            case let .mermaid(source): nativeDescriptor = .code(source: source, language: "mermaid")
            case let .visualization(id): nativeDescriptor = .visualization(id: id)
            case .image: return nil
            }
            weak var retainedView: NativeChatAttachmentView?
            let attachment = NativeChatTextAttachment(descriptor: nativeDescriptor,
                fontSize: fontSize, isDark: isDark, onOpenURL: onOpenURL,
                onSizeChange: {
                    guard let retainedView else { return }
                    onHeight(retainedView.size(for: max(1, retainedView.frame.width)).height)
                }, visualizationView: visualizationView, imageLoader: imageLoader,
                interfaceLanguage: interfaceLanguage)
            let native = NativeChatAttachmentView(attachment)
            retainedView = native
            native.frame.size = native.size(for: width)
            onHeight(native.frame.height)
            return native
        }
        view.onHeightChange = { [weak session] in
            if let messageID, session?.activeSessionID == conversationID { session?.list?.enqueueHeightChange(messageID) }
        }
        document.configure(fontSize: fontSize, ink: WeiBeiNativePalette.ink(),
            secondaryInk: WeiBeiNativePalette.secondaryInk(), accent: WeiBeiNativePalette.link())
        view.bind(document)
        document.submit(markdown)
        view.trackedScrollView = view.enclosingScrollView
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CandidateTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return NSSize(width: width, height: nsView.preparedDocument?.content == nil
            ? placeholderHeight : nsView.measuredHeight(for: width))
    }
    static func dismantleNSView(_ nsView: CandidateTextView, coordinator: Coordinator) {
        nsView.onHeightChange = nil
        if !coordinator.retainsSurface { nsView.unbind() }
    }
}
#else
typealias AgentConversationMarkdownView = NativeChatMarkdownView
#endif
