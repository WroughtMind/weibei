import AppKit
import SwiftUI

/// AppKit-hosted course drawer.
///
/// Why AppKit:
/// 1. `NSAnimationContext` starts the slide on the next CA transaction — no wait for
///    SwiftUI to re-layout reader/agent/notes.
/// 2. Sidebar content exists only while open, so pane toggles cannot re-render a
///    hidden course tree after the drawer closes.
struct CourseDrawerHost: NSViewRepresentable {
    @ObservedObject var drawer: LibraryDrawerState
    let store: WorkspaceStore
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> CourseDrawerContainerView {
        let view = CourseDrawerContainerView()
        view.onDismiss = { [weak coordinator = context.coordinator] in
            coordinator?.onDismiss()
        }
        context.coordinator.container = view
        view.apply(isOpen: drawer.isOpen, store: store, animated: false)
        return view
    }

    func updateNSView(_ nsView: CourseDrawerContainerView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        nsView.onDismiss = { [weak coordinator = context.coordinator] in
            coordinator?.onDismiss()
        }
        nsView.apply(isOpen: drawer.isOpen, store: store, animated: true)
    }

    final class Coordinator {
        var onDismiss: () -> Void
        weak var container: CourseDrawerContainerView?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
    }
}

final class CourseDrawerContainerView: NSView {
    static let panelWidth: CGFloat = 292

    var onDismiss: (() -> Void)?

    private let scrim = NSView()
    private let panel = NSView()
    private let panelMaterial = NSVisualEffectView()
    private var hostingView: NSHostingView<AnyView>?
    private var sidebarModel: CourseSidebarModel?
    private var isOpen = false
    private var transitionGeneration = 0

    var sidebarModelForTesting: CourseSidebarModel? { sidebarModel }
    var activeSidebarHostCountForTesting: Int { hostingView == nil ? 0 : 1 }
    var glassMaterialVisibleForTesting: Bool { !panelMaterial.isHidden }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        scrim.wantsLayer = true
        // Soft paper wash — never pure black (that caused the first-open flash).
        scrim.layer?.backgroundColor = Self.scrimColor(for: .paper).cgColor
        scrim.alphaValue = 0
        scrim.isHidden = true

        panel.wantsLayer = true
        panel.layer?.backgroundColor = Self.panelPaperColor(for: .paper).cgColor
        panel.frame = CGRect(x: -Self.panelWidth, y: 0, width: Self.panelWidth, height: 100)

        panelMaterial.blendingMode = .withinWindow
        panelMaterial.material = .sidebar
        panelMaterial.state = .active
        panelMaterial.alphaValue = 0.55
        panelMaterial.isHidden = true
        panel.addSubview(panelMaterial)

        addSubview(scrim)
        addSubview(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrim.frame = bounds
        let height = max(bounds.height, 1)
        panel.frame = CGRect(
            x: panel.frame.minX,
            y: 0,
            width: Self.panelWidth,
            height: height
        )
        panelMaterial.frame = panel.bounds
        hostingView?.frame = panel.bounds
    }

    /// Critical: when closed (or outside the panel), pass events through to split-view dividers
    /// so resize cursors and drag-resize keep working under this full-frame host.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isOpen else { return nil }
        let local = convert(point, from: nil)
        // Only the drawer panel captures hits; the rest of the window stays interactive.
        let panelPoint = panel.convert(local, from: self)
        if panel.bounds.contains(panelPoint) {
            return panel.hitTest(panelPoint) ?? panel
        }
        return nil
    }

    func apply(isOpen open: Bool, store: WorkspaceStore, animated: Bool) {
        applyPaperChrome(for: store.appearanceMode)
        if open, store.appearanceMode.isGlass {
            panelMaterial.isHidden = false
        }

        if open {
            installHostingIfNeeded(store: store)
            startSlide(open: true, animated: animated)
        } else {
            startSlide(open: false, animated: animated)
        }
    }

    private func applyPaperChrome(for mode: WeiBeiAppearanceMode) {
        let paper = Self.panelPaperColor(for: mode)
        panel.layer?.backgroundColor = paper.cgColor
        panel.layer?.borderWidth = 0
        panel.layer?.borderColor = NSColor.clear.cgColor
        panelMaterial.material = mode.isDark ? .hudWindow : .sidebar
        if !mode.isGlass { panelMaterial.isHidden = true }
        scrim.layer?.backgroundColor = Self.scrimColor(for: mode).cgColor
        hostingView?.layer?.backgroundColor = mode.isGlass ? NSColor.clear.cgColor : paper.cgColor
    }

    private static func panelPaperColor(for mode: WeiBeiAppearanceMode) -> NSColor {
        WeiBeiNativePalette.drawerSurface(for: mode)
    }

    private static func scrimColor(for mode: WeiBeiAppearanceMode) -> NSColor {
        switch mode {
        case .paper, .xuan:
            return WeiBeiNativePalette.ink(for: mode).withAlphaComponent(mode == .xuan ? 0.030 : 0.035)
        case .glassLight:
            return NSColor(calibratedWhite: 0, alpha: 0.10)
        case .inkstone:
            return NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.18)
        case .stele:
            return NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.22)
        case .glassDark:
            return NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.18)
        }
    }

    private func startSlide(open: Bool, animated: Bool) {
        guard isOpen != open else { return }
        isOpen = open
        transitionGeneration &+= 1
        let generation = transitionGeneration
        let targetX: CGFloat = open ? 0 : -Self.panelWidth
        let height = max(bounds.height, 1)
        let targetPanel = CGRect(x: targetX, y: 0, width: Self.panelWidth, height: height)
        let targetScrimAlpha: CGFloat = open ? 1 : 0

        scrim.isHidden = false
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().frame = targetPanel
                scrim.animator().alphaValue = targetScrimAlpha
            }, completionHandler: { [weak self] in
                guard let self,
                      self.transitionGeneration == generation,
                      self.isOpen == open else { return }
                guard !open else { return }
                self.panelMaterial.isHidden = true
                self.scrim.isHidden = true
                self.removeSidebarContent()
            })
        } else {
            panel.frame = targetPanel
            scrim.alphaValue = targetScrimAlpha
            scrim.isHidden = !open
            if !open {
                panelMaterial.isHidden = true
                removeSidebarContent()
            }
        }
    }

    private func installHostingIfNeeded(store: WorkspaceStore) {
        guard hostingView == nil else { return }
        let paper = Self.panelPaperColor(for: store.appearanceMode)
        let model = CourseSidebarModel(store: store)
        let root = makeRootView(store: store, model: model)
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.backgroundColor = store.appearanceMode.isGlass
            ? NSColor.clear.cgColor
            : paper.cgColor
        host.frame = panel.bounds
        host.autoresizingMask = [.width, .height]
        panel.addSubview(host)
        sidebarModel = model
        hostingView = host
    }

    private func removeSidebarContent() {
        sidebarModel?.stop()
        hostingView?.rootView = AnyView(EmptyView())
        hostingView?.removeFromSuperview()
        hostingView = nil
        sidebarModel = nil
    }

    private func makeRootView(
        store: WorkspaceStore,
        model: CourseSidebarModel
    ) -> AnyView {
        AnyView(
            CourseImmersiveDrawerView(
                store: store,
                model: model
            ) { [weak self] in
                self?.onDismiss?()
            }
        )
    }
}
