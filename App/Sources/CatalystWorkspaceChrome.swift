import UIKit
import SwiftUI
import WeiBeiCore

/// The shared pane container owns the transition inside the original toolbar.
@MainActor func configurePaneTopScrollEdges(in view: UIView) {
    if #available(iOS 26.0, *), let scroll = view as? UIScrollView {
        // WebKit tracks its temporary hiding separately from the client's
        // setting. Always register ours, even when the effect is hidden now.
        scroll.topEdgeEffect.isHidden = true
        // The outer viewport owns the window edge. Nested HTML scrollers
        // belong to WebKit and may be created after this view is configured.
        return
    }
    for child in view.subviews { configurePaneTopScrollEdges(in: child) }
}

/// Native toolbar items own their hit regions; drawing controls under a hidden
/// titlebar leaves AppKit's window double-click handling over those controls.
struct CatalystTopBar: UIViewControllerRepresentable {
    let leading: AnyView
    let center: AnyView
    let trailing: AnyView
    let overflowMenus: [UIMenu]
    let isVisible: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update([leading, center, trailing], menus: overflowMenus, isVisible: isVisible)
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.detach()
    }

    final class Controller: UIViewController, NSToolbarDelegate {
        private let identifiers = ["weibei.navigation", "weibei.panes", "weibei.actions"].map { NSToolbarItem.Identifier($0) }
        private let hosts = (0..<3).map { _ in
            UIHostingConfiguration { AnyView(EmptyView()) }.margins(.all, 0).makeContentView()
        }
        private let toolbar = NSToolbar(identifier: "weibei.workspace")
        private var menus = (0..<3).map { _ in UIMenu(children: []) }
        private weak var scene: UIWindowScene?
        private var showsToolbar = true

        override func loadView() {
            let probe = Probe()
            probe.changed = { [weak self] in self?.attach() }
            view = probe
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.centeredItemIdentifiers = [identifiers[1]]
            for host in hosts {
                host.backgroundColor = .clear
            }
        }

        func update(_ contents: [AnyView], menus: [UIMenu], isVisible: Bool) {
            loadViewIfNeeded()
            self.menus = menus
            for (host, content) in zip(hosts, contents) {
                host.configuration = UIHostingConfiguration { content }.margins(.all, 0)
                host.invalidateIntrinsicContentSize()
            }
            for item in toolbar.items {
                guard let index = identifiers.firstIndex(of: item.itemIdentifier) else { continue }
                item.label = menus[index].title
                item.itemMenuFormRepresentation = menus[index]
            }
            showsToolbar = isVisible
            attach()
        }

        private func attach() {
            guard let next = view.window?.windowScene else { return }
            if scene !== next { detach(); scene = next }
            next.titlebar?.toolbarStyle = .unifiedCompact
            next.titlebar?.autoHidesToolbarInFullScreen = false
            let desired = showsToolbar ? toolbar : nil
            if next.titlebar?.toolbar !== desired { next.titlebar?.toolbar = desired }
        }

        func detach() {
            if scene?.titlebar?.toolbar === toolbar { scene?.titlebar?.toolbar = nil }
            scene = nil
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            identifiers + [.flexibleSpace]
        }
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [identifiers[0], .flexibleSpace, identifiers[1], .flexibleSpace, identifiers[2]]
        }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            guard let index = identifiers.firstIndex(of: identifier) else { return nil }
            let item = NSUIViewToolbarItem(itemIdentifier: identifier, uiView: hosts[index])
            // The hosted SwiftUI buttons own their individual enabled states.
            // This container has no target/action for AppKit to validate.
            item.autovalidates = false
            item.isEnabled = true
            item.isBordered = false
            if index == 2 { item.visibilityPriority = .high }
            item.label = menus[index].title
            item.itemMenuFormRepresentation = menus[index]
            return item
        }

        private final class Probe: UIView {
            var changed: (() -> Void)?
            override func didMoveToWindow() { super.didMoveToWindow(); changed?() }
        }
    }
}

/// Keeps each original SwiftUI pane and its editor/controller alive when moving between layouts.
final class CatalystHostingView: UIView {
    let controller: UIHostingController<AnyView>
#if WEIBEI_ACCEPTANCE_CHECKS
    /// Acceptance harness only: main-thread time of each layout pass of this host.
    var layoutTiming: ((TimeInterval) -> Void)?
#endif
    init<Content: View>(_ root: Content) {
        controller = UIHostingController(rootView: AnyView(root))
        super.init(frame: .zero)
        controller.view.backgroundColor = .clear
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(controller.view)
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
#if WEIBEI_ACCEPTANCE_CHECKS
        let started = layoutTiming == nil ? 0 : CACurrentMediaTime()
        super.layoutSubviews()
        controller.view.frame = bounds
        if let layoutTiming {
            controller.view.layoutIfNeeded()
            layoutTiming(CACurrentMediaTime() - started)
        }
#else
        super.layoutSubviews()
        controller.view.frame = bounds
#endif
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        var responder = next
        while let value = responder, !(value is UIViewController) { responder = value.next }
        let parent = window == nil ? nil : responder as? UIViewController
        guard controller.parent !== parent else { return }
        controller.willMove(toParent: nil)
        controller.removeFromParent()
        if let parent {
            parent.addChild(controller)
            controller.didMove(toParent: parent)
        }
    }
}

final class PersistentPaneHostRegistry: ObservableObject {
    private var hosts: [WorkspacePaneRole: CatalystHostingView] = [:]
    private var owners: [WorkspacePaneRole: OwnerToken] = [:]
    private var sequence = 0
    @MainActor func attach(_ role: WorkspacePaneRole, to container: UIView, store: WorkspaceStore) -> OwnerToken {
        sequence += 1
        let owner = OwnerToken(role: role, generation: sequence)
        owners[role] = owner
        let host: CatalystHostingView
        if let resident = hosts[role] { host = resident }
        else {
            host = CatalystHostingView(PersistentPaneRoot(role: role)
                .environmentObject(store).environmentObject(store.paneState)
                .environmentObject(store.interaction).environmentObject(store.threePaneReorder)
                .environmentObject(store.libraryDrawer))
            host.accessibilityIdentifier = "persistent-pane-\(role.rawValue)"
            hosts[role] = host
        }
        if host.superview !== container {
            host.removeFromSuperview()
            host.frame = container.bounds
            host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(host)
        }
        return owner
    }
    func detach(_ owner: OwnerToken, from container: UIView) {
        guard owners[owner.role] == owner, let host = hosts[owner.role], host.superview === container else { return }
        host.removeFromSuperview()
        owners[owner.role] = nil
    }
}

struct PersistentPaneHost: UIViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    let role: WorkspacePaneRole
    let registry: PersistentPaneHostRegistry
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Container {
        let view = Container()
        view.onAttachment = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            if view.window != nil { coordinator.attach(role, registry: registry, store: store, view: view) }
            else { coordinator.detach(view) }
        }
        return view
    }
    func updateUIView(_ view: Container, context: Context) {
        view.isHidden = store.courseWorkspacePresented
        if view.window != nil { context.coordinator.attach(role, registry: registry, store: store, view: view) }
    }
    static func dismantleUIView(_ view: Container, coordinator: Coordinator) {
        view.onAttachment = nil
        coordinator.detach(view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Container, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }
    final class Container: UIView {
        var onAttachment: (() -> Void)?
        private let toolbarFade = CAGradientLayer()
        override func didMoveToWindow() { super.didMoveToWindow(); onAttachment?() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window, window.windowScene?.titlebar?.toolbar != nil, bounds.height > 0 else {
                layer.mask = nil
                return
            }
            let top = max(0, window.safeAreaInsets.top - convert(bounds, to: window).minY)
            guard top > 0 else { layer.mask = nil; return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            toolbarFade.frame = bounds
            toolbarFade.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
            toolbarFade.locations = [0, NSNumber(value: Double(top * 0.25 / bounds.height)),
                                    NSNumber(value: Double(min(top / bounds.height, 1))), 1]
            layer.mask = toolbarFade
            CATransaction.commit()
        }
    }
    final class Coordinator {
        var owner: OwnerToken?
        var registry: PersistentPaneHostRegistry?
        @MainActor func attach(_ role: WorkspacePaneRole, registry: PersistentPaneHostRegistry, store: WorkspaceStore, view: UIView) {
            guard owner?.role != role || self.registry !== registry else { return }
            detach(view)
            self.registry = registry
            owner = registry.attach(role, to: view, store: store)
        }
        func detach(_ view: UIView) {
            if let owner { registry?.detach(owner, from: view) }
            owner = nil
        }
    }
}

struct StableDocumentWorkspace: UIViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Binding var firstSplit: CGFloat
    @Binding var secondSplit: CGFloat
    @Binding var halfSplit: CGFloat
    let registry: PersistentPaneHostRegistry
    let normalizedOrder: [WorkspacePaneRole]
    let visibleOrder: [WorkspacePaneRole]
    let draggedRole: WorkspacePaneRole?
    let expansionRequest: PaneExpansionRequest?
    let appearanceMode: WeiBeiAppearanceMode
    let onFramesChange: ([WorkspacePaneRole], [CGRect]) -> Void
    let onExpansionRequestHandled: (UUID) -> Void
    func makeCoordinator() -> StableDocumentSplitCoordinator {
        StableDocumentSplitCoordinator(firstSplit: $firstSplit, secondSplit: $secondSplit, halfSplit: $halfSplit)
    }
    func makeUIView(context: Context) -> StableDocumentSplitView {
        let view = StableDocumentSplitView()
        for role in WorkspacePaneRole.allCases {
            let host = CatalystHostingView(PersistentPaneHost(role: role, registry: registry)
                .ignoresSafeArea(.container, edges: .top)
                .environmentObject(store).environmentObject(store.paneState)
                .environmentObject(store.interaction).environmentObject(store.threePaneReorder)
                .environmentObject(store.libraryDrawer).weiBeiMotionScoped())
            host.isHidden = true
            view.roleHosts[role] = host
            view.addSubview(host)
        }
        let empty = CatalystHostingView(EmptyWorkspaceLauncherView()
            .environmentObject(store).environmentObject(store.paneState)
            .environmentObject(store.interaction).environmentObject(store.libraryDrawer).weiBeiMotionScoped())
        view.emptyHost = empty
        view.insertSubview(empty, at: 0)
        view.dividerViews.forEach(view.addSubview)
        context.coordinator.install(in: view)
        updateUIView(view, context: context)
        return view
    }
    func updateUIView(_ view: StableDocumentSplitView, context: Context) {
        view.backgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)
        let coordinator = context.coordinator
        coordinator.firstSplit = $firstSplit; coordinator.secondSplit = $secondSplit; coordinator.halfSplit = $halfSplit
        coordinator.onFramesChange = onFramesChange
        coordinator.onExpansionRequestHandled = onExpansionRequestHandled
        coordinator.reduceMotion = reduceMotion
        for divider in view.dividerViews {
            divider.appearanceMode = appearanceMode
            divider.reduceMotion = reduceMotion
            divider.interfaceLanguage = store.interfaceLanguage
        }
        coordinator.update(state: StableDocumentLayoutState(normalizedOrder: WorkspacePaneRole.normalized(normalizedOrder),
            visibleOrder: visibleOrder, firstSplit: firstSplit, secondSplit: secondSplit, halfSplit: halfSplit),
            draggedRole: draggedRole, expansionRequest: expansionRequest, in: view)
    }
    static func dismantleUIView(_ view: StableDocumentSplitView, coordinator: StableDocumentSplitCoordinator) { coordinator.stop(in: view) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StableDocumentSplitView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }
}

final class StableDocumentSplitView: UIView {
    var roleHosts: [WorkspacePaneRole: CatalystHostingView] = [:]
    var emptyHost: CatalystHostingView?
    let dividerViews = [CatalystDividerView(), CatalystDividerView()]
    weak var coordinator: StableDocumentSplitCoordinator?
    override func layoutSubviews() { super.layoutSubviews(); coordinator?.containerDidLayout(self) }
    func assertStableOwnership() {
        assert(emptyHost?.superview === self)
        assert(roleHosts.values.allSatisfy { $0.superview === self })
        assert(dividerViews.allSatisfy { $0.superview === self })
    }
}

final class CatalystDividerView: UIView {
    var onDragStart: (() -> Void)?
    var onDragChange: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onEqualize: (() -> Void)?
    var skipSnap = false
    var appearanceMode: WeiBeiAppearanceMode = .paper { didSet { setNeedsDisplay() } }
    var reduceMotion = false
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese {
        didSet {
            guard interfaceLanguage != oldValue else { return }
            refreshCopy()
        }
    }
    private var hovering = false
    private var pressed = false
    private let accent = CALayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        refreshCopy()
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(equalize))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
        accent.opacity = 0; layer.addSublayer(accent)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func refreshCopy() {
        accessibilityLabel = interfaceLanguage.text("调整分栏宽度", "Resize panes")
        accessibilityHint = interfaceLanguage.text("双击均分相邻两栏；按住 Option 松手可跳过吸附。", "Double-click to split the adjacent panes evenly. Hold Option while releasing to skip snapping.")
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: interfaceLanguage.text("均分相邻两栏", "Split adjacent panes evenly"), target: self, selector: #selector(equalize))]
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        skipSnap = gesture.modifierFlags.contains(.alternate) || gesture.state == .cancelled
        switch gesture.state {
        case .began: pressed = true; updateAccent(); onDragStart?()
        case .changed: onDragChange?(gesture.translation(in: superview).x)
        case .ended, .cancelled:
            if gesture.state == .ended { onDragChange?(gesture.translation(in: superview).x) }
            pressed = false; updateAccent(); onDragEnd?(); skipSnap = false
        default: break
        }
    }
    @objc private func equalize() -> Bool { onEqualize?(); return true }
    override func accessibilityIncrement() { onDragStart?(); onDragChange?(40); onDragEnd?() }
    override func accessibilityDecrement() { onDragStart?(); onDragChange?(-40); onDragEnd?() }
    override func draw(_ rect: CGRect) {
        WeiBeiNativePalette.dividerFill(for: appearanceMode).setFill()
        UIRectFill(bounds)
        WeiBeiNativePalette.dividerLine(for: appearanceMode).setFill()
        UIRectFill(CGRect(x: bounds.midX - 0.5, y: 14, width: 1, height: max(0, bounds.height - 28)))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        refreshCopy()
        accent.frame = CGRect(x: bounds.midX - 0.5, y: 14, width: 1, height: max(0, bounds.height - 28))
        accent.backgroundColor = WeiBeiNativePalette.cinnabar(for: appearanceMode).cgColor
    }
    @objc private func hover(_ recognizer: UIHoverGestureRecognizer) {
        let inside = recognizer.state == .began || recognizer.state == .changed
        if inside != hovering {
            if inside { CatalystDesktopWindow.shared.pushCursor("resizeLeftRight") }
            else { CatalystDesktopWindow.shared.popCursor() }
        }
        hovering = inside
        updateAccent()
    }
    private func updateAccent() {
        let opacity: Float = pressed ? 1 : (hovering ? 0.55 : 0)
        guard opacity != accent.opacity else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = accent.presentation()?.opacity ?? accent.opacity
        animation.toValue = opacity
        animation.duration = opacity == 0 ? 0.14 : 0.08
        accent.opacity = opacity
        if !reduceMotion { accent.add(animation, forKey: "weiBeiAccentOpacity") }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil, hovering { CatalystDesktopWindow.shared.popCursor(); hovering = false }
    }
}

struct WindowFullScreenReader: UIViewRepresentable {
    @Binding var isFullScreen: Bool
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.changed = { value in if isFullScreen != value { isFullScreen = value } }
    }
    final class Probe: UIView {
        var changed: ((Bool) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let scene = window?.windowScene else { return }
            let value = scene.isFullScreen
            DispatchQueue.main.async { [weak self] in self?.changed?(value) }
        }
    }
}


struct CourseDrawerHost: UIViewRepresentable {
    @ObservedObject var drawer: LibraryDrawerState
    let store: WorkspaceStore
    var onDismiss: () -> Void
    func makeUIView(context: Context) -> Drawer { Drawer() }
    func updateUIView(_ view: Drawer, context: Context) { view.apply(open: drawer.isOpen, store: store, dismiss: onDismiss) }
    final class Drawer: UIView {
        private let scrim = UIView()
        private let panel = UIView()
        private let material = UIVisualEffectView()
        var host: CatalystHostingView?
        var model: CourseSidebarModel?
        var open = false
        var onDismiss: (() -> Void)?
        private let panelWidth = WeiBeiMetric.courseDrawerWidth
        override init(frame: CGRect) {
            super.init(frame: frame)
            scrim.alpha = 0
            scrim.isUserInteractionEnabled = true
            scrim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeFromScrim)))
            material.isUserInteractionEnabled = false
            addSubview(scrim); addSubview(panel); panel.addSubview(material)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { open && bounds.contains(point) }
        @objc private func closeFromScrim() { onDismiss?() }
        override func layoutSubviews() {
            super.layoutSubviews()
            scrim.frame = bounds
            panel.frame = CGRect(x: open ? 0 : -panelWidth, y: 0, width: panelWidth, height: bounds.height)
            material.frame = panel.bounds; host?.frame = panel.bounds
        }
        func apply(open: Bool, store: WorkspaceStore, dismiss: @escaping () -> Void) {
            onDismiss = dismiss
            if open, host == nil {
                let model = CourseSidebarModel(store: store)
                self.model = model
                let host = CatalystHostingView(CourseImmersiveDrawerView(store: store, model: model, dismiss: dismiss)
                    .weiBeiMotionScoped(preference: store.motionPreference))
                host.backgroundColor = WeiBeiNativePalette.drawerSurface(for: store.appearanceMode)
                host.frame = panel.bounds
                self.host = host
                panel.addSubview(host)
            }
            let mode = store.appearanceMode
            panel.backgroundColor = WeiBeiNativePalette.drawerSurface(for: mode)
            host?.backgroundColor = .clear
            material.effect = mode.isGlass ? UIBlurEffect(style: mode.isDark ? .systemMaterialDark : .systemMaterialLight) : nil
            material.alpha = 0.55
            switch mode {
            case .paper, .xuan: scrim.backgroundColor = WeiBeiNativePalette.ink(for: mode).withAlphaComponent(mode == .xuan ? 0.030 : 0.035)
            case .glassLight, .glassMist: scrim.backgroundColor = UIColor.black.withAlphaComponent(0.10)
            case .stele: scrim.backgroundColor = UIColor.black.withAlphaComponent(0.22)
            default: scrim.backgroundColor = UIColor.black.withAlphaComponent(0.18)
            }
            guard self.open != open else { return }
            self.open = open
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.panel.frame.origin.x = open ? 0 : -self.panelWidth
                self.scrim.alpha = open ? 1 : 0
            } completion: { [weak self] _ in
                guard let self, !self.open else { return }
                self.model?.stop(); self.model = nil
                self.host?.removeFromSuperview(); self.host = nil
            }
        }
    }
}

struct HoverPassThroughRegion: UIViewRepresentable {
    var onHoverChange: (Bool) -> Void
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.changed = onHoverChange }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }
    final class Probe: UIView, UIGestureRecognizerDelegate {
        var changed: ((Bool) -> Void)?
        private weak var observedView: UIView?
        private var inside = false
        private lazy var hover = UIHoverGestureRecognizer(target: self, action: #selector(moved(_:)))
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard window != nil else { return }
            // The owning content view receives hover for its descendants and
            // follows this pane's lifetime, including the initially empty pane.
            var responder = next
            while let value = responder, !(value is UIViewController) { responder = value.next }
            observedView = (responder as? UIViewController)?.view
            hover.cancelsTouchesInView = false
            hover.delegate = self
            observedView?.addGestureRecognizer(hover)
        }
        func detach() {
            observedView?.removeGestureRecognizer(hover); observedView = nil
            if inside { inside = false; changed?(false) }
        }
        @objc private func moved(_ recognizer: UIHoverGestureRecognizer) {
            let next = recognizer.state != .ended && recognizer.state != .cancelled
                && window != nil && bounds.contains(recognizer.location(in: self))
            guard next != inside else { return }
            inside = next; changed?(next)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

struct CatalystWindowChrome: UIViewRepresentable {
    let appearanceMode: WeiBeiAppearanceMode
    var initialSize = CGSize(width: 1240, height: 792)
    var minimumSize = CGSize(width: 520, height: 560)
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.initialSize = initialSize
        view.minimumSize = minimumSize
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Probe, context: Context) {
        view.mode = appearanceMode
        view.minimumSize = minimumSize
        view.configure()
    }
    final class Probe: UIView {
        var mode: WeiBeiAppearanceMode = .paper
        var initialSize = CGSize.zero
        var minimumSize = CGSize(width: 520, height: 560)
        override func didMoveToWindow() { super.didMoveToWindow(); configure() }
        func configure() {
            CatalystDesktopWindow.configure(mode: mode)
            guard let window, let scene = window.windowScene else { return }
            scene.titlebar?.titleVisibility = .hidden
            scene.titlebar?.separatorStyle = .none
            scene.sizeRestrictions?.minimumSize = minimumSize
            let initialSizeKey = "weibeiInitialWindowSizeApplied"
            if scene.session.userInfo?[initialSizeKey] as? Bool != true {
                var info = scene.session.userInfo ?? [:]
                info[initialSizeKey] = true
                scene.session.userInfo = info
                var frame = scene.effectiveGeometry.systemFrame
                if frame.isNull || frame.isEmpty { frame = scene.screen.bounds }
                let size = CGSize(width: min(initialSize.width, scene.screen.bounds.width),
                                  height: min(initialSize.height, scene.screen.bounds.height))
                frame = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                               width: size.width, height: size.height)
                // A geometry request sets the opening frame, not permanent min/max constraints.
                scene.requestGeometryUpdate(.Mac(systemFrame: frame)) { error in
                    WeiBeiLog.workspace.error("Initial window geometry request failed: \(WeiBeiLog.code(error), privacy: .public)")
                }
            }
            window.isOpaque = !mode.isGlass
            window.backgroundColor = WeiBeiNativePalette.paper(for: mode)
            // A nonzero root surface keeps Catalyst pointer events in transparent gaps.
            window.rootViewController?.view.backgroundColor = UIColor(white: 0, alpha: 1.0 / 255)
            window.overrideUserInterfaceStyle = mode.isDark ? .dark : .light
        }
    }
}

// SwiftUI's Mac Catalyst sheet is hosted in a separate UIKit window.
struct CatalystIndependentSheetFitting: ViewModifier {
    let color: UIColor
    @State private var contentSize = CGSize.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                contentSize = size
            }
            .background(CatalystIndependentSheetSizingProbe(
                color: color,
                contentSize: contentSize
            ))
    }
}

struct CatalystIndependentSheetSizingProbe: UIViewRepresentable {
    let color: UIColor
    var contentSize: CGSize?

    init(color: UIColor, contentSize: CGSize? = nil) {
        self.color = color
        self.contentSize = contentSize
    }

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ view: Probe, context: Context) {
        view.color = color
        view.contentSize = contentSize
        view.configure()
    }

    final class Probe: UIView {
        var color = UIColor.clear
        var contentSize: CGSize?
        private var lastGeometryRequestSignature: String?

        override func didMoveToWindow() { super.didMoveToWindow(); configure() }
        override func layoutSubviews() { super.layoutSubviews(); configure() }

        func configure() {
            guard let window else { return }
            window.backgroundColor = color
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController {
                    controller.view.backgroundColor = color
                }
                responder = current.next
            }
            guard let contentSize else { return }
            resizeSheetIfNeeded(window: window, targetSize: contentSize)
        }

        private func resizeSheetIfNeeded(window: UIWindow, targetSize: CGSize) {
            guard targetSize.width.isFinite, targetSize.height.isFinite,
                  targetSize.width > 0, targetSize.height > 0,
                  !Self.sameSize(window.bounds.size, targetSize),
                  let scene = window.windowScene else { return }
            let sourceFrame = scene.effectiveGeometry.systemFrame
            let rootedWindows = scene.windows.filter { $0.rootViewController != nil }
            guard Self.sameSize(sourceFrame.size, window.bounds.size),
                  rootedWindows.count == 1,
                  rootedWindows[0] === window else { return }
            let targetFrame = Self.centeredFrame(size: targetSize, in: sourceFrame)
            let signature = "\(sourceFrame)|\(targetFrame)"
            guard signature != lastGeometryRequestSignature else { return }
            lastGeometryRequestSignature = signature
            DispatchQueue.main.async { [weak self, weak window, weak scene] in
                guard let self else { return }
                guard let window, let scene, window.windowScene === scene else {
                    self.clearGeometryRequest(signature)
                    return
                }
                self.requestGeometryUpdate(
                    window: window,
                    scene: scene,
                    targetSize: targetSize,
                    signature: signature
                )
            }
        }

        private func requestGeometryUpdate(
            window: UIWindow,
            scene: UIWindowScene,
            targetSize: CGSize,
            signature: String
        ) {
            guard self.window === window,
                  let contentSize,
                  Self.sameSize(contentSize, targetSize) else {
                clearGeometryRequest(signature)
                return
            }
            let sourceFrame = scene.effectiveGeometry.systemFrame
            let rootedWindows = scene.windows.filter { $0.rootViewController != nil }
            guard !Self.sameSize(window.bounds.size, targetSize),
                  Self.sameSize(sourceFrame.size, window.bounds.size),
                  rootedWindows.count == 1,
                  rootedWindows[0] === window else {
                clearGeometryRequest(signature)
                return
            }
            let targetFrame = Self.centeredFrame(size: targetSize, in: sourceFrame)
            scene.requestGeometryUpdate(.Mac(systemFrame: targetFrame)) { [weak self] _ in
                self?.clearGeometryRequest(signature)
            }
            DispatchQueue.main.async { [weak self, weak window, weak scene] in
                guard let self, let window, let scene else { return }
                self.synchronizeWindowWithSceneIfNeeded(
                    window: window,
                    scene: scene,
                    targetSize: targetSize
                )
            }
        }

        private func synchronizeWindowWithSceneIfNeeded(
            window: UIWindow,
            scene: UIWindowScene,
            targetSize: CGSize
        ) {
            let effectiveFrame = scene.effectiveGeometry.systemFrame
            let rootedWindows = scene.windows.filter { $0.rootViewController != nil }
            guard self.window === window,
                  window.windowScene === scene,
                  rootedWindows.count == 1,
                  rootedWindows[0] === window,
                  Self.sameSize(effectiveFrame.size, targetSize),
                  let rootViewController = window.rootViewController,
                  let presentationController = rootViewController.presentationController,
                  presentationController.presentedViewController === rootViewController,
                  let containerView = presentationController.containerView else { return }
            rootViewController.preferredContentSize = targetSize
            presentationController.preferredContentSizeDidChange(
                forChildContentContainer: rootViewController
            )
            containerView.setNeedsLayout()
            containerView.layoutIfNeeded()
            DispatchQueue.main.async { [weak self, weak window, weak scene] in
                guard let self, let window, let scene,
                      self.window === window,
                      window.windowScene === scene else { return }
                guard let contentSize,
                      !Self.sameSize(contentSize, targetSize) else { return }
                self.configure()
            }
        }

        private func clearGeometryRequest(_ signature: String) {
            if lastGeometryRequestSignature == signature {
                lastGeometryRequestSignature = nil
            }
        }

        private static func sameSize(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
            abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
        }

        private static func centeredFrame(size: CGSize, in frame: CGRect) -> CGRect {
            CGRect(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

    }
}
