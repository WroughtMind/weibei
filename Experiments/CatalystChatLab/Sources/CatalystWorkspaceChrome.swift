import UIKit
import SwiftUI
import WeiBeiCore

/// Keeps each original SwiftUI pane and its editor/controller alive when moving between layouts.
final class CatalystHostingView: UIView {
    let controller: UIHostingController<AnyView>
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
        super.layoutSubviews()
        controller.view.frame = bounds
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
    func attach(_ role: WorkspacePaneRole, to container: UIView, store: WorkspaceStore) -> OwnerToken {
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
        override func didMoveToWindow() { super.didMoveToWindow(); onAttachment?() }
    }
    final class Coordinator {
        var owner: OwnerToken?
        var registry: PersistentPaneHostRegistry?
        func attach(_ role: WorkspacePaneRole, registry: PersistentPaneHostRegistry, store: WorkspaceStore, view: UIView) {
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
        for divider in view.dividerViews { divider.appearanceMode = appearanceMode; divider.reduceMotion = reduceMotion }
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
    var appearanceMode: WeiBeiAppearanceMode = .paper { didSet { setNeedsDisplay() } }
    var reduceMotion = false
    private var hovering = false
    private var pressed = false
    private let accent = CALayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "调整分栏宽度"
        accessibilityTraits = .adjustable
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
        accent.opacity = 0; layer.addSublayer(accent)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began: pressed = true; updateAccent(); onDragStart?()
        case .changed: onDragChange?(gesture.translation(in: superview).x)
        case .ended, .cancelled: pressed = false; updateAccent(); onDragEnd?()
        default: break
        }
    }
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
        private let panelWidth = WeiBeiMetric.courseDrawerWidth
        override init(frame: CGRect) {
            super.init(frame: frame)
            scrim.alpha = 0; scrim.isUserInteractionEnabled = false
            material.isUserInteractionEnabled = false
            addSubview(scrim); addSubview(panel); panel.addSubview(material)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { open && point.x <= panelWidth && bounds.contains(point) }
        override func layoutSubviews() {
            super.layoutSubviews()
            scrim.frame = bounds
            panel.frame = CGRect(x: open ? 0 : -panelWidth, y: 0, width: panelWidth, height: bounds.height)
            material.frame = panel.bounds; host?.frame = panel.bounds
        }
        func apply(open: Bool, store: WorkspaceStore, dismiss: @escaping () -> Void) {
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
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { view.mode = appearanceMode; view.configure() }
    final class Probe: UIView {
        var mode: WeiBeiAppearanceMode = .paper
        override func didMoveToWindow() { super.didMoveToWindow(); configure() }
        func configure() {
            CatalystDesktopWindow.configure(mode: mode)
            guard let window, let scene = window.windowScene else { return }
            scene.titlebar?.titleVisibility = .hidden
            scene.titlebar?.toolbar = nil
            scene.titlebar?.separatorStyle = .none
            scene.sizeRestrictions?.minimumSize = CGSize(width: 520, height: 720)
            window.isOpaque = !mode.isGlass
            window.backgroundColor = WeiBeiNativePalette.paper(for: mode)
            window.rootViewController?.view.backgroundColor = .clear
            window.overrideUserInterfaceStyle = mode.isDark ? .dark : .light
        }
    }
}

// SwiftUI's Mac Catalyst sheet is hosted in a separate UIKit window.
struct CatalystSheetBackground: UIViewRepresentable {
    let color: UIColor
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.color = color; view.configure() }
    final class Probe: UIView {
        var color = UIColor.clear
        override func didMoveToWindow() { super.didMoveToWindow(); configure() }
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
        }
    }
}
