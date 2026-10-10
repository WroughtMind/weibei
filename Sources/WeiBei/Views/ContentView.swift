#if targetEnvironment(macCatalyst)
import UIKit
#else
import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

struct ContentView: View {
    /// Intentionally does NOT observe `libraryDrawer` / `paneState` / `interaction` —
    /// those chrome surfaces rebuild dedicated child layers so reader/agent/notes stay put.
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weiBeiTextScale) private var textScale
    @FocusState private var focusedPane: PaneFocus?
    @FocusState private var topSearchFocused: Bool
    @State private var floatingAgentExpanded = false
    @State private var windowIsFullScreen = false
    @State private var isFileDropTargeted = false
    /// Size of the document area under the top bar. The float uses it for placement
    /// and must not measure that area with a GeometryReader laid over the reader.
    @State private var documentCanvas = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WorkspaceChromeBackdrop(isFullScreen: windowIsFullScreen)

                // Glass: ONE full-window foreground sheet above the backdrop and
                // below every surface (top bar, panes, course space). Each region
                // gets exactly one wash — per-surface painting stacked twice and
                // made the bar drift from the content below it.
                if store.appearanceMode.isGlass {
                    WeiBeiGlassForegroundSheet(mode: store.appearanceMode)
                }

                VStack(spacing: 0) {
                    UnifiedTopBarView(
                        isImmersiveLayout: isImmersiveLayout,
                        isFullScreen: windowIsFullScreen,
                        searchFocused: $topSearchFocused
                    )

                    if store.isCourseLibraryRootVolatile {
                        CourseLibraryVolatilityBanner()
                    }

                    ZStack(alignment: .top) {
                        LayoutContentView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
#if targetEnvironment(macCatalyst)
                            .ignoresSafeArea(.container, edges: .top)
#endif
                            .background(
                                store.appearanceMode.isGlass
                                    ? Color.clear
                                    : Color(weiBeiNativeColor: WeiBeiNativePalette.paper(for: store.appearanceMode))
                            )
                            // Only cross-fade immersive ↔ document families. Pane show/hide inside
                            // the document family is owned by AppKit StableDocumentWorkspace animation
                            // — a second SwiftUI layout animation here made toggles feel split/janky.
                            .animation(WeiBeiMotion.layout, value: store.layout.isImmersiveFamily)
                            .background {
                                GeometryReader { content in
                                    Color.clear.preference(
                                        key: DocumentCanvasSizeKey.self,
                                        value: content.size
                                    )
                                }
                            }
                            .onPreferenceChange(DocumentCanvasSizeKey.self) { size in
                                guard size.width > 1, size.height > 1 else { return }
                                if abs(documentCanvas.width - size.width) > 0.5
                                    || abs(documentCanvas.height - size.height) > 0.5 {
                                    documentCanvas = size
                                }
                            }
                            // Above the document, outside its layout. A ZStack sibling was
                            // resizing the reader for a frame, so the page painted again.
                            .overlay {
                                ZStack(alignment: .topLeading) {
                                    Color.clear.allowsHitTesting(false)
                                    GlobalFloatingSelectionLayer(
                                        expanded: $floatingAgentExpanded,
                                        canvasSize: documentCanvas == .zero ? geometry.size : documentCanvas
                                    )
                                }
                            }

                        // AppKit drawer: slide starts immediately; sidebar not store-synced while closed.
                        CourseLibraryDrawerLayer(store: store) {
                            store.toggleLibrary()
                        }
                        .zIndex(35)

                        if store.commandPalettePresented {
                            CommandPaletteView()
                                .transition(WeiBeiTransition.commandPalette)
                                .zIndex(40)
                        }
                    }
                }
                .allowsHitTesting(!store.courseWorkspacePresented)
                .accessibilityHidden(store.courseWorkspacePresented)
                .opacity(
                    store.courseWorkspacePresented && store.appearanceMode.isGlass
                        ? 0
                        : 1
                )

                if store.courseWorkspacePresented {
                    ZStack {
                        Color(weiBeiNativeColor: WeiBeiNativePalette.foregroundWorkspaceSurface(
                            for: store.appearanceMode
                        ))
                        CourseWorkspaceView()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.995, anchor: .top)))
                    .zIndex(100)
                }

                // Single top-level status surface: important errors first,
                // otherwise editor / selection / transient note status.
                // Workspace save failures live on the title-bar persist dot.
                if store.importantOperationError != nil
                    || store.noteEditorCommandFailureMessage != nil
                    || store.noteSelectionStatusMessage != nil
                    || store.transientNoteStatus != nil {
                    WorkspaceStatusBanner()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
#if targetEnvironment(macCatalyst)
                        .padding(.top, 10)
#else
                        .padding(.top, WeiBeiMetric.topBarHeight * textScale + 10)
#endif
                        .zIndex(120)
                        .transition(WeiBeiTransition.floating)
                }

                if store.courseFileOperationProgress != nil {
                    ImportProgressPill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 16)
                        .padding(.bottom, 16)
                        .zIndex(120)
                        .transition(WeiBeiTransition.floating)
                }

                // Agent 创建文稿的写盘确认浮层：覆盖课程空间等全部层级。
                AgentDocumentConfirmationOverlay()
            }
            .contentShape(Rectangle())
            .allowsHitTesting(!store.settingsPresented)
            .accessibilityHidden(store.settingsPresented)
#if targetEnvironment(macCatalyst)
            .background {
                WorkspaceFileDropBridge(isTargeted: $isFileDropTargeted,
                    receive: receiveTransferredFileDrop, receiveNative: receiveFileDropURLs)
                    .allowsHitTesting(false)
            }
#else
            .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
                receiveFileDrop(providers)
            }
#endif
            .overlay {
                if isFileDropTargeted { WeiBeiFileDropPrompt() }
            }
            .overlay {
                if store.settingsPresented {
                    ZStack {
                        Color.black.opacity(0.22)
                            .ignoresSafeArea()
                        SettingsPanel(availableSize: geometry.size)
                    }
                    .transition(.opacity)
                }
            }
            .animation(WeiBeiMotion.panel, value: store.settingsPresented)
            .animation(WeiBeiMotion.panel, value: store.importantOperationError)
            .animation(WeiBeiMotion.panel, value: store.lastPersistState)
            .animation(WeiBeiMotion.panel, value: store.noteEditorCommandFailureMessage)
            .animation(WeiBeiMotion.panel, value: store.noteSelectionStatusMessage)
            .animation(WeiBeiMotion.panel, value: store.transientNoteStatus)
            .background {
                LibraryAwareEscapeBridge(
                    courseWorkspacePresented: store.courseWorkspacePresented,
                    onDismissFloatingAgent: { store.dismissFloatingSelectionAgent() },
                    onHideReaderSearch: {
                        store.hideDocumentSearch()
                        topSearchFocused = false
                    }
                )
            }
        }
        .sheet(isPresented: $store.excerptBookPresented) {
            ExcerptBookView(courseID: store.excerptBookCourseID)
                .environmentObject(store)
        }
        .sheet(isPresented: Binding(
            get: { store.confirmedFileImport != nil },
            set: { if !$0 { store.dismissConfirmedFileImport() } }
        )) {
            ConfirmedFileImportView().environmentObject(store)
        }
        .background(WindowFullScreenReader(isFullScreen: $windowIsFullScreen))
        .background {
            // Focus / reader-search sync observes paneState so ContentView does not.
            PaneChromeFocusBridge(
                focusedPane: $focusedPane,
                topSearchFocused: $topSearchFocused
            )
        }
        .onAppear {
            focusedPane = store.focusedPane
            guard WeiBeiPerf.isEnabled else { return }
            DispatchQueue.main.async {
                WeiBeiPerf.finishLaunch()
            }
        }
        // Theme animation is owned by `setAppearanceMode` (single transaction).
        // A second root `.animation(value: appearanceMode)` desynced chrome vs paper.
        // showLibrary animation is scoped to the drawer ZStack only (above).
        .animation(WeiBeiMotion.panel, value: store.courseWorkspacePresented)
    }

    private var isImmersiveLayout: Bool {
        [.immersiveReading, .immersiveConversation, .immersiveWriting].contains(store.layout)
    }

#if targetEnvironment(macCatalyst)
    private func receiveTransferredFileDrop(_ providers: [NSItemProvider], _ urls: [URL]) {
        store.receiveTransferredFiles(providers, sourceURLs: urls,
            courseID: store.courseWorkspacePresented ? store.courseWorkspaceCourseID : nil)
    }
    private func receiveFileDropURLs(_ urls: [URL]) {
        store.receiveDroppedFileURLs(urls, courseID: store.courseWorkspacePresented
            ? store.courseWorkspaceCourseID : nil)
    }
#endif
    private func receiveFileDrop(_ providers: [NSItemProvider]) -> Bool {
        return store.receiveDroppedFiles(providers, courseID: store.courseWorkspacePresented
            ? store.courseWorkspaceCourseID : nil)
    }
}

private struct WeiBeiFileDropPrompt: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        Label(store.ui("松开以导入资料", "Drop to import"), systemImage: "tray.and.arrow.down")
            .weiBeiText(14, weight: .semibold)
            .foregroundStyle(WeiBeiTheme.cinnabar)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .weibeiEtchedCapsuleBackground(
                fill: WeiBeiTheme.paperRaised.opacity(0.94),
                stroke: WeiBeiTheme.cinnabar.opacity(0.32),
                contactShadow: true
            )
            .allowsHitTesting(false)
    }
}

#if !targetEnvironment(macCatalyst)
private struct WindowFullScreenReader: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isFullScreen = $isFullScreen
        context.coordinator.attach(to: view)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator {
        var isFullScreen: Binding<Bool>
        private weak var view: NSView?
        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        func attach(to view: NSView) {
            self.view = view
            DispatchQueue.main.async { [weak self] in
                self?.observeWindowIfReady()
            }
        }

        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            observedWindow = nil
        }

        private func observeWindowIfReady() {
            guard let window = view?.window else { return }
            isFullScreen.wrappedValue = window.styleMask.contains(.fullScreen)
            guard observedWindow !== window else { return }
            stopObserving()
            observedWindow = window
            let names: [NSNotification.Name] = [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    self?.isFullScreen.wrappedValue = window?.styleMask.contains(.fullScreen) == true
                }
            }
        }
    }
}

#endif

/// AppKit course drawer layer. Observes only `LibraryDrawerState`; the store reference
/// is passed through without subscribing this chrome layer to the whole workspace.
private struct CourseLibraryDrawerLayer: View {
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    let store: WorkspaceStore
    let dismiss: () -> Void

    var body: some View {
        CourseDrawerHost(
            drawer: libraryDrawer,
            store: store,
            onDismiss: dismiss
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(libraryDrawer.isOpen)
            .accessibilityHidden(!libraryDrawer.isOpen)
    }
}

/// Syncs `@FocusState` from `WorkspacePaneState` without ContentView observing pane chrome.
private struct PaneChromeFocusBridge: View {
    @EnvironmentObject private var paneState: WorkspacePaneState
    var focusedPane: FocusState<PaneFocus?>.Binding
    var topSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: paneState.focusedPane) { _, value in
                focusedPane.wrappedValue = value
            }
            .onChange(of: paneState.showDocumentSearch) { _, visible in
                topSearchFocused.wrappedValue = visible
            }
            .onChange(of: paneState.searchFocusRequest) { _, _ in
                topSearchFocused.wrappedValue = true
            }
            .onAppear {
                focusedPane.wrappedValue = paneState.focusedPane
                topSearchFocused.wrappedValue = paneState.showDocumentSearch
            }
    }
}

private struct DocumentCanvasSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 1, next.height > 1 { value = next }
    }
}

/// Selection float layer. Observes `WorkspaceInteractionState` (+ store for chat routing).
private struct GlobalFloatingSelectionLayer: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @Environment(\.weiBeiTextScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var expanded: Bool
    let canvasSize: CGSize
    /// Top-left of the expanded panel. Nil until 「问」/「记」 opens; cleared when the float hides.
    @State private var placedOrigin: CGPoint? = nil

    var body: some View {
        Group {
            if showsGlobalFloatingAgent {
                FloatingSelectionAgentView(
                    expanded: $expanded,
                    placedOrigin: $placedOrigin,
                    canvasSize: canvasSize,
                    topInset: CGFloat(selectionTopInset)
                )
                .modifier(FloatingSelectionPositionModifier(
                    placedOrigin: $placedOrigin,
                    usesPlacedOrigin: usesPlacedOrigin,
                    initialOrigin: initialOrigin,
                    anchor: interaction.selectionAnchor.map {
                        FloatingAgentCoordinate(x: Double($0.x), y: Double($0.y))
                    },
                    canvasSize: canvasSize,
                    topInset: selectionTopInset,
                    prefersAbove: interaction.selectionAnchor?.prefersAbove == true
                ))
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : WeiBeiMotion.appearance, value: showsGlobalFloatingAgent)
        .transaction { transaction in
            // Fade visibility only; selection coordinates must track without a spring.
            transaction.animation = nil
        }
        .onChange(of: usesPlacedOrigin) { _, placed in
            guard placed, placedOrigin == nil else { return }
            placedOrigin = initialOrigin
        }
        .onChange(of: showsGlobalFloatingAgent) { _, shown in
            if !shown { placedOrigin = nil }
        }
    }

    private var showsGlobalFloatingAgent: Bool {
        // The selection composer stays beside the passage in every reading layout.
        !store.courseWorkspacePresented
            && store.canShowSelectionPromptSurface
            && SelectionFloatingAgentPlacement.isVisible(
                surface: interaction.agentSurface,
                hasSelection: interaction.selectionContext != nil || interaction.keepFloatingSelectionForAnswer,
                hasAnchor: interaction.selectionAnchor != nil,
                pinned: false,
                keepOpen: interaction.keepFloatingSelectionForAnswer
            )
    }

    private var usesPlacedOrigin: Bool {
        expanded || interaction.keepFloatingSelectionForAnswer
    }

    private var initialOrigin: CGPoint {
        let point = SelectionFloatingAgentPlacement.initialTopLeft(
            anchor: interaction.selectionAnchor.map { FloatingAgentCoordinate(x: Double($0.x), y: Double($0.y)) },
            canvas: FloatingAgentCoordinate(x: Double(canvasSize.width), y: Double(canvasSize.height)),
            topInset: selectionTopInset,
            prefersAbove: interaction.selectionAnchor?.prefersAbove == true
        )
        return CGPoint(x: point.x, y: point.y)
    }

    private var selectionTopInset: Double {
#if targetEnvironment(macCatalyst)
        // The native toolbar sits outside the workspace's content coordinates.
        0
#else
        Double(WeiBeiMetric.topBarHeight * textScale)
#endif
    }
}

/// Read motion in the display modifier, outside the conversation's layout inputs.
private struct FloatingSelectionPositionModifier: ViewModifier {
    @Binding var placedOrigin: CGPoint?
    let usesPlacedOrigin: Bool
    let initialOrigin: CGPoint
    let anchor: FloatingAgentCoordinate?
    let canvasSize: CGSize
    let topInset: Double
    let prefersAbove: Bool

    func body(content: Content) -> some View {
        content.modifier(FloatingSelectionPositionEffect(
            origin: usesPlacedOrigin ? placedOrigin ?? initialOrigin : nil,
            anchor: anchor,
            canvasSize: canvasSize,
            topInset: topInset,
            prefersAbove: prefersAbove
        ))
    }
}

/// A translation changes where the panel is drawn, without proposing a new text layout.
private struct FloatingSelectionPositionEffect: GeometryEffect {
    let origin: CGPoint?
    let anchor: FloatingAgentCoordinate?
    let canvasSize: CGSize
    let topInset: Double
    let prefersAbove: Bool

    func effectValue(size: CGSize) -> ProjectionTransform {
        let topLeft: CGPoint
        if let origin {
            topLeft = origin
        } else {
            let center = SelectionFloatingAgentPlacement.position(
                anchor: anchor,
                canvas: FloatingAgentCoordinate(x: Double(canvasSize.width), y: Double(canvasSize.height)),
                topInset: topInset,
                surfaceHalfWidth: Double(size.width / 2),
                measuredHalfHeight: Double(size.height / 2),
                prefersAbove: prefersAbove,
                prefersAnchorCenter: true
            )
            topLeft = CGPoint(x: center.x - Double(size.width / 2), y: center.y - Double(size.height / 2))
        }
        return ProjectionTransform(CGAffineTransform(translationX: topLeft.x, y: topLeft.y))
    }
}

/// Top-level workspace feedback: important data-operation errors (persistent,
/// user-dismissed) take priority over the auto-expiring transient status.
private struct ImportProgressPill: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        let progress = store.courseFileOperationProgress
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(store.ui(
                "正在导入 \(progress?.completed ?? 0)/\(progress?.total ?? 0)：\(progress?.currentFileName ?? "")",
                "Importing \(progress?.completed ?? 0)/\(progress?.total ?? 0): \(progress?.currentFileName ?? "")"
            ))
            .weiBeiText(12, weight: .medium)
            .foregroundStyle(WeiBeiTheme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .weibeiEtchedCapsuleBackground(
            fill: WeiBeiTheme.paperRaised.opacity(0.97),
            stroke: WeiBeiTheme.hairline.opacity(0.6),
            contactShadow: true
        )
        .clipShape(Capsule())
        .shadow(color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.3 : 0.1), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(store.ui("正在导入文件", "Importing files")))
    }
}

private struct WorkspaceStatusBanner: View {
    @EnvironmentObject private var store: WorkspaceStore

    private var isImportant: Bool {
        store.importantOperationError != nil
    }

    private var isNoteSelectionFailure: Bool {
        !isImportant && !isEditorCommandFailure
            && store.canRetryPendingNoteSelection
    }

    private var isEditorCommandFailure: Bool {
        !isImportant && store.noteEditorCommandFailureMessage != nil
    }

    private var isAlert: Bool {
        isImportant || isEditorCommandFailure || isNoteSelectionFailure
    }

    private var showsBackupReveal: Bool {
        !isAlert
            && store.noteSelectionStatusMessage == nil
            && store.transientNoteStatusRevealURL != nil
    }

    private var message: String {
        store.importantOperationError
            ?? store.noteEditorCommandFailureMessage
            ?? store.noteSelectionStatusMessage
            ?? store.transientNoteStatus
            ?? ""
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isAlert ? "exclamationmark.triangle.fill" : "info.circle")
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(isAlert ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
            Text(message)
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if isEditorCommandFailure && store.canRetryRejectedNoteEditorCommand {
                Button {
                    store.retryRejectedNoteEditorCommand()
                } label: {
                    Text(store.ui("重试", "Retry"))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("重试应用编辑内容", "Retry applying editor content")))
            } else if isNoteSelectionFailure {
                Button {
                    store.retryPendingNoteSelection()
                } label: {
                    Text(store.ui("重试", "Retry"))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("重试保存并切换笔记", "Retry saving and switching notes")))
            } else if store.pendingDeletionUndo != nil {
                Button {
                    store.undoPendingDeletion()
                } label: {
                    Text(store.ui("撤销", "Undo"))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("撤销删除", "Undo delete")))
            } else if isImportant {
                if case .defaultLibraryBootstrapFailed = store.importantOperationNotice {
                    Button {
                        store.retryBootstrapDefaultLibrary()
                    } label: {
                        Text(store.ui("重试", "Retry"))
                            .weiBeiText(12, weight: .semibold)
                            .foregroundStyle(WeiBeiTheme.cinnabar)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(store.ui("重试建立默认资料库", "Retry creating the default library")))
                }
                Button {
                    store.dismissImportantOperationError()
                } label: {
                    Image(systemName: "xmark")
                        .weiBeiText(10.5, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("关闭错误提示", "Dismiss error")))
            } else if showsBackupReveal {
                Button {
                    if let url = store.transientNoteStatusRevealURL {
                        store.revealMaterialFileInFinder(url)
                    }
                } label: {
                    Text(store.ui("在访达中显示", "Show in Finder"))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("在访达中显示备份", "Show backup in Finder")))
                Button {
                    store.dismissTransientNoteStatus()
                } label: {
                    Image(systemName: "xmark")
                        .weiBeiText(10.5, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("关闭提示", "Dismiss notice")))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 440, alignment: .leading)
        .background {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: WeiBeiTheme.paperRaised.opacity(0.97),
                stroke: isAlert
                    ? WeiBeiTheme.cinnabar.opacity(0.55)
                    : WeiBeiTheme.hairline.opacity(0.6),
                showsContactShadow: true
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.3 : 0.1), radius: 12, y: 6)
        .allowsHitTesting(isAlert || showsBackupReveal || store.pendingDeletionUndo != nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(store.ui("工作台状态提示", "Workspace status")))
    }
}

/// Escape routing that can observe drawer / pane / selection chrome without forcing ContentView to do so.
private struct LibraryAwareEscapeBridge: View {
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    @EnvironmentObject private var paneState: WorkspacePaneState
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @EnvironmentObject private var store: WorkspaceStore
    let courseWorkspacePresented: Bool
    let onDismissFloatingAgent: () -> Void
    let onHideReaderSearch: () -> Void

    var body: some View {
        Group {
            if !courseWorkspacePresented && store.notePickerPresented {
                EscapeKeyBridge(onEscape: {
                    store.notePickerPresented = false
                    store.focus(.notes)
                })
            } else if !courseWorkspacePresented && !libraryDrawer.isOpen && showsGlobalFloatingAgent {
                EscapeKeyBridge(onEscape: onDismissFloatingAgent)
            } else if !courseWorkspacePresented && !libraryDrawer.isOpen && paneState.showDocumentSearch {
                EscapeKeyBridge(onEscape: onHideReaderSearch)
            } else if !courseWorkspacePresented && !libraryDrawer.isOpen && !store.readerSourceHighlight.isEmpty {
                // X8: Esc clears the source-reference jump highlight (search UI closed).
                EscapeKeyBridge(onEscape: { store.clearReaderSourceHighlight() })
            }
        }
    }

    private var showsGlobalFloatingAgent: Bool {
        !courseWorkspacePresented
            && store.canShowSelectionPromptSurface
            && SelectionFloatingAgentPlacement.isVisible(
                surface: interaction.agentSurface,
                hasSelection: interaction.selectionContext != nil || interaction.keepFloatingSelectionForAnswer,
                hasAnchor: interaction.selectionAnchor != nil,
                pinned: false,
                keepOpen: interaction.keepFloatingSelectionForAnswer
            )
    }
}

/// Window paper sits behind the top bar so empty-board glow and open-pane
/// paper continue through the chrome instead of becoming a second strip.
private struct WorkspaceChromeBackdrop: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var paneState: WorkspacePaneState
    let isFullScreen: Bool

    var body: some View {
        let empty = !paneState.showReader && !paneState.showAgent && !paneState.showNotes
        ZStack {
            WeiBeiThemeBackdrop(
                mode: store.appearanceMode,
                isFullScreen: isFullScreen
            )
            if empty && store.appearanceMode != .glassMist && store.appearanceMode != .glassSlate {
                EmptyWorkspacePaperField(mode: store.appearanceMode, compact: false)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if targetEnvironment(macCatalyst)
/// Find field we own. SwiftUI `TextField` on Catalyst keeps the system gray well
/// and blue focus ring no matter which theme is active.
struct WeiBeiPlainTextField: UIViewRepresentable {
    @Binding var text: String
    var prompt: String
    var fontSize: CGFloat
    var isFocused: Binding<Bool>
    var focusRequest: Int
    var focusesOnAppear: Bool
    var brandLanguage: WeiBeiInterfaceLanguage?
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMove: ((Int) -> Void)?

    func makeUIView(context: Context) -> WeiBeiSearchTextField {
        let field = WeiBeiSearchTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: WeiBeiSearchTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        let font = Self.font(size: fontSize, brandLanguage: brandLanguage)
        field.font = font
        field.textColor = WeiBeiNativePalette.ink()
        field.tintColor = WeiBeiNativePalette.cinnabar()
        field.attributedPlaceholder = NSAttributedString(
            string: prompt,
            attributes: [
                .foregroundColor: WeiBeiNativePalette.placeholderInk(),
                .font: font
            ]
        )
        field.accessibilityLabel = prompt
        field.onSubmit = onSubmit
        field.onEscape = onEscape
        field.onMove = onMove
        field.stripSystemChrome()
        if field.appliedFocusRequest != focusRequest {
            let shouldFocus = field.appliedFocusRequest != -1 || focusesOnAppear || isFocused.wrappedValue
            field.appliedFocusRequest = focusRequest
            if shouldFocus { field.scheduleFocus() }
        } else if isFocused.wrappedValue, !field.wasFocusedBinding {
            field.scheduleFocus()
        }
        field.wasFocusedBinding = isFocused.wrappedValue
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WeiBeiSearchTextField, context: Context) -> CGSize? {
        let intrinsicHeight = uiView.intrinsicContentSize.height
        let fittedHeight = intrinsicHeight.isFinite && intrinsicHeight > 0
            ? intrinsicHeight
            : uiView.sizeThatFits(
                CGSize(
                    width: proposal.width ?? UIView.layoutFittingCompressedSize.width,
                    height: UIView.layoutFittingCompressedSize.height
                )
            ).height
        return CGSize(
            width: proposal.width ?? 160,
            height: fittedHeight.isFinite && fittedHeight > 0
                ? fittedHeight
                : max(fontSize + 8, 22)
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static func font(size: CGFloat, brandLanguage: WeiBeiInterfaceLanguage?) -> UIFont {
        guard let brandLanguage else { return .systemFont(ofSize: size) }
        if brandLanguage == .english {
            WeiBeiTypography.registerBundledFonts()
            if let named = UIFont(name: WeiBeiTypography.englishDisplayFontName, size: size) { return named }
        }
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: WeiBeiPlainTextField
        init(_ parent: WeiBeiPlainTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            let next = field.text ?? ""
            if parent.text != next { parent.text = next }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFocused.wrappedValue { parent.isFocused.wrappedValue = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isFocused.wrappedValue { parent.isFocused.wrappedValue = false }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard let onSubmit = parent.onSubmit else { return true }
            onSubmit()
            return false
        }
    }
}

final class WeiBeiSearchTextField: UITextField {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var appliedFocusRequest = -1
    var wasFocusedBinding = false
    private var pendingFocus = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        borderStyle = .none
        backgroundColor = .clear
        autocorrectionType = .no
        spellCheckingType = .no
        clearButtonMode = .never
        returnKeyType = .search
        tintColor = WeiBeiNativePalette.cinnabar()
    }

    required init?(coder: NSCoder) { return nil }

    override var focusEffect: UIFocusEffect? {
        get { nil }
        set { }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stripSystemChrome()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        stripSystemChrome()
        return accepted
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, pendingFocus { scheduleFocus() }
    }

    func scheduleFocus() {
        pendingFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.pendingFocus = !self.becomeFirstResponder()
        }
    }

    func stripSystemChrome() {
        borderStyle = .none
        backgroundColor = .clear
        layer.borderWidth = 0
        layer.borderColor = UIColor.clear.cgColor
        layer.shadowOpacity = 0
        for subview in subviews {
            let name = NSStringFromClass(type(of: subview))
            let isChrome = name.contains("Background") || name.contains("Rounded") || name.contains("Focus") || name.contains("Halo")
            guard isChrome else { continue }
            subview.isHidden = true
            subview.alpha = 0
            subview.backgroundColor = .clear
            subview.layer.borderWidth = 0
        }
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: 1, dy: 0) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []
        if onMove != nil {
            let up = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(moveUp))
            let down = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(moveDown))
            up.wantsPriorityOverSystemBehavior = true
            down.wantsPriorityOverSystemBehavior = true
            commands.append(contentsOf: [up, down])
        }
        if onEscape != nil {
            let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape))
            escape.wantsPriorityOverSystemBehavior = true
            commands.append(escape)
        }
        return commands.isEmpty ? nil : commands
    }

    @objc private func moveUp() { onMove?(-1) }
    @objc private func moveDown() { onMove?(1) }
    @objc private func escape() { onEscape?() }
}

/// One plate for the find cluster. Glass is a blur plus that theme's own tint.
/// Paper themes use raised paper. Neither path is the system gray search well.
private struct ReaderSearchPlate: UIViewRepresentable {
    var mode: WeiBeiAppearanceMode

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        if mode.isGlass {
            view.effect = UIBlurEffect(style: mode.isDark ? .systemThinMaterialDark : .systemThinMaterialLight)
            view.contentView.backgroundColor = WeiBeiNativePalette.glassTint(for: mode)
                .withAlphaComponent(mode.isDark ? 0.78 : 0.70)
        } else {
            view.effect = nil
            view.contentView.backgroundColor = WeiBeiNativePalette.paperRaised(for: mode)
        }
    }
}
#endif

/// Search text used by the find cluster and the other search fields.
/// On Catalyst this is a borderless field; the surrounding plate or
/// `weibeiInputSurface` is the only chrome.
struct WeiBeiSearchField: View {
    @Binding var text: String
    var prompt: String
    var isFocused: Binding<Bool>
    var fontSize: CGFloat = 12
    var focusRequest: Int = 0
    var focusesOnAppear: Bool = false
    var drawsChrome: Bool = true
    var chromeHeight: CGFloat = 28
    var horizontalPadding: CGFloat = 10
    var brandLanguage: WeiBeiInterfaceLanguage? = nil
    var onSubmit: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onMove: ((Int) -> Void)? = nil

    var body: some View {
        field
            .modifier(WeiBeiSearchFieldChrome(
                drawsChrome: drawsChrome,
                active: isFocused.wrappedValue,
                height: chromeHeight,
                horizontalPadding: horizontalPadding
            ))
    }

    @ViewBuilder
    private var field: some View {
#if targetEnvironment(macCatalyst)
        WeiBeiPlainTextField(
            text: $text,
            prompt: prompt,
            fontSize: fontSize,
            isFocused: isFocused,
            focusRequest: focusRequest,
            focusesOnAppear: focusesOnAppear,
            brandLanguage: brandLanguage,
            onSubmit: onSubmit,
            onEscape: onEscape,
            onMove: onMove
        )
#else
        MacSearchField(
            text: $text,
            prompt: prompt,
            isFocused: isFocused,
            fontSize: fontSize,
            focusRequest: focusRequest,
            focusesOnAppear: focusesOnAppear,
            brandLanguage: brandLanguage,
            onSubmit: onSubmit,
            onEscape: onEscape,
            onMove: onMove
        )
#endif
    }
}

#if !targetEnvironment(macCatalyst)
private struct MacSearchField: View {
    @Binding var text: String
    var prompt: String
    var isFocused: Binding<Bool>
    var fontSize: CGFloat
    var focusRequest: Int
    var focusesOnAppear: Bool
    var brandLanguage: WeiBeiInterfaceLanguage?
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMove: ((Int) -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: promptText)
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            .modifier(MacSearchFieldFont(fontSize: fontSize, brandLanguage: brandLanguage))
            .focused($focused)
            .foregroundStyle(WeiBeiTheme.ink)
            .tint(WeiBeiTheme.cinnabar)
            .onChange(of: focused) { _, value in
                if isFocused.wrappedValue != value { isFocused.wrappedValue = value }
            }
            .onChange(of: isFocused.wrappedValue) { _, value in
                if focused != value { focused = value }
            }
            .onAppear { focused = focusesOnAppear || isFocused.wrappedValue }
            .onChange(of: focusRequest) { _, _ in focused = true }
            .onSubmit { onSubmit?() }
            .modifier(SearchExitCommand(action: onEscape))
            .onKeyPress(.upArrow) {
                guard onMove != nil else { return .ignored }
                onMove?(-1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard onMove != nil else { return .ignored }
                onMove?(1)
                return .handled
            }
    }

    private var promptText: Text {
        let prompt = Text(prompt).foregroundStyle(WeiBeiTheme.placeholderInk)
        guard let brandLanguage else { return prompt }
        return prompt.font(WeiBeiTypography.brandFont(language: brandLanguage, size: fontSize, weight: .semibold))
    }
}

private struct SearchExitCommand: ViewModifier {
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.weiBeiOnExitCommand(perform: action)
        } else {
            content
        }
    }
}

private struct MacSearchFieldFont: ViewModifier {
    var fontSize: CGFloat
    var brandLanguage: WeiBeiInterfaceLanguage?

    func body(content: Content) -> some View {
        if let brandLanguage {
            content.weiBeiBrandFont(language: brandLanguage, size: fontSize, weight: .semibold)
        } else {
            content.weiBeiText(fontSize)
        }
    }
}
#endif

private struct WeiBeiSearchFieldChrome: ViewModifier {
    var drawsChrome: Bool
    var active: Bool
    var height: CGFloat
    var horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        if drawsChrome {
            content.weibeiInputSurface(active: active, height: height, horizontalPadding: horizontalPadding)
        } else {
            content
                .padding(.horizontal, 2)
                .frame(minHeight: height)
        }
    }
}

/// Focus new and repeated find requests after the field enters its view hierarchy.
private struct ToolbarSearchField: View {
    @Binding var text: String
    let prompt: String
    let focusRequest: Int
    let height: CGFloat
    var width: CGFloat? = 220
    var drawsOwnChrome = true
    var onFocusedChange: (Bool) -> Void = { _ in }
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onMove: (Int) -> Void
    @State private var isFocused = false

    var body: some View {
        WeiBeiSearchField(
            text: $text,
            prompt: prompt,
            isFocused: $isFocused,
            fontSize: 12,
            focusRequest: focusRequest,
            focusesOnAppear: true,
            drawsChrome: drawsOwnChrome,
            chromeHeight: height,
            horizontalPadding: drawsOwnChrome ? 8 : 2,
            onSubmit: onSubmit,
            onEscape: onEscape,
            onMove: onMove
        )
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .onChange(of: isFocused) { _, value in onFocusedChange(value) }
    }
}

private struct SearchClusterIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        SearchClusterIconBody(configuration: configuration, isEnabled: isEnabled)
    }
}

private struct SearchClusterIconBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(foreground)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering && isEnabled ? WeiBeiTheme.ink.opacity(0.08) : Color.clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering = isEnabled && $0 }
    }

    private var foreground: Color {
        guard isEnabled else { return WeiBeiTheme.tertiaryInk.opacity(0.45) }
        return hovering || configuration.isPressed ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk
    }
}

private struct SearchClusterTextRow: View {
    let title: String
    let systemImage: String
    var accessibilityLabel: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? WeiBeiTheme.ink.opacity(0.06) : Color.clear)
        .accessibilityLabel(Text(accessibilityLabel))
        .onHover { hovering = $0 }
    }
}

private struct SearchResultRow<Label: View>: View {
    var selected: Bool
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .weiBeiText(12)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        }
        .onHover { hovering = $0 }
    }

    private var rowFill: Color {
        if selected { return WeiBeiTheme.cinnabarSoft }
        if hovering { return WeiBeiTheme.ink.opacity(0.06) }
        return .clear
    }
}

func readerSearchLocationLabel(_ result: ReaderSearchResult, language: WeiBeiInterfaceLanguage) -> String {
    let raw = result.location.isEmpty ? "第 \(result.pageIndex + 1) 页" : result.location
    let location = raw.hasPrefix("第 ")
        ? raw.replacingOccurrences(of: "第 ", with: "").replacingOccurrences(of: " ", with: "")
        : raw
    guard language == .english else { return location }
    if location.hasSuffix("页备注"), let page = Int(location.dropLast(3)) { return "Page \(page) notes" }
    if location.hasSuffix("页"), let page = Int(location.dropLast()) { return "Page \(page)" }
    if location.hasSuffix("行"), let line = Int(location.dropLast()) { return "Line \(line)" }
    if location.hasPrefix("段 "), let paragraph = Int(location.dropFirst(2)) { return "Paragraph \(paragraph)" }
    return location
}

private struct UnifiedTopBarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var updateService: WeiBeiUpdateService
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    @EnvironmentObject private var paneState: WorkspacePaneState
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @Environment(\.weiBeiTextScale) private var textScale
    let isImmersiveLayout: Bool
    let isFullScreen: Bool
    var searchFocused: FocusState<Bool>.Binding
    @State private var appeared = false
    @State private var readerSearchKeyboardFocusRequest = 0
    @State private var searchFieldFocused = false

    var body: some View {
#if targetEnvironment(macCatalyst)
        CatalystTopBar(
            leading: toolbarContent(leftPrimaryControls),
            center: toolbarContent(paneToggleCluster),
            trailing: toolbarContent(trailingControls),
            overflowMenus: toolbarOverflowMenus,
            isVisible: !store.courseWorkspacePresented
        )
        .frame(height: 0)
        .overlay(alignment: .topTrailing) {
            if paneState.showDocumentSearch && shouldShowSearchAction {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                VStack(spacing: 0) {
                    HStack(spacing: 2) {
                        Image(systemName: "magnifyingglass")
                            .weiBeiText(11, weight: .medium)
                            .foregroundStyle(searchFieldFocused ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk)
                            .frame(width: 18)
                        searchControls
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.vertical, 4)
                    if showsReaderSearchResults {
                        searchClusterHairline
                        readerSearchResultsList
                    }
                    if paneState.canReturnToReaderSearchOrigin(for: store.selectedMaterialItem?.id) {
                        searchClusterHairline
                        readerSearchReturnRow
                    }
                }
                .frame(width: searchClusterExpanded ? 348 : nil, alignment: .leading)
                .fixedSize(horizontal: !searchClusterExpanded, vertical: true)
                .background { ReaderSearchPlate(mode: store.appearanceMode) }
                .clipShape(shape)
                .overlay { shape.stroke(searchClusterStroke, lineWidth: 1) }
                .shadow(color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.36 : 0.16), radius: 16, y: 8)
                .padding(.trailing, 12)
                .padding(.top, 5)
            }
        }
        .zIndex(10)
        .onChange(of: store.readerSearch) { _, _ in readerSearchKeyboardFocusRequest = 0 }
        .onChange(of: paneState.showDocumentSearch) { _, visible in
            if !visible { readerSearchKeyboardFocusRequest = 0 }
        }

#else
        customTopBar
#endif
    }

#if targetEnvironment(macCatalyst)
    private var toolbarOverflowMenus: [UIMenu] {
        let navigation = [
            toolbarAction(store.ui("课程栏", "Course sidebar"), selected: libraryDrawer.isOpen, action: store.toggleLibrary),
            toolbarAction(store.ui("后退", "Back"), enabled: store.canNavigateBack) {
                withAnimation(WeiBeiMotion.layout) { store.navigateBackInWorkspace() }
            },
            toolbarAction(store.ui("前进", "Forward"), enabled: store.canNavigateForward) {
                withAnimation(WeiBeiMotion.layout) { store.navigateForwardInWorkspace() }
            }
        ]
        let panes = [
            toolbarAction(store.ui("文稿", "Document"), selected: store.isPaneToggleActive(.reader), action: store.toggleReader),
            toolbarAction(store.ui("对话", "Chat"), selected: store.isPaneToggleActive(.agent), action: store.toggleAgent),
            toolbarAction(store.ui("笔记", "Notes"), selected: store.isPaneToggleActive(.notes), action: store.toggleNotes)
        ]
        var actions: [UIAction] = []
        if updateService.showsToolbarControl {
            actions.append(toolbarAction(updateService.actionLabel(english: store.interfaceLanguage == .english),
                enabled: !updateService.isBusy, action: updateService.installAvailableUpdate))
        }
        if shouldShowSearchAction {
            actions.append(toolbarAction(searchPrompt,
                selected: paneState.showDocumentSearch, action: toggleReaderSearch))
        }
        actions.append(toolbarAction(store.ui("切换深浅外观", "Toggle Light / Dark"), action: toggleAppearance))
        if store.lastPersistState == .failed {
            actions.append(toolbarAction(store.ui("重试保存", "Retry save")) { _ = store.retryWorkspaceSave() })
        }
        actions.append(toolbarAction(store.ui("打开设置", "Open Settings"), action: showSettings))
        return [UIMenu(title: store.ui("导航", "Navigation"), children: navigation),
                UIMenu(title: store.ui("面板", "Panes"), children: panes),
                UIMenu(title: store.ui("操作", "Actions"), children: actions)]
    }

    private func toolbarAction(_ title: String, enabled: Bool = true, selected: Bool = false,
                               action: @escaping () -> Void) -> UIAction {
        UIAction(title: title, attributes: enabled && !store.settingsPresented ? [] : [.disabled], state: selected ? .on : .off) { _ in action() }
    }

    private func toolbarContent<Content: View>(_ content: Content) -> AnyView {
        AnyView(content
            .disabled(store.settingsPresented)
            .foregroundStyle(secondaryText)
            .environmentObject(store)
            .environmentObject(updateService)
            .environmentObject(libraryDrawer)
            .environmentObject(paneState)
            .environmentObject(interaction)
            .environment(\.weiBeiTextScale, textScale))
    }
#endif

    @ViewBuilder
    private var searchControls: some View {
        ToolbarSearchField(
            text: store.searchesNotes ? $store.noteSearch : $store.readerSearch,
            prompt: searchPrompt,
            focusRequest: paneState.searchFocusRequest,
            height: searchControlHeight,
            width: searchFieldLayoutWidth,
            drawsOwnChrome: searchFieldDrawsOwnChrome,
            onFocusedChange: { searchFieldFocused = $0 },
            onSubmit: {
                if store.searchesNotes { store.noteSearchRequest &+= 1 }
                else if showsReaderSearchResults {
                    moveReaderSearchResult(1, focusResults: true)
                }
            },
            onEscape: {
                store.hideDocumentSearch()
                searchFocused.wrappedValue = false
            },
            onMove: { step in
                if store.searchesNotes { store.noteSearchRequest &+= step }
                else if showsReaderSearchResults { moveReaderSearchResult(step) }
            }
        )
        if showsReaderSearchResults {
            Text(readerSearchResultStatus)
                .weiBeiText(11, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(readerSearchStatusColor)
                .fixedSize()
                .accessibilityLabel(Text(store.ui("搜索结果：", "Search results: ") + readerSearchResultStatus))
            searchStepButton("chevron.up", help: store.ui("上一个匹配（⇧⌘G）", "Previous match (⇧⌘G)")) { moveReaderSearchResult(-1, focusResults: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!readerSearchResultsReady || paneState.readerSearchResults.isEmpty)
            searchStepButton("chevron.down", help: store.ui("下一个匹配（⌘G）", "Next match (⌘G)")) { moveReaderSearchResult(1, focusResults: true) }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!readerSearchResultsReady || paneState.readerSearchResults.isEmpty)
        }
        if store.searchesNotes && !store.noteSearch.isEmpty {
            if store.noteSearchFound == false {
                Text(store.ui("无匹配", "No matches"))
                    .weiBeiText(11, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .fixedSize()
            }
            searchStepButton("chevron.up", help: store.ui("上一个匹配（⇧⌘G）", "Previous match (⇧⌘G)")) { store.noteSearchRequest &-= 1 }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            searchStepButton("chevron.down", help: store.ui("下一个匹配（⌘G）", "Next match (⌘G)")) { store.noteSearchRequest &+= 1 }
                .keyboardShortcut("g", modifiers: .command)
        }
        searchStepButton("xmark", help: store.ui("关闭查找", "Close search")) {
            store.hideDocumentSearch()
            searchFocused.wrappedValue = false
        }
    }

    private var searchFieldLayoutWidth: CGFloat? {
#if targetEnvironment(macCatalyst)
        searchClusterExpanded ? nil : searchFieldWidth
#else
        searchFieldWidth
#endif
    }

    private var searchClusterExpanded: Bool {
        showsReaderSearchResults || paneState.canReturnToReaderSearchOrigin(for: store.selectedMaterialItem?.id)
    }

    private var searchClusterStroke: Color {
        WeiBeiTheme.hairline.opacity(store.appearanceMode.isDark ? 0.58 : 0.42)
    }

    private var searchClusterHairline: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(store.appearanceMode.isDark ? 0.55 : 0.42))
            .frame(height: 1)
    }

    private var readerSearchStatusColor: Color {
        if readerSearchResultsReady, paneState.readerSearchResults.isEmpty {
            return WeiBeiTheme.tertiaryInk
        }
        return WeiBeiTheme.secondaryInk
    }

    private var readerSearchReturnRow: some View {
        SearchClusterTextRow(
            title: store.ui("回到查找前", "Back to reading position"),
            systemImage: "arrow.uturn.backward",
            accessibilityLabel: store.ui("回到查找前的阅读位置", "Return to reading position before search")
        ) {
            paneState.returnToReaderSearchOrigin()
        }
    }

    private func searchStepButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
#if targetEnvironment(macCatalyst)
        Button(action: action) {
            Image(systemName: systemName)
                .weiBeiText(11, weight: .semibold)
                .frame(width: 22 * textScale, height: 22 * textScale)
                .contentShape(Rectangle())
        }
        .buttonStyle(SearchClusterIconStyle())
        .accessibilityLabel(Text(help))
        .help(help)
#else
        topIconButton(systemName, help: help, action: action)
#endif
    }

    private var showsReaderSearchResults: Bool {
        !store.searchesNotes && store.selectedMaterialItem != nil && !ReaderSearch.cleaned(store.readerSearch).isEmpty
    }

    private var readerSearchResultsReady: Bool {
        paneState.readerSearchResultQuery == ReaderSearch.cleaned(store.readerSearch)
            && paneState.readerSearchResultMaterialID == store.selectedMaterialItem?.id
    }

    private var readerSearchResultStatus: String {
        guard readerSearchResultsReady else { return store.ui("查找中", "Finding…") }
        let count = paneState.readerSearchResults.count
        if count == 0 { return store.ui("无匹配", "No matches") }
        if paneState.readerSearchResultIndex < 0 { return store.ui("\(count) 处", "\(count) \(count == 1 ? "match" : "matches")") }
        return "\(paneState.readerSearchResultIndex + 1) / \(count)"
    }

    private func moveReaderSearchResult(_ step: Int, focusResults: Bool = false) {
        guard readerSearchResultsReady else { return }
        paneState.selectReaderSearchResult(ReaderSearch.matchIndex(current: paneState.readerSearchResultIndex,
            step: step, count: paneState.readerSearchResults.count))
        if focusResults { readerSearchKeyboardFocusRequest &+= 1 }
    }

    @ViewBuilder
    private var readerSearchResultsList: some View {
        if !readerSearchResultsReady {
            searchClusterStatusRow(store.ui("查找中", "Finding…"))
        } else if paneState.readerSearchResults.isEmpty {
            searchClusterStatusRow(store.ui("没有找到匹配", "No matches"))
        } else {
            let results = paneState.readerSearchResults
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results.indices, id: \.self) { index in
                            let result = results[index]
                            if index == 0 || result.location != results[index - 1].location {
                                HStack(spacing: 8) {
                                    Text(compactLocation(result))
                                        .weiBeiText(10, weight: .semibold)
                                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                        .fixedSize()
                                    Rectangle()
                                        .fill(WeiBeiTheme.hairline.opacity(store.appearanceMode.isDark ? 0.55 : 0.42))
                                        .frame(height: 1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.top, index == 0 ? 8 : 10)
                                .padding(.bottom, 2)
                            }
                            SearchResultRow(selected: result.id == paneState.readerSearchResultIndex) {
                                paneState.selectReaderSearchResult(result.id)
                                readerSearchKeyboardFocusRequest &+= 1
                            } label: {
                                highlightedPreview(result)
                            }
                            .id(result.id)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(results.count * 40 + readerSearchLocationCount * 26 + 8), 360))
#if targetEnvironment(macCatalyst)
                .background {
                    CatalystSearchResultsKeyboardBridge(focusRequest: readerSearchKeyboardFocusRequest) { step in
                        moveReaderSearchResult(step, focusResults: true)
                    }
                    .frame(width: 1, height: 1)
                }
#endif
                .onChange(of: paneState.readerSearchResultIndex) { _, index in proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func searchClusterStatusRow(_ title: String) -> some View {
        Text(title)
            .weiBeiText(12)
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    private var readerSearchLocationCount: Int {
        let results = paneState.readerSearchResults
        return results.indices.filter { $0 == 0 || results[$0].location != results[$0 - 1].location }.count
    }

    private func compactLocation(_ result: ReaderSearchResult) -> String {
        readerSearchLocationLabel(result, language: store.interfaceLanguage)
    }

    private func highlightedPreview(_ result: ReaderSearchResult) -> Text {
        let source = result.preview as NSString
        let range = result.matchRange
        guard range.location != NSNotFound, NSMaxRange(range) <= source.length else {
            return Text(result.preview).foregroundColor(WeiBeiTheme.ink)
        }
        let before = source.substring(to: range.location)
        let match = source.substring(with: range)
        let after = source.substring(from: NSMaxRange(range))
        return Text(before).foregroundColor(WeiBeiTheme.ink)
            + Text(match).foregroundColor(WeiBeiTheme.cinnabar).bold()
            + Text(after).foregroundColor(WeiBeiTheme.ink)
    }

    private var trailingControls: some View {
        HStack(spacing: topBarSpacing) {
#if !targetEnvironment(macCatalyst)
            if paneState.showDocumentSearch && shouldShowSearchAction { searchControls }
            if shouldShowSearchAction && !paneState.showDocumentSearch { searchButton }
#else
            if shouldShowSearchAction { searchButton }
#endif

            // Copy-reference is not top-bar chrome: use its configured shortcut, menu, or command palette when needed.

            // Light/dark quick toggle — keeps the active style pair, flips the
            // preference. Command palette stays reachable on ⌘K.
            topIconButton(
                store.appearanceMode.isDark ? "sun.max" : "moon.stars",
                help: store.ui("切换深浅外观", "Toggle Light / Dark")
            ) {
                toggleAppearance()
            }
            .animation(WeiBeiMotion.micro, value: store.appearanceMode.isDark)

            WorkspacePersistStatusDot()

            // Settings stay inside the current workspace in every window mode.
            topIconButton("gearshape", help: store.ui("打开设置", "Open Settings")) {
                showSettings()
            }

        }
    }

    private var customTopBar: some View {
        HStack(spacing: topBarSpacing) {
            Spacer()
                .frame(width: leftInset)

            leftPrimaryControls

            Spacer(minLength: 0)

            trailingControls

            Spacer()
                .frame(width: 8)
        }
        .foregroundStyle(secondaryText)
        .offset(y: isFullScreen ? 0 : -2)
        .frame(height: barHeight)
        .background(topBarBackground)
        .overlay {
            paneToggleCluster
                .offset(y: isFullScreen ? 0 : -2)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -5)
        .onAppear {
            withAnimation(WeiBeiMotion.reveal) {
                appeared = true
            }
        }
        .animation(WeiBeiMotion.layout, value: isImmersiveLayout)
        // Pane toggle active states live on paneState — keep this chrome reactive without ContentView.
        .animation(WeiBeiMotion.panel, value: paneState.showReader)
        .animation(WeiBeiMotion.panel, value: paneState.showAgent)
        .animation(WeiBeiMotion.panel, value: paneState.showNotes)
    }

    private func showSettings() {
        store.settingsPresented = true
    }

    private func toggleAppearance() {
        store.appearancePreference = store.appearanceMode.isDark ? .light : .dark
    }

    private var barHeight: CGFloat {
        WeiBeiMetric.topBarHeight * textScale
    }

    private var leftInset: CGFloat {
        CGFloat(TopBarLeadingInset.value(isFullScreen: isFullScreen))
    }

    private var topBarSpacing: CGFloat {
        7
    }

    private var controlHeight: CGFloat {
        28 * textScale
    }

    private var searchFieldDrawsOwnChrome: Bool {
#if targetEnvironment(macCatalyst)
        false
#else
        true
#endif
    }

    private var searchFieldWidth: CGFloat {
#if targetEnvironment(macCatalyst)
        170
#else
        220
#endif
    }

    private var searchControlHeight: CGFloat {
#if targetEnvironment(macCatalyst)
        24 * textScale
#else
        controlHeight
#endif
    }

    private var shouldShowSearchAction: Bool {
        store.canSearchCurrentDocument
    }

    private var searchPrompt: String {
        store.searchesNotes ? store.ui("在笔记中查找", "Find in note") : store.ui("在文稿中查找", "Find in document")
    }

    private var primaryText: Color {
        WeiBeiTheme.ink
    }

    private var secondaryText: Color {
        WeiBeiTheme.secondaryInk
    }

    private var tertiaryText: Color {
        WeiBeiTheme.tertiaryInk
    }

    private var controlFill: Color {
        WeiBeiTheme.paperInset.opacity(0.38)
    }

    private var topBarBackground: some View {
        let empty = !paneState.showReader && !paneState.showAgent && !paneState.showNotes
        // Empty board keeps the glow visible through the bar. Open panes paint
        // the same theme surface as the workspace so the system titlebar cannot
        // leave a second strip above NOTE / READ / CHAT.
        return Group {
            if empty || store.appearanceMode.isGlass {
                // Glass legibility comes from the single full-window sheet at the
                // ZStack root — the bar itself must not paint a second layer.
                Color.clear
            } else {
                Color(weiBeiNativeColor: WeiBeiNativePalette.paper(for: store.appearanceMode))
            }
        }
    }

    @ViewBuilder
    private var leftPrimaryControls: some View {
        HStack(spacing: 6) {
            libraryButton

            navigationButtons

            if updateService.showsToolbarControl {
                WeiBeiUpdateControl()
                    .environmentObject(updateService)
                    .environmentObject(store)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
    }

    @ViewBuilder
    private var navigationButtons: some View {
        HStack(spacing: 3) {
            topIconButton("arrow.left", help: store.ui("后退", "Back")) {
                withAnimation(WeiBeiMotion.layout) {
                    store.navigateBackInWorkspace()
                }
            }
            .weiBeiKeyboardShortcut(store.executableChord(for: .navigateBack))
            .disabled(!store.canNavigateBack)

            topIconButton("arrow.right", help: store.ui("前进", "Forward")) {
                withAnimation(WeiBeiMotion.layout) {
                    store.navigateForwardInWorkspace()
                }
            }
            .weiBeiKeyboardShortcut(store.executableChord(for: .navigateForward))
            .disabled(!store.canNavigateForward)
        }
    }

    private var paneToggleCluster: some View {
        WeiBeiSegmentedControl(segments: [
            WeiBeiSegmentedControl.Segment(
                id: "reader",
                systemImage: "doc.text",
                help: store.isPaneToggleActive(.reader) ? store.ui("隐藏文稿", "Hide document") : store.ui("显示文稿", "Show document"),
                isSelected: store.isPaneToggleActive(.reader),
                action: store.toggleReader
            ),
            WeiBeiSegmentedControl.Segment(
                id: "agent",
                systemImage: "bubble.left.and.text.bubble.right",
                help: agentPaneToggleHelp,
                isSelected: store.isPaneToggleActive(.agent),
                action: store.toggleAgent
            ),
            WeiBeiSegmentedControl.Segment(
                id: "notes",
                systemImage: "note.text",
                help: store.isPaneToggleActive(.notes) ? store.ui("隐藏笔记", "Hide notes") : store.ui("显示笔记", "Show notes"),
                isSelected: store.isPaneToggleActive(.notes),
                action: store.toggleNotes
            ),
        ])
    }

    private var agentPaneToggleHelp: String {
        if store.isPaneToggleActive(.agent) {
            return store.ui("隐藏对话", "Hide chat")
        }
        if interaction.selectionContext != nil {
            return store.ui("用当前选区打开对话", "Open chat with current selection")
        }
        return store.ui("显示对话", "Show chat")
    }

    @ViewBuilder
    private var libraryButton: some View {
        topIconButton(
            "sidebar.left",
            help: libraryDrawer.isOpen ? store.ui("收起课程栏", "Hide course sidebar") : store.ui("打开课程栏", "Show course sidebar"),
            active: libraryDrawer.isOpen
        ) {
            store.toggleLibrary()
        }
    }

    @ViewBuilder
    private var searchButton: some View {
        topIconButton("magnifyingglass", help: searchPrompt, active: paneState.showDocumentSearch) {
            toggleReaderSearch()
        }
    }

    private func toggleReaderSearch() {
        if paneState.showDocumentSearch {
            store.hideDocumentSearch()
            searchFocused.wrappedValue = false
        } else {
            store.revealDocumentSearch()
            searchFocused.wrappedValue = true
        }
    }

    private func topIconButton(_ systemName: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24 * textScale, height: 24 * textScale)
                .contentShape(Rectangle())
        }
        .buttonStyle(WeiBeiIconButtonStyle(active: active, size: 24))
        .accessibilityLabel(Text(help))
        .help(help)
    }
}

/// Observes only `ThreePaneReorderState` for live drag chrome + dimming.
private struct ThreePaneWorkspaceChrome: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var paneReorder: ThreePaneReorderState
    @Binding var firstSplit: CGFloat
    @Binding var secondSplit: CGFloat
    @Binding var halfSplit: CGFloat
    let registry: PersistentPaneHostRegistry
    let normalizedOrder: [WorkspacePaneRole]
    let visibleOrder: [WorkspacePaneRole]
    let expansionRequest: PaneExpansionRequest?
    let frames: [CGRect]
    let canvasSize: CGSize
    let onFramesChange: ([WorkspacePaneRole], [CGRect]) -> Void
    let onExpansionRequestHandled: (UUID) -> Void

    var body: some View {
        ZStack {
            StableDocumentWorkspace(
                firstSplit: $firstSplit,
                secondSplit: $secondSplit,
                halfSplit: $halfSplit,
                registry: registry,
                normalizedOrder: normalizedOrder,
                visibleOrder: visibleOrder,
                draggedRole: paneReorder.drag?.role,
                expansionRequest: expansionRequest,
                appearanceMode: store.appearanceMode,
                onFramesChange: onFramesChange,
                onExpansionRequestHandled: onExpansionRequestHandled
            )

            threePaneReorderOverlay
        }
    }

    @ViewBuilder
    private var threePaneReorderOverlay: some View {
        if let drag = paneReorder.drag,
           let sourceIndex = visibleOrder.firstIndex(of: drag.role),
           frames.indices.contains(sourceIndex) {
            let sourceFrame = frames[sourceIndex]
            // drag.targetIndex indexes the complete three-pane order (submission space).
            // Translate it through the role before reading the visible-frame array —
            // indexing frames directly misplaces the highlight once a pane is hidden.
            if let targetIndex = drag.targetIndex,
               let visibleTargetIndex = ThreePaneReorderTargeting.visibleHighlightIndex(
                   completeOrderIndex: targetIndex,
                   completeOrder: normalizedOrder,
                   visibleOrder: visibleOrder
               ),
               frames.indices.contains(visibleTargetIndex) {
                PaneDropTargetView(role: visibleOrder[visibleTargetIndex])
                    .frame(width: frames[visibleTargetIndex].width, height: frames[visibleTargetIndex].height)
                    .position(x: frames[visibleTargetIndex].midX, y: frames[visibleTargetIndex].midY)
            }

            PaneReorderPreviewView(role: drag.role)
                .frame(width: sourceFrame.width, height: sourceFrame.height)
                .clipped()
                .allowsHitTesting(false)
                .opacity(0.11)
                .overlay {
                    Rectangle()
                        .stroke(WeiBeiTheme.cinnabar.opacity(0.22), lineWidth: 1)
                }
                .position(
                    x: sourceFrame.midX + min(max(drag.translation, -canvasSize.width), canvasSize.width),
                    y: sourceFrame.midY
                )
                .shadow(
                    color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.38 : 0.14),
                    radius: 22,
                    y: 12
                )
                .zIndex(8)
        }
    }
}

private struct LayoutContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    /// Pane visibility lives here so document-family show/hide rebuilds order without store thrash.
    @EnvironmentObject private var paneState: WorkspacePaneState
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @StateObject private var paneHostRegistry = PersistentPaneHostRegistry()
    @AppStorage("documentThreePaneFirstSplit") private var firstSplitStorage: Double = 0.34
    @AppStorage("documentThreePaneSecondSplit") private var secondSplitStorage: Double = 0.67
    @AppStorage("documentNotesHalfSplit") private var halfSplitStorage: Double = 0.50
    
    var body: some View {
        Group {
            switch store.layout {
            case .documentAgentNotes, .documentNotesAgent:
                documentPaneLayoutView()
            // Each representable pane host re-insets to the toolbar safe area on
            // its own; the outer ignoresSafeArea does not reach it. Without this
            // the pane container starts at y=40, its toolbar fade mask is nil and
            // content is cut at the toolbar edge. Same rule as StableDocumentWorkspace.
            case .immersiveReading:
                PersistentPaneHost(role: .reader, registry: paneHostRegistry)
                    .ignoresSafeArea(.container, edges: .top)
            case .immersiveConversation:
                PersistentPaneHost(role: .agent, registry: paneHostRegistry)
                    .ignoresSafeArea(.container, edges: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(WeiBeiTransition.layout)
            case .immersiveWriting:
                PersistentPaneHost(role: .notes, registry: paneHostRegistry)
                    .ignoresSafeArea(.container, edges: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(WeiBeiTransition.layout)
        // Document-internal pane toggles must not re-trigger SwiftUI layout animation.
        .animation(WeiBeiMotion.layout, value: store.layout.isImmersiveFamily)
        // Opening the selection float must not animate this workspace. That
        // transaction was rebuilding the reader and painting the document again.
        .animation(nil, value: interaction.agentSurface)
        // Touch pane flags so SwiftUI rebuilds visibleOrder when only paneState publishes.
        .animation(nil, value: paneState.showReader)
        .animation(nil, value: paneState.showAgent)
        .animation(nil, value: paneState.showNotes)
    }

    private var firstSplit: Binding<CGFloat> {
        return numericBinding($firstSplitStorage)
    }

    private var secondSplit: Binding<CGFloat> {
        return numericBinding($secondSplitStorage)
    }

    private var halfSplit: Binding<CGFloat> {
        return numericBinding($halfSplitStorage)
    }

    @ViewBuilder
    private func documentPaneLayoutView() -> some View {
        let order = store.visibleDocumentPaneOrder
        GeometryReader { geometry in
            let fallbackFrames = estimatedDocumentPaneFrames(order: order, size: geometry.size)
            let frames = store.threePaneReorderFrameList(order: order, fallback: fallbackFrames)
            ZStack {
                // Drag chrome observes ThreePaneReorderState separately so live drag
                // does not rebuild this workspace through WorkspaceStore.
                ThreePaneWorkspaceChrome(
                    firstSplit: firstSplit,
                    secondSplit: secondSplit,
                    halfSplit: halfSplit,
                    registry: paneHostRegistry,
                    normalizedOrder: store.normalizedThreePaneOrder,
                    visibleOrder: order,
                    expansionRequest: store.paneExpansionRequest,
                    frames: frames,
                    canvasSize: geometry.size,
                    onFramesChange: { reportedOrder, frames in
                        store.updateThreePaneReorderFrames(order: reportedOrder, frames: frames)
                    },
                    onExpansionRequestHandled: { requestID in
                        store.completePaneExpansionRequest(requestID)
                    }
                )
            }
        }
    }

    // 与 StableDocumentSplitCoordinator.dividerWidth 保持一致,真实布局由那边决定
    private static let estimatedDividerWidth: CGFloat = 10

    private func estimatedDocumentPaneFrames(order: [WorkspacePaneRole], size: CGSize) -> [CGRect] {
        switch order.count {
        case 0:
            return []
        case 1:
            return [CGRect(origin: .zero, size: size)]
        case 2:
            return twoPaneFrames(order: order, size: size)
        default:
            return threePaneFrames(order: Array(order.prefix(3)), size: size)
        }
    }

    private func minimumWidth(for _: WorkspacePaneRole) -> CGFloat {
        ContentRailMetrics.railOnlyWidth
    }

    private func threePaneFrames(order: [WorkspacePaneRole], size: CGSize) -> [CGRect] {
        let divider = Self.estimatedDividerWidth
        let usable = max(size.width - 2 * divider, 1)
        let firstMinimum = minimumWidth(for: order[0])
        let secondMinimum = minimumWidth(for: order[1])
        let thirdMinimum = minimumWidth(for: order[2])
        let firstWidth = clamped(firstSplit.wrappedValue * usable, min: firstMinimum, max: usable - secondMinimum - thirdMinimum)
        let secondWidth = clamped((secondSplit.wrappedValue - firstSplit.wrappedValue) * usable, min: secondMinimum, max: usable - firstWidth - thirdMinimum)
        let thirdWidth = max(thirdMinimum, usable - firstWidth - secondWidth)
        let height = max(size.height, 1)
        return [
            CGRect(x: 0, y: 0, width: firstWidth, height: height),
            CGRect(x: firstWidth + divider, y: 0, width: secondWidth, height: height),
            CGRect(x: firstWidth + divider + secondWidth + divider, y: 0, width: thirdWidth, height: height)
        ]
    }

    private func twoPaneFrames(order: [WorkspacePaneRole], size: CGSize) -> [CGRect] {
        let divider = Self.estimatedDividerWidth
        let usable = max(size.width - divider, 1)
        let firstMinimum = minimumWidth(for: order[0])
        let secondMinimum = minimumWidth(for: order[1])
        let firstWidth = clamped(halfSplit.wrappedValue * usable, min: firstMinimum, max: usable - secondMinimum)
        let secondWidth = max(secondMinimum, usable - firstWidth)
        let height = max(size.height, 1)
        return [
            CGRect(x: 0, y: 0, width: firstWidth, height: height),
            CGRect(x: firstWidth + divider, y: 0, width: secondWidth, height: height)
        ]
    }

    private func clamped(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), Swift.max(min, max))
    }

    private func numericBinding(_ storage: Binding<Double>) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(storage.wrappedValue) },
            set: { storage.wrappedValue = Double($0) }
        )
    }

}

struct OwnerToken: Equatable {
    let role: WorkspacePaneRole
    let generation: Int
}

#if !targetEnvironment(macCatalyst)
final class PersistentPaneHostRegistry: ObservableObject {
    private var hosts: [WorkspacePaneRole: NSHostingView<AnyView>] = [:]
    private var latestOwnerGeneration: [WorkspacePaneRole: Int] = [:]
    private var activeOwners: [WorkspacePaneRole: OwnerToken] = [:]
    private var nextOwnerGeneration = 0

    func registerOwner(for role: WorkspacePaneRole) -> OwnerToken {
        nextOwnerGeneration += 1
        let owner = OwnerToken(role: role, generation: nextOwnerGeneration)
        latestOwnerGeneration[role] = owner.generation
        return owner
    }

    func attach(_ role: WorkspacePaneRole, to container: NSView, store: WorkspaceStore, owner: OwnerToken) {
        guard owner.role == role else { return }
        guard latestOwnerGeneration[role] == owner.generation else { return }
        let host = host(for: role, store: store)
        activeOwners[role] = owner
        guard host.superview !== container else {
            host.frame = container.bounds
            return
        }

        host.removeFromSuperview()
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
    }

    func detach(_ role: WorkspacePaneRole, from container: NSView, owner: OwnerToken) {
        guard let host = hosts[role] else { return }
        guard activeOwners[role] == owner, host.superview === container else { return }
        host.removeFromSuperview()
        activeOwners[role] = nil
    }

    private func host(for role: WorkspacePaneRole, store: WorkspaceStore) -> NSHostingView<AnyView> {
        if let host = hosts[role] {
            return host
        }

        let root = PersistentPaneRoot(role: role)
            .environmentObject(store)
            .environmentObject(store.paneState)
            .environmentObject(store.interaction)
            .environmentObject(store.threePaneReorder)
            .environmentObject(store.libraryDrawer)
        // Same rule as StableDocumentDividerView / ContentRail: pane content must not
        // initiate isMovableByWindowBackground. Reader/notes often hide this via nested
        // AppKit (PDFView/NSTextView); agent chat is mostly SwiftUI so it needs the host flag.
        let host = PaneContentHostingView(rootView: AnyView(root))
        host.identifier = NSUserInterfaceItemIdentifier("persistent-pane-\(role.rawValue)")
        host.autoresizingMask = [.width, .height]
        hosts[role] = host
        return host
    }
}

/// NSHostingView that keeps pane drags (header reorder, scroll, text) from moving the window.
private final class PaneContentHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class PersistentPaneContainerView: NSView {
    var onWindowChange: ((PersistentPaneContainerView) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(self)
    }
}

struct PersistentPaneHost: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    let role: WorkspacePaneRole
    let registry: PersistentPaneHostRegistry

    func makeCoordinator() -> Coordinator {
        Coordinator(role: role, registry: registry)
    }

    func makeNSView(context: Context) -> PersistentPaneContainerView {
        let container = PersistentPaneContainerView()
        container.isHidden = store.courseWorkspacePresented
        container.onWindowChange = { [weak coordinator = context.coordinator] container in
            coordinator?.windowChanged(container)
        }
        context.coordinator.update(role: role, registry: registry, store: store, container: container)
        return container
    }

    func updateNSView(_ container: PersistentPaneContainerView, context: Context) {
        container.isHidden = store.courseWorkspacePresented
        context.coordinator.update(role: role, registry: registry, store: store, container: container)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: PersistentPaneContainerView,
        context: Context
    ) -> CGSize? {
        guard
            let width = proposal.width,
            let height = proposal.height,
            width.isFinite,
            height.isFinite,
            width >= 0,
            height >= 0
        else { return nil }
        // The native pane split owns this exact frame. Falling back to the
        // container's fittingSize recursively measures its entire hosted pane,
        // including every visible Markdown, table, and formula view on scroll.
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ container: PersistentPaneContainerView, coordinator: Coordinator) {
        container.onWindowChange = nil
        coordinator.detach(from: container)
    }

    final class Coordinator {
        private var role: WorkspacePaneRole
        private var registry: PersistentPaneHostRegistry
        private var owner: OwnerToken?
        private weak var store: WorkspaceStore?

        init(role: WorkspacePaneRole, registry: PersistentPaneHostRegistry) {
            self.role = role
            self.registry = registry
        }

        func update(role: WorkspacePaneRole, registry: PersistentPaneHostRegistry, store: WorkspaceStore, container: PersistentPaneContainerView) {
            if self.role != role || self.registry !== registry {
                detach(from: container)
                self.role = role
                self.registry = registry
            }
            self.store = store
            attachIfVisible(to: container)
        }

        func windowChanged(_ container: PersistentPaneContainerView) {
            guard container.window != nil else {
                detach(from: container)
                return
            }
            owner = nil
            attachIfVisible(to: container)
        }

        private func attachIfVisible(to container: PersistentPaneContainerView) {
            guard container.window != nil else { return }
            guard let store else { return }
            if owner == nil {
                owner = registry.registerOwner(for: role)
            }
            guard let owner else { return }
            registry.attach(role, to: container, store: store, owner: owner)
        }

        func detach(from container: NSView) {
            guard let owner else { return }
            registry.detach(role, from: container, owner: owner)
            self.owner = nil
        }
    }
}

#endif

struct PersistentPaneRoot: View {
    @EnvironmentObject private var store: WorkspaceStore
    let role: WorkspacePaneRole

    var body: some View {
        Group {
#if targetEnvironment(macCatalyst)
            if #available(iOS 26.0, *) {
                pane.scrollEdgeEffectHidden(true, for: .top)
            } else {
                pane
            }
#else
            pane
#endif
        }
#if targetEnvironment(macCatalyst)
            .environment(\.weiBeiTextScale, store.interfaceTextScale.multiplier)
            .weiBeiMotionScoped()
            .preferredColorScheme(store.appearanceMode.colorScheme)
#endif
    }

    @ViewBuilder
    private var pane: some View {
        switch role {
        case .reader:
            ReaderView(
                isImmersive: store.layout == .immersiveReading,
                showsFloatingTitle: true,
                floatingTitleReorderRole: reorderRole
            )
            .frame(minHeight: 280)
            .foregroundStyle(WeiBeiTheme.ink)
            .background(WeiBeiTheme.paper)
        case .agent:
            AgentPaneView(showsPaneHeader: false, reorderRole: reorderRole)
        case .notes:
            NotePaneView(showsPaneHeader: false, reorderRole: reorderRole)
        }
    }

    private var reorderRole: WorkspacePaneRole? {
        guard store.visibleDocumentPaneOrder.count > 1 else { return nil }
        switch store.layout {
        case .documentAgentNotes, .documentNotesAgent:
            return role
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return nil
        }
    }
}

private struct PaneReorderPreviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let role: WorkspacePaneRole

    var body: some View {
        ZStack(alignment: .topLeading) {
            WeiBeiTheme.paper
            HStack(spacing: 7) {
                Image(systemName: role.systemImage)
                    .weiBeiText(12, weight: .semibold)
                Text(role.label(language: store.interfaceLanguage))
                    .weiBeiText(12, weight: .semibold)
            }
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
    }
}

private struct PaneDropTargetView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var role: WorkspacePaneRole

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode.isDark ? 0.16 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(WeiBeiTheme.cinnabar.opacity(0.30), lineWidth: 1)
                    .padding(8)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 7) {
                    Image(systemName: role.systemImage)
                        .weiBeiText(12, weight: .semibold)
                    Text(role.label(language: store.interfaceLanguage))
                        .weiBeiText(12, weight: .semibold)
                }
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .weibeiEtchedCapsuleBackground(
                    fill: WeiBeiTheme.paperRaised.opacity(0.72),
                    stroke: WeiBeiTheme.hairline.opacity(0.4),
                    contactShadow: true
                )
                .clipShape(Capsule())
                .padding(14)
            }
            .allowsHitTesting(false)
    }
}

struct WeiBeiDroppedFileResult {
    var urls: [URL] = []
    var securityScopedURLs: [URL] = []
    var temporaryDirectories: [URL] = []
    var failures: [String] = []

    func release() {
        securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        WeiBeiDroppedFileURLs.removeTemporaryDirectories(temporaryDirectories)
    }
}

enum WeiBeiDroppedFileURLs {
    /// A cross-app URL is metadata, not permission to read the source app's
    /// private directory. Receive its file representation through UIKit and
    /// retain an owned copy before the provider's completion handler returns.
    static func loadTransferredFiles(_ providers: [NSItemProvider], sourceURLs: [URL],
        completion: @escaping (WeiBeiDroppedFileResult) -> Void) -> Bool {
        guard !providers.isEmpty else { return false }
        let lock = NSLock()
        var results = Array(repeating: WeiBeiDroppedFileResult(), count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            // Promised files have no URL yet, so a mixed drag's URL list is
            // sparse. Do not assign another provider's name or content type.
            let metadata = sourceURLs.count == providers.count ? sourceURLs[index] : nil
            let preferredType = metadata.flatMap { UTType(filenameExtension: $0.pathExtension) }
            let contentType: String?
            if let preferredType, provider.hasItemConformingToTypeIdentifier(preferredType.identifier) {
                contentType = preferredType.identifier
            } else {
                contentType = provider.registeredTypeIdentifiers.first {
                    guard let type = UTType($0), !type.conforms(to: .url) else { return false }
                    return type == .folder || type.conforms(to: .content) || type.conforms(to: .data)
                }
            }
            guard contentType != nil || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                lock.lock()
                results[index].failures = [provider.suggestedName ?? "file representation unavailable"]
                lock.unlock()
                continue
            }
            group.enter()
            let receive: (URL?, Error?) -> Void = { url, error in
                var result = WeiBeiDroppedFileResult()
                var directory: URL?
                do {
                    if let error { throw error }
                    guard let url, url.isFileURL else { throw CocoaError(.fileReadUnknown) }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let owned = FileManager.default.temporaryDirectory.appendingPathComponent(
                        "WeiBeiDroppedFiles-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false,
                        attributes: [.posixPermissions: 0o700])
                    directory = owned
                    let name = metadata?.lastPathComponent
                        ?? provider.suggestedName.map { URL(fileURLWithPath: $0).lastPathComponent }
                        ?? url.lastPathComponent
                    guard !name.isEmpty, name != ".", name != ".." else { throw CocoaError(.fileReadInvalidFileName) }
                    let target = owned.appendingPathComponent(name, isDirectory: url.hasDirectoryPath)
                    var coordinationError: NSError?
                    var copyError: Error?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges,
                        error: &coordinationError) { readableURL in
                        do {
                            if let html = try HTMLResourceImport.dataIfHTML(at: readableURL) {
                                try html.write(to: target, options: .withoutOverwriting)
                            } else {
                                try FileManager.default.copyItem(at: readableURL, to: target)
                            }
                        } catch { copyError = error }
                    }
                    if let coordinationError { throw coordinationError }
                    if let copyError { throw copyError }
                    guard FileManager.default.fileExists(atPath: target.path) else { throw CocoaError(.fileReadUnknown) }
                    result.urls = [target]
                    result.temporaryDirectories = [owned]
                } catch {
                    if let directory { removeTemporaryDirectories([directory]) }
                    result.failures = [error.localizedDescription]
                }
                lock.lock(); results[index] = result; lock.unlock()
                group.leave()
            }
            // Content and file-address representations are distinct source
            // contracts. Prefer exported bytes; never retry a failed export
            // against metadata from the source app's private directory.
            if let contentType {
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: contentType) { url, _, error in
                    receive(url, error)
                }
            } else {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    receive(fileURL(from: item), error)
                }
            }
        }
        group.notify(queue: .main) {
            completion(WeiBeiDroppedFileResult(urls: results.flatMap(\.urls),
                temporaryDirectories: results.flatMap(\.temporaryDirectories), failures: results.flatMap(\.failures)))
        }
        return true
    }

    static func removeTemporaryDirectories(_ directories: [URL]) {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        for directory in directories where directory.lastPathComponent.hasPrefix("WeiBeiDroppedFiles-")
            && directory.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == parent {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Complete even when every item fails: a claimed drop must never disappear silently.
    static func load(_ providers: [NSItemProvider], completion: @escaping (WeiBeiDroppedFileResult) -> Void) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }
        let lock = NSLock()
        var results = Array(repeating: WeiBeiDroppedFileResult(), count: fileProviders.count)
        let group = DispatchGroup()
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                var result = WeiBeiDroppedFileResult()
                if let url = fileURL(from: item) {
                    // Hold access until review/import/cancel finishes, just like the file chooser.
                    if url.startAccessingSecurityScopedResource() { result.securityScopedURLs = [url] }
                    result.urls = [url]
                } else {
                    result.failures = [error?.localizedDescription ?? provider.suggestedName ?? "public.file-url"]
                }
                lock.lock()
                results[index] = result
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(WeiBeiDroppedFileResult(
                urls: results.flatMap(\.urls),
                securityScopedURLs: results.flatMap(\.securityScopedURLs),
                failures: results.flatMap(\.failures)
            ))
        }
        return true
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        let url: URL?
        switch item {
        case let value as URL: url = value
        case let value as Data: url = URL(dataRepresentation: value, relativeTo: nil)
        case let value as String: url = URL(string: value)
        default: url = nil
        }
        guard let url, url.isFileURL, !url.path.isEmpty else { return nil }
        return url
    }
}
