import AppKit
import QuartzCore
import SwiftUI
import WeiBeiCore

struct StableDocumentWorkspace: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var firstSplit: CGFloat
    @Binding var secondSplit: CGFloat
    @Binding var halfSplit: CGFloat
    let registry: PersistentPaneHostRegistry
    let normalizedOrder: [WorkspacePaneRole]
    let visibleOrder: [WorkspacePaneRole]
    let draggedRole: WorkspacePaneRole?
    let expansionRequest: PaneExpansionRequest?
    let onFramesChange: ([WorkspacePaneRole], [CGRect]) -> Void
    let onExpansionRequestHandled: (UUID) -> Void

    func makeCoordinator() -> StableDocumentSplitCoordinator {
        StableDocumentSplitCoordinator(
            firstSplit: $firstSplit,
            secondSplit: $secondSplit,
            halfSplit: $halfSplit
        )
    }

    func makeNSView(context: Context) -> StableDocumentSplitView {
        let splitView = StableDocumentSplitView()
        let roleHosts = Dictionary(uniqueKeysWithValues: WorkspacePaneRole.allCases.map { role in
            (role, nativeHost(
                PersistentPaneHost(role: role, registry: registry)
                    .environmentObject(store),
                identifier: "stable-document-slot-\(role.rawValue)"
            ))
        })
        let emptyHost = nativeHost(
            EmptyWorkspaceLauncherView().environmentObject(store),
            identifier: "stable-document-empty-workspace"
        )
        splitView.install(roleHosts: roleHosts, emptyHost: emptyHost)
        context.coordinator.install(in: splitView)
        update(splitView, coordinator: context.coordinator)
        return splitView
    }

    func updateNSView(_ splitView: StableDocumentSplitView, context: Context) {
        update(splitView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ splitView: StableDocumentSplitView, coordinator: StableDocumentSplitCoordinator) {
        coordinator.stop(in: splitView)
    }

    private func update(_ splitView: StableDocumentSplitView, coordinator: StableDocumentSplitCoordinator) {
        coordinator.firstSplit = $firstSplit
        coordinator.secondSplit = $secondSplit
        coordinator.halfSplit = $halfSplit
        coordinator.onFramesChange = onFramesChange
        coordinator.onExpansionRequestHandled = onExpansionRequestHandled
        coordinator.update(
            state: StableDocumentLayoutState(
                normalizedOrder: WorkspacePaneRole.normalized(normalizedOrder),
                visibleOrder: visibleOrder,
                firstSplit: firstSplit,
                secondSplit: secondSplit,
                halfSplit: halfSplit
            ),
            draggedRole: draggedRole,
            expansionRequest: expansionRequest,
            in: splitView
        )
    }

    private func nativeHost<Content: View>(_ content: Content, identifier: String) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(content))
        host.identifier = NSUserInterfaceItemIdentifier(identifier)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = []
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        return host
    }
}

struct StableDocumentLayoutState: Equatable {
    let normalizedOrder: [WorkspacePaneRole]
    let visibleOrder: [WorkspacePaneRole]
    let firstSplit: CGFloat
    let secondSplit: CGFloat
    let halfSplit: CGFloat

    func hasSameStructure(as other: StableDocumentLayoutState) -> Bool {
        normalizedOrder == other.normalizedOrder && visibleOrder == other.visibleOrder
    }

    func hasSameStoredRatios(as other: StableDocumentLayoutState) -> Bool {
        abs(firstSplit - other.firstSplit) < 0.001
            && abs(secondSplit - other.secondSplit) < 0.001
            && abs(halfSplit - other.halfSplit) < 0.001
    }
}

final class StableDocumentSplitView: NSView {
    fileprivate var roleHosts: [WorkspacePaneRole: NSHostingView<AnyView>] = [:]
    fileprivate var emptyHost: NSHostingView<AnyView>?
    fileprivate let dividerViews = [StableDocumentDividerView(), StableDocumentDividerView()]
    fileprivate weak var coordinator: StableDocumentSplitCoordinator?
#if DEBUG
    private let continuityRecorder = PaneContinuityRecorder.configuredFromEnvironment()
#endif

    override var isFlipped: Bool { true }

    func install(
        roleHosts: [WorkspacePaneRole: NSHostingView<AnyView>],
        emptyHost: NSHostingView<AnyView>
    ) {
        precondition(roleHosts.count == WorkspacePaneRole.allCases.count)
        autoresizesSubviews = false
        wantsLayer = true
        layer?.masksToBounds = true
        self.roleHosts = roleHosts
        self.emptyHost = emptyHost
        addSubview(emptyHost)
        for role in WorkspacePaneRole.defaultThreePaneOrder {
            guard let host = roleHosts[role] else { continue }
            host.isHidden = true
            addSubview(host)
        }
        for divider in dividerViews {
            divider.isHidden = true
            addSubview(divider)
        }
        assertStableOwnership()
    }

    func assertStableOwnership() {
        assert(emptyHost?.superview === self)
        assert(roleHosts.values.allSatisfy { $0.superview === self })
        assert(dividerViews.allSatisfy { $0.superview === self })
    }

#if DEBUG
    func recordContinuityTransition(duration: TimeInterval) {
        continuityRecorder?.recordTransition(view: self, duration: duration)
    }

    func continuitySample(recorderID: String, transition: Int, frame: Int) -> PaneContinuitySample {
        let parentID = String(describing: ObjectIdentifier(self))
        let roles = WorkspacePaneRole.allCases.compactMap { role -> PaneContinuityRoleSample? in
            guard let host = roleHosts[role] else { return nil }
            let presentationFrame = host.layer?.presentation()?.frame ?? host.frame
            return PaneContinuityRoleSample(
                role: role.rawValue,
                hostID: String(describing: ObjectIdentifier(host)),
                parentID: host.superview.map { String(describing: ObjectIdentifier($0)) } ?? "none",
                hidden: host.isHidden,
                modelFrame: host.frame,
                presentationFrame: presentationFrame
            )
        }
        return PaneContinuitySample(
            recorderID: recorderID,
            transition: transition,
            frame: frame,
            timestamp: ProcessInfo.processInfo.systemUptime,
            stableOwnership: roles.count == WorkspacePaneRole.allCases.count
                && roles.allSatisfy { $0.parentID == parentID },
            containerBounds: bounds,
            roles: roles
        )
    }
#endif

    override func layout() {
        super.layout()
        coordinator?.containerDidLayout(self)
    }
}

private final class StableDocumentDividerView: NSView {
    var onDragStart: (() -> Void)?
    var onDragChange: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    private var dragStartX: CGFloat?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.splitter)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        dividerFill.setFill()
        bounds.fill()
        dividerLine.setFill()
        NSRect(x: bounds.midX - 0.5, y: bounds.minY + 14, width: 1, height: max(0, bounds.height - 28)).fill()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX else { return }
        onDragChange?(event.locationInWindow.x - dragStartX)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartX = nil
        onDragEnd?()
    }

    private var dividerFill: NSColor {
        if isDarkAppearance {
            return NSColor(calibratedRed: 0.059, green: 0.059, blue: 0.059, alpha: 0.96)
        }
        return NSColor(calibratedRed: 0.955, green: 0.918, blue: 0.835, alpha: 0.96)
    }

    private var dividerLine: NSColor {
        if isDarkAppearance {
            return NSColor(calibratedRed: 0.230, green: 0.200, blue: 0.155, alpha: 0.24)
        }
        return NSColor(calibratedRed: 0.500, green: 0.380, blue: 0.260, alpha: 0.13)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

final class StableDocumentSplitCoordinator {
    var firstSplit: Binding<CGFloat>
    var secondSplit: Binding<CGFloat>
    var halfSplit: Binding<CGFloat>
    var onFramesChange: (([WorkspacePaneRole], [CGRect]) -> Void)?
    var onExpansionRequestHandled: ((UUID) -> Void)?

    private var desiredState: StableDocumentLayoutState?
    private var appliedState: StableDocumentLayoutState?
    private var displayedVisibleOrder: [WorkspacePaneRole] = []
    private var recentReadableWidths: [WorkspacePaneRole: CGFloat] = [:]
    private var lastContainerSize = CGSize.zero
    private var isAnimatingLayout = false
    private var isDraggingDivider = false
    private var isWritingStoredRatios = false
    private var pendingState: StableDocumentLayoutState?
    private var pendingExpansionRequest: PaneExpansionRequest?
    private var handledExpansionRequestID: UUID?
    private var dividerDrag: DividerDrag?
    private var animationSequence = 0
    private var activeAnimationToken: Int?

    private let dividerWidth: CGFloat = 10
    private let railWidth = ContentRailMetrics.railOnlyWidth
    private let railSnapThreshold = ContentRailMetrics.snapThreshold
    private let readableWidthThreshold = ContentRailMetrics.readableWidth
    private let defaultReadableWidth = ContentRailMetrics.defaultReadableWidth
    private let layoutAnimationDuration = 0.24
    private let snapAnimationDuration = 0.18
    private let animationFallbackGrace: TimeInterval = 0.25

    init(
        firstSplit: Binding<CGFloat>,
        secondSplit: Binding<CGFloat>,
        halfSplit: Binding<CGFloat>
    ) {
        self.firstSplit = firstSplit
        self.secondSplit = secondSplit
        self.halfSplit = halfSplit
    }

    func install(in splitView: StableDocumentSplitView) {
        splitView.coordinator = self
        for (index, divider) in splitView.dividerViews.enumerated() {
            divider.onDragStart = { [weak self, weak splitView] in
                guard let self, let splitView else { return }
                self.beginDividerDrag(index: index, in: splitView)
            }
            divider.onDragChange = { [weak self, weak splitView] delta in
                guard let self, let splitView else { return }
                self.updateDividerDrag(delta: delta, in: splitView)
            }
            divider.onDragEnd = { [weak self, weak splitView] in
                guard let self, let splitView else { return }
                self.endDividerDrag(in: splitView)
            }
        }
    }

    func stop(in splitView: StableDocumentSplitView) {
        splitView.coordinator = nil
        for divider in splitView.dividerViews {
            divider.onDragStart = nil
            divider.onDragChange = nil
            divider.onDragEnd = nil
        }
    }

    func update(
        state: StableDocumentLayoutState,
        draggedRole: WorkspacePaneRole?,
        expansionRequest: PaneExpansionRequest?,
        in splitView: StableDocumentSplitView
    ) {
        splitView.assertStableOwnership()
        desiredState = state
        updateDragAppearance(draggedRole, in: splitView)

        if let expansionRequest, expansionRequest.id != handledExpansionRequestID {
            pendingExpansionRequest = expansionRequest
        }

        guard splitView.bounds.width > 0, splitView.bounds.height > 0 else {
            splitView.needsLayout = true
            return
        }

        if isAnimatingLayout || isDraggingDivider {
            pendingState = state
            return
        }

        guard let appliedState else {
            apply(state: state, in: splitView, animated: false, preserveCurrentWidths: false)
            handlePendingExpansionRequest(in: splitView)
            return
        }

        if !state.hasSameStructure(as: appliedState) {
            apply(state: state, in: splitView, animated: true, preserveCurrentWidths: true)
            return
        }

        if isWritingStoredRatios {
            self.appliedState = state
        } else if !state.hasSameStoredRatios(as: appliedState) {
            apply(state: state, in: splitView, animated: false, preserveCurrentWidths: false)
        }
        handlePendingExpansionRequest(in: splitView)
    }

    func containerDidLayout(_ splitView: StableDocumentSplitView) {
        guard splitView.bounds.width > 0, splitView.bounds.height > 0 else { return }
        guard !isAnimatingLayout, !isDraggingDivider else { return }
        let size = splitView.bounds.size
        guard appliedState == nil || abs(size.width - lastContainerSize.width) > 0.5 || abs(size.height - lastContainerSize.height) > 0.5 else { return }
        guard let state = desiredState else { return }
        apply(state: state, in: splitView, animated: false, preserveCurrentWidths: appliedState != nil)
        handlePendingExpansionRequest(in: splitView)
    }

    private func apply(
        state: StableDocumentLayoutState,
        in splitView: StableDocumentSplitView,
        animated: Bool,
        preserveCurrentWidths: Bool
    ) {
        let visibleOrder = state.visibleOrder.filter { state.normalizedOrder.contains($0) }
        let widths = paneWidths(
            for: visibleOrder,
            state: state,
            in: splitView,
            preserveCurrentWidths: preserveCurrentWidths
        )
        let targetFrames = visibleFrames(order: visibleOrder, widths: widths, size: splitView.bounds.size)
        let allTargetFrames = allRoleFrames(
            normalizedOrder: state.normalizedOrder,
            visibleOrder: visibleOrder,
            visibleFrames: targetFrames,
            size: splitView.bounds.size
        )
        let targetDividerFrames = dividerFramesForOrder(
            visibleOrder,
            visibleFrames: targetFrames,
            size: splitView.bounds.size
        )
        let previousVisible = Set(displayedVisibleOrder)
        let nextVisible = Set(visibleOrder)
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        prepareHosts(
            previousVisible: previousVisible,
            nextVisible: nextVisible,
            targetFrames: allTargetFrames,
            in: splitView
        )
        prepareDividers(targetFrames: targetDividerFrames, in: splitView)
        displayedVisibleOrder = visibleOrder
        appliedState = state
        lastContainerSize = splitView.bounds.size

        guard shouldAnimate else {
            setFramesImmediately(
                roleFrames: allTargetFrames,
                dividerFrames: targetDividerFrames,
                visibleOrder: visibleOrder,
                in: splitView
            )
            finishLayout(state: state, in: splitView, saveRatios: animated)
            return
        }

        let animationToken = beginAnimation()
        let finishAnimation = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.completeAnimation(animationToken) {
                self.setFramesImmediately(
                    roleFrames: allTargetFrames,
                    dividerFrames: targetDividerFrames,
                    visibleOrder: visibleOrder,
                    in: splitView
                )
                self.finishLayout(state: state, in: splitView, saveRatios: true)
                self.applyPendingWork(in: splitView)
            }
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = layoutAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            animateFrames(
                roleFrames: allTargetFrames,
                dividerFrames: targetDividerFrames,
                visibleOrder: visibleOrder,
                in: splitView
            )
        }, completionHandler: finishAnimation)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + layoutAnimationDuration + animationFallbackGrace,
            execute: finishAnimation
        )
#if DEBUG
        splitView.recordContinuityTransition(duration: layoutAnimationDuration)
#endif
    }

    private func paneWidths(
        for visibleOrder: [WorkspacePaneRole],
        state: StableDocumentLayoutState,
        in splitView: StableDocumentSplitView,
        preserveCurrentWidths: Bool
    ) -> [CGFloat] {
        let count = visibleOrder.count
        guard count > 0 else { return [] }
        let usable = max(splitView.bounds.width - CGFloat(count - 1) * dividerWidth, 1)
        if count == 1 {
            return [usable]
        }

        if preserveCurrentWidths, appliedState != nil {
            let desired = visibleOrder.map { role -> CGFloat in
                if displayedVisibleOrder.contains(role), let width = splitView.roleHosts[role]?.frame.width, width > 0.5 {
                    return width
                }
                return recentReadableWidths[role] ?? defaultReadableWidth
            }
            return normalizedWidths(desired, total: usable)
        }

        if count == 2 {
            let first = clamped(state.halfSplit * usable, min: minimumPaneWidth(total: usable, count: count), max: usable - minimumPaneWidth(total: usable, count: count))
            return [first, usable - first]
        }

        let minimum = minimumPaneWidth(total: usable, count: count)
        let first = clamped(state.firstSplit * usable, min: minimum, max: usable - 2 * minimum)
        let second = clamped((state.secondSplit - state.firstSplit) * usable, min: minimum, max: usable - first - minimum)
        return [first, second, max(minimum, usable - first - second)]
    }

    private func normalizedWidths(_ desired: [CGFloat], total: CGFloat) -> [CGFloat] {
        guard !desired.isEmpty else { return [] }
        let minimum = minimumPaneWidth(total: total, count: desired.count)
        let minimumTotal = minimum * CGFloat(desired.count)
        let extraAvailable = max(0, total - minimumTotal)
        let extras = desired.map { max(0, $0 - minimum) }
        let extraTotal = extras.reduce(0, +)
        var result = extras.map { extra -> CGFloat in
            if extraTotal > 0.5 {
                return minimum + extraAvailable * extra / extraTotal
            }
            return minimum + extraAvailable / CGFloat(desired.count)
        }
        if let lastIndex = result.indices.last {
            result[lastIndex] += total - result.reduce(0, +)
        }
        return result
    }

    private func minimumPaneWidth(total: CGFloat, count: Int) -> CGFloat {
        min(railWidth, total / CGFloat(max(count, 1)))
    }

    private func visibleFrames(order: [WorkspacePaneRole], widths: [CGFloat], size: CGSize) -> [WorkspacePaneRole: CGRect] {
        var frames: [WorkspacePaneRole: CGRect] = [:]
        var x: CGFloat = 0
        for (index, role) in order.enumerated() {
            let width = widths[safe: index] ?? 0
            frames[role] = CGRect(x: x, y: 0, width: width, height: size.height)
            x += width
            if index < order.count - 1 {
                x += dividerWidth
            }
        }
        return frames
    }

    private func allRoleFrames(
        normalizedOrder: [WorkspacePaneRole],
        visibleOrder: [WorkspacePaneRole],
        visibleFrames: [WorkspacePaneRole: CGRect],
        size: CGSize
    ) -> [WorkspacePaneRole: CGRect] {
        var frames = visibleFrames
        for role in normalizedOrder where visibleFrames[role] == nil {
            frames[role] = collapsedFrame(
                for: role,
                normalizedOrder: normalizedOrder,
                visibleOrder: visibleOrder,
                visibleFrames: visibleFrames,
                size: size
            )
        }
        return frames
    }

    private func collapsedFrame(
        for role: WorkspacePaneRole,
        normalizedOrder: [WorkspacePaneRole],
        visibleOrder: [WorkspacePaneRole],
        visibleFrames: [WorkspacePaneRole: CGRect],
        size: CGSize
    ) -> CGRect {
        guard let roleIndex = normalizedOrder.firstIndex(of: role) else {
            return CGRect(x: size.width, y: 0, width: 0, height: size.height)
        }
        if let nextRole = normalizedOrder.dropFirst(roleIndex + 1).first(where: { visibleOrder.contains($0) }),
           let nextFrame = visibleFrames[nextRole] {
            return CGRect(x: nextFrame.minX, y: 0, width: 0, height: size.height)
        }
        if let previousRole = normalizedOrder[..<roleIndex].reversed().first(where: { visibleOrder.contains($0) }),
           let previousFrame = visibleFrames[previousRole] {
            return CGRect(x: previousFrame.maxX, y: 0, width: 0, height: size.height)
        }
        return CGRect(x: 0, y: 0, width: 0, height: size.height)
    }

    private func prepareHosts(
        previousVisible: Set<WorkspacePaneRole>,
        nextVisible: Set<WorkspacePaneRole>,
        targetFrames: [WorkspacePaneRole: CGRect],
        in splitView: StableDocumentSplitView
    ) {
        for role in nextVisible.subtracting(previousVisible) {
            guard let host = splitView.roleHosts[role], let target = targetFrames[role] else { continue }
            host.frame = CGRect(x: target.minX, y: 0, width: 0, height: target.height)
            host.isHidden = false
        }
        for role in previousVisible.union(nextVisible) {
            splitView.roleHosts[role]?.isHidden = false
        }
        if nextVisible.isEmpty {
            splitView.emptyHost?.isHidden = false
            if previousVisible.isEmpty {
                splitView.emptyHost?.alphaValue = 1
            } else {
                splitView.emptyHost?.alphaValue = 0
            }
        }
    }

    private func prepareDividers(targetFrames: [CGRect], in splitView: StableDocumentSplitView) {
        for (index, divider) in splitView.dividerViews.enumerated() where targetFrames.indices.contains(index) {
            if divider.isHidden {
                let target = targetFrames[index]
                divider.frame = CGRect(x: target.minX, y: 0, width: 0, height: target.height)
                divider.alphaValue = 0
                divider.isHidden = false
            }
        }
    }

    private func setFramesImmediately(
        roleFrames: [WorkspacePaneRole: CGRect],
        dividerFrames: [CGRect],
        visibleOrder: [WorkspacePaneRole],
        in splitView: StableDocumentSplitView
    ) {
        for (role, frame) in roleFrames {
            splitView.roleHosts[role]?.frame = frame
        }
        updateDividerFrames(dividerFrames, animated: false, in: splitView)
        splitView.emptyHost?.frame = splitView.bounds
        splitView.emptyHost?.alphaValue = visibleOrder.isEmpty ? 1 : 0
    }

    private func animateFrames(
        roleFrames: [WorkspacePaneRole: CGRect],
        dividerFrames: [CGRect],
        visibleOrder: [WorkspacePaneRole],
        in splitView: StableDocumentSplitView
    ) {
        for (role, frame) in roleFrames {
            splitView.roleHosts[role]?.animator().frame = frame
        }
        updateDividerFrames(dividerFrames, animated: true, in: splitView)
        splitView.emptyHost?.animator().frame = splitView.bounds
        splitView.emptyHost?.animator().alphaValue = visibleOrder.isEmpty ? 1 : 0
    }

    private func updateDividerFrames(_ frames: [CGRect], animated: Bool, in splitView: StableDocumentSplitView) {
        for (index, divider) in splitView.dividerViews.enumerated() {
            let target = frames[safe: index] ?? collapsedDividerFrame(index: index, frames: frames, size: splitView.bounds.size)
            if animated {
                divider.animator().frame = target
                divider.animator().alphaValue = frames.indices.contains(index) ? 1 : 0
            } else {
                divider.frame = target
                divider.alphaValue = frames.indices.contains(index) ? 1 : 0
            }
        }
    }

    private func collapsedDividerFrame(index: Int, frames: [CGRect], size: CGSize) -> CGRect {
        let x = frames.last?.maxX ?? (index == 0 ? 0 : size.width)
        return CGRect(x: x, y: 0, width: 0, height: size.height)
    }

    private func finishLayout(state: StableDocumentLayoutState, in splitView: StableDocumentSplitView, saveRatios: Bool) {
        splitView.assertStableOwnership()
        let visible = Set(displayedVisibleOrder)
        for role in WorkspacePaneRole.allCases {
            let host = splitView.roleHosts[role]
            host?.isHidden = !visible.contains(role)
            host?.alphaValue = 1
        }
        for (index, divider) in splitView.dividerViews.enumerated() {
            divider.isHidden = index >= max(0, displayedVisibleOrder.count - 1)
            divider.alphaValue = divider.isHidden ? 0 : 1
        }
        splitView.emptyHost?.isHidden = !displayedVisibleOrder.isEmpty
        splitView.emptyHost?.alphaValue = displayedVisibleOrder.isEmpty ? 1 : 0
        captureReadableWidths(in: splitView)
        if saveRatios {
            persistRatios(in: splitView)
        }
        appliedState = StableDocumentLayoutState(
            normalizedOrder: state.normalizedOrder,
            visibleOrder: state.visibleOrder,
            firstSplit: firstSplit.wrappedValue,
            secondSplit: secondSplit.wrappedValue,
            halfSplit: halfSplit.wrappedValue
        )
        reportFrames(in: splitView)
    }

    private func applyPendingWork(in splitView: StableDocumentSplitView) {
        if let pendingState {
            self.pendingState = nil
            if let appliedState, !pendingState.hasSameStructure(as: appliedState) {
                apply(state: pendingState, in: splitView, animated: true, preserveCurrentWidths: true)
                return
            }
            if let appliedState,
               !isWritingStoredRatios,
               !pendingState.hasSameStoredRatios(as: appliedState) {
                apply(state: pendingState, in: splitView, animated: false, preserveCurrentWidths: false)
                return
            }
        }
        handlePendingExpansionRequest(in: splitView)
        splitView.needsLayout = true
    }

    private func updateDragAppearance(_ draggedRole: WorkspacePaneRole?, in splitView: StableDocumentSplitView) {
        for (role, host) in splitView.roleHosts {
            host.alphaValue = role == draggedRole ? 0.08 : 1
        }
    }

    private struct DividerDrag {
        let index: Int
        let baseWidths: [CGFloat]
    }

    private func beginDividerDrag(index: Int, in splitView: StableDocumentSplitView) {
        guard !isAnimatingLayout, displayedVisibleOrder.count > index + 1 else { return }
        let widths = displayedVisibleOrder.compactMap { splitView.roleHosts[$0]?.frame.width }
        guard widths.count == displayedVisibleOrder.count else { return }
        captureReadableWidths(in: splitView)
        dividerDrag = DividerDrag(index: index, baseWidths: widths)
        isDraggingDivider = true
    }

    private func updateDividerDrag(delta: CGFloat, in splitView: StableDocumentSplitView) {
        guard let dividerDrag else { return }
        var widths = dividerDrag.baseWidths
        let leftIndex = dividerDrag.index
        let rightIndex = dividerDrag.index + 1
        let combined = widths[leftIndex] + widths[rightIndex]
        let minimum = minimumPaneWidth(total: combined, count: 2)
        let left = clamped(widths[leftIndex] + delta, min: minimum, max: combined - minimum)
        widths[leftIndex] = left
        widths[rightIndex] = combined - left
        applyVisibleWidthsImmediately(widths, in: splitView)
    }

    private func endDividerDrag(in splitView: StableDocumentSplitView) {
        guard dividerDrag != nil else { return }
        dividerDrag = nil
        isDraggingDivider = false
        let widths = displayedVisibleOrder.compactMap { splitView.roleHosts[$0]?.frame.width }
        let snapped = snappedWidths(widths)
        if zip(widths, snapped).contains(where: { abs($0 - $1) > 0.5 }) {
            animateVisibleWidths(snapped, duration: snapAnimationDuration, in: splitView) { [weak self, weak splitView] in
                guard let self, let splitView else { return }
                self.captureReadableWidths(in: splitView)
                self.persistRatios(in: splitView)
                self.reportFrames(in: splitView)
                self.applyPendingWork(in: splitView)
            }
        } else {
            captureReadableWidths(in: splitView)
            persistRatios(in: splitView)
            reportFrames(in: splitView)
            applyPendingWork(in: splitView)
        }
    }

    private func snappedWidths(_ widths: [CGFloat]) -> [CGFloat] {
        guard widths.count >= 2 else { return widths }
        let snapIndices = widths.indices.filter { widths[$0] <= railSnapThreshold }
        guard !snapIndices.isEmpty else { return widths }
        var target = widths
        for index in snapIndices {
            let released = max(0, widths[index] - railWidth)
            target[index] = min(railWidth, widths[index])
            guard released > 0.5 else { continue }
            let recipients = widths.indices.filter { $0 != index && !snapIndices.contains($0) }
            let recipient = recipients.min { abs($0 - index) < abs($1 - index) }
                ?? widths.indices.filter { $0 != index }.max { widths[$0] < widths[$1] }
            if let recipient {
                target[recipient] += released
            }
        }
        return target
    }

    private func applyVisibleWidthsImmediately(_ widths: [CGFloat], in splitView: StableDocumentSplitView) {
        let frames = visibleFrames(order: displayedVisibleOrder, widths: widths, size: splitView.bounds.size)
        for (role, frame) in frames {
            splitView.roleHosts[role]?.frame = frame
        }
        let dividers = dividerFramesForOrder(displayedVisibleOrder, visibleFrames: frames, size: splitView.bounds.size)
        updateDividerFrames(dividers, animated: false, in: splitView)
        reportFrames(in: splitView)
    }

    private func animateVisibleWidths(
        _ widths: [CGFloat],
        duration: TimeInterval,
        in splitView: StableDocumentSplitView,
        completion: @escaping () -> Void
    ) {
        let frames = visibleFrames(order: displayedVisibleOrder, widths: widths, size: splitView.bounds.size)
        let dividers = dividerFramesForOrder(displayedVisibleOrder, visibleFrames: frames, size: splitView.bounds.size)
        let animationToken = beginAnimation()
        let finishAnimation = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.completeAnimation(animationToken) {
                self.applyVisibleWidthsImmediately(widths, in: splitView)
                completion()
            }
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            for (role, frame) in frames {
                splitView.roleHosts[role]?.animator().frame = frame
            }
            updateDividerFrames(dividers, animated: true, in: splitView)
        }, completionHandler: finishAnimation)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + duration + animationFallbackGrace,
            execute: finishAnimation
        )
    }

    private func beginAnimation() -> Int {
        animationSequence += 1
        activeAnimationToken = animationSequence
        isAnimatingLayout = true
        return animationSequence
    }

    private func completeAnimation(_ token: Int, completion: () -> Void) {
        guard activeAnimationToken == token else { return }
        activeAnimationToken = nil
        isAnimatingLayout = false
        completion()
    }

    private func handlePendingExpansionRequest(in splitView: StableDocumentSplitView) {
        guard !isAnimatingLayout, !isDraggingDivider,
              let request = pendingExpansionRequest,
              request.id != handledExpansionRequestID else { return }
        pendingExpansionRequest = nil
        handledExpansionRequestID = request.id
        guard let requestedIndex = displayedVisibleOrder.firstIndex(of: request.role) else {
            onExpansionRequestHandled?(request.id)
            return
        }
        let widths = displayedVisibleOrder.compactMap { splitView.roleHosts[$0]?.frame.width }
        guard widths.count == displayedVisibleOrder.count else {
            onExpansionRequestHandled?(request.id)
            return
        }
        let target = expandedWidths(widths, requestedIndex: requestedIndex, role: request.role)
        animateVisibleWidths(target, duration: layoutAnimationDuration, in: splitView) { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.captureReadableWidths(in: splitView)
            self.persistRatios(in: splitView)
            self.reportFrames(in: splitView)
            self.onExpansionRequestHandled?(request.id)
            self.applyPendingWork(in: splitView)
        }
    }

    private func expandedWidths(_ widths: [CGFloat], requestedIndex: Int, role: WorkspacePaneRole) -> [CGFloat] {
        guard widths.indices.contains(requestedIndex) else { return widths }
        let total = widths.reduce(0, +)
        let minimum = minimumPaneWidth(total: total, count: widths.count)
        let maxRequested = max(minimum, total - minimum * CGFloat(widths.count - 1))
        let requested = clamped(
            ContentRailPolicy.expansionWidth(recentWidth: recentReadableWidths[role]),
            min: minimum,
            max: maxRequested
        )
        let remaining = max(0, total - requested)
        let otherIndices = widths.indices.filter { $0 != requestedIndex }
        let otherDesired = otherIndices.map { widths[$0] }
        let allocated = normalizedWidths(otherDesired, total: remaining)
        var result = widths
        result[requestedIndex] = requested
        for (offset, index) in otherIndices.enumerated() {
            result[index] = allocated[safe: offset] ?? minimum
        }
        return result
    }

    private func captureReadableWidths(in splitView: StableDocumentSplitView) {
        for role in displayedVisibleOrder {
            guard let width = splitView.roleHosts[role]?.frame.width, width >= readableWidthThreshold else { continue }
            recentReadableWidths[role] = width
        }
    }

    private func persistRatios(in splitView: StableDocumentSplitView) {
        let widths = displayedVisibleOrder.compactMap { splitView.roleHosts[$0]?.frame.width }
        guard widths.count == displayedVisibleOrder.count, widths.count >= 2 else { return }
        let usable = max(widths.reduce(0, +), 1)
        isWritingStoredRatios = true
        if widths.count == 2 {
            halfSplit.wrappedValue = clamped(widths[0] / usable, min: 0, max: 1)
        } else {
            firstSplit.wrappedValue = clamped(widths[0] / usable, min: 0, max: 1)
            secondSplit.wrappedValue = clamped((widths[0] + widths[1]) / usable, min: 0, max: 1)
        }
        DispatchQueue.main.async { [weak self] in
            self?.isWritingStoredRatios = false
        }
    }

    private func reportFrames(in splitView: StableDocumentSplitView) {
        let order = displayedVisibleOrder
        let frames = order.compactMap { splitView.roleHosts[$0]?.frame }
        guard frames.count == order.count else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFramesChange?(order, frames)
        }
    }

    private func dividerFramesForOrder(
        _ order: [WorkspacePaneRole],
        visibleFrames: [WorkspacePaneRole: CGRect],
        size: CGSize
    ) -> [CGRect] {
        order.dropLast().compactMap { role in
            guard let frame = visibleFrames[role] else { return nil }
            return CGRect(x: frame.maxX, y: 0, width: dividerWidth, height: size.height)
        }
    }

    private func clamped(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), Swift.max(min, max))
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
