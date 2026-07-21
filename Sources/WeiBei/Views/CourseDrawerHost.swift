import AppKit
import SwiftUI

/// AppKit-hosted course drawer.
///
/// Why AppKit:
/// 1. `NSAnimationContext` starts the slide on the next CA transaction — no wait for
///    SwiftUI to re-layout reader/agent/notes.
/// 2. Sidebar content is only installed while open (or kept warm but not store-synced
///    while closed), so pane toggles no longer re-render a hidden course tree.
struct CourseDrawerHost: NSViewRepresentable {
    @ObservedObject var drawer: LibraryDrawerState
    @EnvironmentObject private var store: WorkspaceStore
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
    private var hostingView: NSHostingView<AnyView>?
    private var isOpen = false
    private var hasWarmContent = false
    private var appearanceMode: WeiBeiAppearanceMode = .paper
    private weak var store: WorkspaceStore?

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
        let x = isOpen ? 0 : -Self.panelWidth
        panel.frame = CGRect(x: x, y: 0, width: Self.panelWidth, height: height)
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
        self.store = store
        applyPaperChrome(for: store.appearanceMode)

        if open {
            // Paint sidebar onto the paper panel *before* sliding — avoids the first-open
            // black/empty flash from mounting content mid-animation.
            installHostingIfNeeded(store: store)
            syncHosting(store: store)
            // One layout pass so the first frame of the slide already has content.
            layoutSubtreeIfNeeded()
            hostingView?.layoutSubtreeIfNeeded()
            startSlide(open: true, animated: animated)
        } else {
            startSlide(open: false, animated: animated)
            // Keep warm content for next open, but do not sync store-driven rebuilds while closed.
        }
    }

    private func applyPaperChrome(for mode: WeiBeiAppearanceMode) {
        appearanceMode = mode
        let paper = Self.panelPaperColor(for: mode)
        panel.layer?.backgroundColor = paper.cgColor
        scrim.layer?.backgroundColor = Self.scrimColor(for: mode).cgColor
        hostingView?.layer?.backgroundColor = paper.cgColor
    }

    private static func panelPaperColor(for mode: WeiBeiAppearanceMode) -> NSColor {
        // Match Sidebar / paperRaised family so empty frames never read as system dark gray.
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.976, green: 0.944, blue: 0.872, alpha: 1)
        case .inkstone:
            return NSColor(calibratedRed: 0.082, green: 0.082, blue: 0.082, alpha: 1)
        }
    }

    private static func scrimColor(for mode: WeiBeiAppearanceMode) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.115, green: 0.095, blue: 0.080, alpha: 0.035)
        case .inkstone:
            return NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.18)
        }
    }

    private func startSlide(open: Bool, animated: Bool) {
        guard isOpen != open || panel.frame.minX != (open ? 0 : -Self.panelWidth) else {
            isOpen = open
            return
        }
        isOpen = open
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
                guard let self else { return }
                if !self.isOpen {
                    self.scrim.isHidden = true
                }
            })
        } else {
            panel.frame = targetPanel
            scrim.alphaValue = targetScrimAlpha
            scrim.isHidden = !open
        }
    }

    private func installHostingIfNeeded(store: WorkspaceStore) {
        guard hostingView == nil else { return }
        let paper = Self.panelPaperColor(for: store.appearanceMode)
        let root = makeRootView(store: store)
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.backgroundColor = paper.cgColor
        host.frame = panel.bounds
        host.autoresizingMask = [.width, .height]
        panel.addSubview(host)
        hostingView = host
        hasWarmContent = true
    }

    private func syncHosting(store: WorkspaceStore) {
        // Called only on the open path (or first mount); closed path skips apply's sync.
        guard let hostingView else { return }
        hostingView.rootView = makeRootView(store: store)
    }

    private func makeRootView(store: WorkspaceStore) -> AnyView {
        AnyView(
            CourseImmersiveDrawerView { [weak self] in
                self?.onDismiss?()
            }
            .environmentObject(store)
            .environmentObject(store.libraryDrawer)
        )
    }
}
