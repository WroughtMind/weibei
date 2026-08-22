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

/// Transient selection / floating-agent interaction chrome.
/// Isolated from `WorkspaceStore` so selection drag does not rebuild the whole workspace tree.
@MainActor
final class WorkspaceInteractionState: ObservableObject {
    @Published var agentSurface: AgentSurface = .hidden
    @Published var floatingSelectionPrompt = ""
    @Published var pinnedFloatingAgent = false
    @Published var selectionContext: SelectionContext?
    @Published var selectionAttachments: [SelectionContext] = []
    @Published var activeSelectionAskThreadID: UUID?
    @Published var keepFloatingSelectionForAnswer = false
    @Published var noteSelectionFormatting: NoteSelectionFormatting?
    /// ⌘K in the note editor asks the selection capsule to open its link popover; bump to request.
    @Published var noteLinkEditorRequest = 0
    /// 问/记共用浮层的当前模式;胶囊"问/记"点击时切换。
    @Published var floatingComposerMode: FloatingSelectionComposerMode = .ask
    /// "记"模式的独立草稿;与问的 agentDraft 互不覆盖,提交后清空。
    @Published var selectionNoteDraft = ""

    /// Selection capsule position. Anchor-only drag/scroll updates can suppress
    /// publish so agent chat SelectionOverlay is not remasured every pixel.
    private var selectionAnchorValue: CGPoint?
    private var suppressSelectionAnchorPublish = false
    private var lastSelectionAnchorPublishAt: CFAbsoluteTime = 0

    var selectionAnchor: CGPoint? {
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
    func setSelectionAnchorSilently(_ anchor: CGPoint?) {
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

    static func anchorsApproximatelyEqual(_ lhs: CGPoint?, _ rhs: CGPoint?, epsilon: CGFloat = 0.5) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return abs(left.x - right.x) < epsilon && abs(left.y - right.y) < epsilon
        default:
            return false
        }
    }
}
