import AppKit
import SwiftUI

/// AppKit-hosted course index column.
///
/// Why AppKit:
/// Sidebar content is installed only while open and remains warm while closed, so
/// resizing the peer workspace columns doesn't remount the course tree.
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
        view.apply(isOpen: drawer.isOpen, store: store)
        return view
    }

    func updateNSView(_ nsView: CourseDrawerContainerView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        nsView.onDismiss = { [weak coordinator = context.coordinator] in
            coordinator?.onDismiss()
        }
        nsView.apply(isOpen: drawer.isOpen, store: store)
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

    private let panel = NSView()
    private var hostingView: NSHostingView<AnyView>?
    private var isOpen = false
    private var hasWarmContent = false
    private var appearanceMode: WeiBeiAppearanceMode = .paper
    private weak var store: WorkspaceStore?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        panel.wantsLayer = true
        panel.layer?.backgroundColor = Self.panelPaperColor(for: .paper).cgColor
        panel.frame = CGRect(x: 0, y: 0, width: Self.panelWidth, height: 100)
        addSubview(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let height = max(bounds.height, 1)
        panel.frame = CGRect(x: 0, y: 0, width: Self.panelWidth, height: height)
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

    /**
     * 同步目录可见性，并只在展开路径刷新课程内容。
     */
    func apply(isOpen open: Bool, store: WorkspaceStore) {
        self.store = store
        applyPaperChrome(for: store.appearanceMode)

        if open {
            // Paint before the peer column expands so its first visible frame is complete.
            installHostingIfNeeded(store: store)
            syncHosting(store: store)
            layoutSubtreeIfNeeded()
            hostingView?.layoutSubtreeIfNeeded()
        }
        isOpen = open
        // Keep warm content for the next open, but do not sync store-driven rebuilds while closed.
    }

    private func applyPaperChrome(for mode: WeiBeiAppearanceMode) {
        appearanceMode = mode
        let paper = Self.panelPaperColor(for: mode)
        panel.layer?.backgroundColor = paper.cgColor
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
