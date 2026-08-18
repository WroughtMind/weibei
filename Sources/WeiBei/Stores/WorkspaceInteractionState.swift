import Combine
import CoreGraphics
import Foundation
import WeiBeiCore

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
