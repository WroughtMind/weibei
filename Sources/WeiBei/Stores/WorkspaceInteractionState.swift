import Combine
import CoreGraphics
import Foundation
import WeiBeiCore

struct NoteSelectionFormatting: Equatable {
    var activeMarks: Set<String>
    var blockType: String
    var canConvertToMath: Bool
    var linkTarget: String
}

/// 问/记共用浮层的当前面向:问=提问模式,记=札记模式。
enum FloatingSelectionComposerMode {
    case ask
    case remark
}

struct ExcerptRevealRequest: Equatable {
    let id = UUID()
    let recordID: UUID
}

/// Transient selection / floating-agent interaction chrome.
/// Isolated from `WorkspaceStore` so selection drag does not rebuild the whole workspace tree.
@MainActor
final class WorkspaceInteractionState: ObservableObject {
#if targetEnvironment(macCatalyst)
    // UI drafts survive collection-cell eviction and switching away from a chat.
    var agentActionDrafts: [UUID: (title: String, body: String)] = [:]
#endif
    @Published var agentSurface: AgentSurface = .hidden
    @Published var floatingSelectionPrompt = ""
    @Published var pinnedFloatingAgent = false
    @Published var selectionContext: SelectionContext?
    @Published var selectionAttachments: [SelectionContext] = []
    @Published var activeSelectionAskThreadID: UUID?
    @Published var keepFloatingSelectionForAnswer = false
    @Published var noteSelectionFormatting: NoteSelectionFormatting?
    @Published var noteLinkEditorRequest = 0
    /// 问/记共用浮层的当前模式;胶囊"问/记"点击时切换。
    @Published var floatingComposerMode: FloatingSelectionComposerMode = .ask
    /// "记"模式的独立草稿;与问的 agentDraft 互不覆盖,提交后清空。
    /// 按选区锚点分开存放。换到另一段时只显示那段自己的草稿。
    @Published var selectionNoteDraft = ""
    private var selectionNoteDraftsByAnchor: [String: String] = [:]

    func rebaseSelectionNoteDraft(from previous: SelectionContext?, to next: SelectionContext?) {
        let previousKey = previous.map(Self.selectionNoteDraftKey)
        let nextKey = next.map(Self.selectionNoteDraftKey)
        guard previousKey != nextKey else { return }
        if let previousKey {
            if selectionNoteDraft.isEmpty {
                selectionNoteDraftsByAnchor.removeValue(forKey: previousKey)
            } else {
                selectionNoteDraftsByAnchor[previousKey] = selectionNoteDraft
            }
        }
        selectionNoteDraft = nextKey.flatMap { selectionNoteDraftsByAnchor[$0] } ?? ""
    }

    static func selectionNoteDraftKey(for context: SelectionContext) -> String {
        var parts = [
            "\(context.source)",
            context.itemID ?? "",
            SelectionAttachmentMerge.normalized(context.text),
        ]
        if let anchor = context.documentAnchor,
           let data = try? JSONEncoder().encode(anchor),
           let encoded = String(data: data, encoding: .utf8) {
            parts.append(encoded)
        }
        return parts.joined(separator: "\u{1f}")
    }

    /// Selection capsule position. Anchor-only drag/scroll updates can suppress
    /// publish so agent chat SelectionOverlay is not remasured every pixel.
    private var selectionAnchorValue: SelectionPopoverAnchor?
    private var suppressSelectionAnchorPublish = false
    private var lastSelectionAnchorPublishAt: CFAbsoluteTime = 0

    var selectionAnchor: SelectionPopoverAnchor? {
        get { selectionAnchorValue }
        set {
            guard !Self.anchorsApproximatelyEqual(selectionAnchorValue, newValue) else { return }
            if !suppressSelectionAnchorPublish {
                objectWillChange.send()
            }
            selectionAnchorValue = newValue
        }
    }

    /// Write anchor without publishing (drag stream); caller may throttle a later publish.
    func setSelectionAnchorSilently(_ anchor: SelectionPopoverAnchor?) {
        guard !Self.anchorsApproximatelyEqual(selectionAnchorValue, anchor) else { return }
        selectionAnchorValue = anchor
    }

    /// Throttled publish after silent anchor writes (~20fps for floating capsule).
    @discardableResult
    func publishSelectionAnchorIfDue(minInterval: CFTimeInterval = 0.05) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSelectionAnchorPublishAt >= minInterval else { return false }
        lastSelectionAnchorPublishAt = now
        objectWillChange.send()
        return true
    }

    var isSuppressingSelectionAnchorPublish: Bool {
        get { suppressSelectionAnchorPublish }
        set { suppressSelectionAnchorPublish = newValue }
    }

    static func anchorsApproximatelyEqual(_ lhs: SelectionPopoverAnchor?, _ rhs: SelectionPopoverAnchor?, epsilon: CGFloat = 0.5) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left.prefersAbove == right.prefersAbove && left.textAnchor == right.textAnchor
                && abs(left.x - right.x) < epsilon && abs(left.y - right.y) < epsilon
        default:
            return false
        }
    }
}

extension Notification.Name {
    static let weiBeiScrollAgentToMessage = Notification.Name("WeiBeiScrollAgentToMessage")
}
