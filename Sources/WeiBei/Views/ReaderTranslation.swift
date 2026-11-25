import SwiftUI
import WeiBeiCore
#if targetEnvironment(macCatalyst)
import UIKit
#else
import AppKit
#endif

struct ReaderTranslationPreferences: DynamicProperty {
    @AppStorage("weibei.readerTranslation.connection") private var connectionID = ""
    @AppStorage("weibei.readerTranslation.language") private var languageID = ""

    var connection: Binding<String> { $connectionID }
    var language: Binding<String> { $languageID }

    var choices: [String] {
        var seen: Set<String> = []
        return (["zh-Hans", "en", "zh-Hant"] + Locale.preferredLanguages)
            .filter { seen.insert($0).inserted }
    }

    @MainActor
    func service(in store: WorkspaceStore, selectedConnection: String? = nil) -> ReaderTranslationService? {
        let connectionID = selectedConnection ?? connectionID
        let targetID = languageID.isEmpty ? store.interfaceLanguage.rawValue : languageID
        let target = Locale(identifier: "en").localizedString(forIdentifier: targetID) ?? targetID
        if connectionID.isEmpty {
            return ReaderTranslationService(
                provider: store.agentProviderID, model: store.modelName, baseURL: store.agentBaseURL,
                authMethod: store.agentAuthMethod, targetLanguage: target
            )
        }
        guard let profile = store.agentCredentialProfiles.first(where: { $0.id.uuidString == connectionID }) else {
            return nil
        }
        return ReaderTranslationService(
            provider: profile.provider, model: profile.modelName, baseURL: profile.baseURL,
            authMethod: profile.authMethod, targetLanguage: target
        )
    }
}

struct ReaderTranslationContext: Equatable {
    let itemID: String
    let revision: UInt64
    let attempt: UUID
    let service: ReaderTranslationService
}

enum ReaderTranslationProblem: Error, Equatable {
    case missingConnection, connectionChanged, missingModel, unauthorized, rateLimited, insufficientQuota, offline, incomplete, failed

    init(_ error: Error) {
        if let error = error as? ReaderTranslationService.Failure {
            self = error == .missingModel ? .missingModel : .incomplete
        } else if let error = error as? NativeLLMFailure {
            switch error.asAgentFailureKind {
            case .unauthorized: self = .unauthorized
            case .rateLimited: self = .rateLimited
            case .insufficientQuota: self = .insufficientQuota
            case .modelUnavailable: self = .missingModel
            case .offline, .timedOut: self = .offline
            case .truncated: self = .incomplete
            default: self = .failed
            }
        } else if let error = error as? URLError, error.code == .notConnectedToInternet {
            self = .offline
        } else if error is AgentProviderEndpointError {
            self = .missingConnection
        } else {
            self = .failed
        }
    }

    var needsConnection: Bool {
        self == .missingConnection || self == .missingModel || self == .unauthorized
    }

    func message(_ language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .missingConnection:
            language.text("翻译连接不可用。请在翻译菜单中选择连接。", "The translation connection is unavailable. Choose a connection in the translation menu.")
        case .connectionChanged:
            language.text("翻译连接已变更。", "The translation connection has changed.")
        case .missingModel:
            language.text("请先为翻译连接选择模型。", "Choose a model for the translation connection.")
        case .unauthorized:
            language.text("翻译服务未通过验证，请检查连接凭据。", "The translation service could not authenticate. Check the connection credentials.")
        case .rateLimited:
            language.text("翻译服务请求过多，请稍后重试。", "The translation service is receiving too many requests. Try again shortly.")
        case .insufficientQuota:
            language.text("翻译服务额度不足，请查看服务商账户。", "The translation service has run out of quota. Check your provider account.")
        case .offline:
            language.text("翻译服务暂时无法连接。", "The translation service is unreachable.")
        case .incomplete:
            language.text("模型返回的译文不完整。", "The model returned an incomplete translation.")
        case .failed:
            language.text("翻译失败，请检查服务或重试。", "Translation failed. Check the service or try again.")
        }
    }
}

enum ReaderTranslationStatus: Equatable {
    case idle, translating, noText, ready, failed(ReaderTranslationProblem)
}

struct ReaderTranslationMenu: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var enabled: Bool
    @Binding var presented: Bool
    var status: ReaderTranslationStatus
    var retry: () -> Void
    var onConnectionChange: (ReaderTranslationService?) -> Void
    var showsLabel = false
    private var problem: ReaderTranslationProblem? {
        if case let .failed(problem) = status { return problem }
        return nil
    }

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "character.bubble")
                if showsLabel { Text(store.ui("双语", "Bilingual")) }
            }
                .weiBeiText(13, weight: .medium)
                .foregroundStyle(enabled ? WeiBeiTheme.accent : WeiBeiTheme.secondaryInk)
                .padding(.horizontal, showsLabel ? 6 : 0)
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(store.ui("双语阅读", "Bilingual reading")))
        .accessibilityValue(enabled ? store.ui("开启", "On") : store.ui("关闭", "Off"))
        .help(problem?.message(store.interfaceLanguage) ?? store.ui("双语阅读", "Bilingual reading"))
        .popover(isPresented: $presented) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(store.ui("双语阅读", "Bilingual reading"), isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                ReaderTranslationOptions(manageConnections: openConnectionSettings, onConnectionChange: onConnectionChange)
                if enabled {
                    switch status {
                    case .translating:
                        Text(store.ui("正在翻译…", "Translating…"))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                    case .noText:
                        Text(store.ui("当前阅读位置没有可翻译的段落。", "There are no translatable paragraphs at the current reading position."))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                    case let .failed(problem):
                        ReaderTranslationProblemView(problem: problem, retry: retry)
                    case .idle, .ready:
                        EmptyView()
                    }
                } else {
                    Text(store.ui("开启后，当前阅读位置的文字会发给所选服务。", "When on, text at the current reading position is sent to the selected service."))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
            }
            .weiBeiText(12)
            .padding(14)
            .frame(width: 300)
            .environmentObject(store)
        }
    }

    private func openConnectionSettings() {
        presented = false
        store.settingsPresented = true
    }
}

private struct ReaderTranslationOptions: View {
    @EnvironmentObject private var store: WorkspaceStore
    private var preferences = ReaderTranslationPreferences()
    var manageConnections: () -> Void
    var onConnectionChange: (ReaderTranslationService?) -> Void

    init(manageConnections: @escaping () -> Void,
         onConnectionChange: @escaping (ReaderTranslationService?) -> Void) {
        self.manageConnections = manageConnections
        self.onConnectionChange = onConnectionChange
    }

    var body: some View {
        Picker(store.ui("译为", "Translate to"), selection: preferences.language) {
            Text(store.ui("跟随界面语言", "Interface language")).tag("")
            ForEach(preferences.choices, id: \.self) { id in
                Text(Locale(identifier: id).localizedString(forIdentifier: id) ?? id).tag(id)
            }
            if !preferences.language.wrappedValue.isEmpty,
               !preferences.choices.contains(preferences.language.wrappedValue) {
                let id = preferences.language.wrappedValue
                Text(Locale(identifier: id).localizedString(forIdentifier: id) ?? id).tag(id)
            }
        }
        Picker(store.ui("连接", "Connection"), selection: Binding(
            get: { preferences.connection.wrappedValue },
            set: { id in
                preferences.connection.wrappedValue = id
                onConnectionChange(preferences.service(in: store, selectedConnection: id))
            }
        )) {
            Text(store.ui("当前模型连接", "Current model connection")).tag("")
            ForEach(store.agentCredentialProfiles) { profile in
                Text(profile.name).tag(profile.id.uuidString)
            }
            if !preferences.connection.wrappedValue.isEmpty,
               !store.agentCredentialProfiles.contains(where: { $0.id.uuidString == preferences.connection.wrappedValue }) {
                Text(store.ui("连接不可用", "Connection unavailable")).tag(preferences.connection.wrappedValue)
            }
        }
        Button(store.ui("管理模型连接…", "Manage model connections…"), action: manageConnections)
        .buttonStyle(.plain)
        .foregroundStyle(WeiBeiTheme.link)
    }
}

struct ReaderTranslationProblemView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var problem: ReaderTranslationProblem
    var offersSettings = false
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(problem.message(store.interfaceLanguage))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            if problem.needsConnection {
                if offersSettings {
                    Button(store.ui("打开设置", "Open Settings")) { store.settingsPresented = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(WeiBeiTheme.link)
                }
            } else {
                Button(problem == .connectionChanged
                    ? store.ui("用当前连接继续", "Continue with current connection")
                    : store.ui("重试", "Try again"), action: retry)
                    .buttonStyle(.plain)
                    .foregroundStyle(WeiBeiTheme.link)
            }
        }
    }
}

struct ReaderSelectionTranslationButton: View {
    @EnvironmentObject private var store: WorkspaceStore
    let selection: SelectionContext
    private var preferences = ReaderTranslationPreferences()

    init(selection: SelectionContext) {
        self.selection = selection
    }

    var body: some View {
        Button {
            guard let item = store.selectedMaterialItem, item.id == selection.itemID,
                  let anchor = store.interaction.selectionAnchor else { return }
            store.interaction.readerSelectionTranslation = ReaderSelectionTranslationRequest(
                revision: item.contentRevision, selection: selection, anchor: anchor,
                service: preferences.service(in: store)
            )
            store.dismissFloatingSelectionAgent()
        } label: {
            Text(store.ui("译", "Translate"))
        }
        .accessibilityLabel(Text(store.ui("翻译选中文字", "Translate selected text")))
        .help(store.ui("翻译选中文字", "Translate selected text"))
    }
}

struct ReaderSelectionTranslationAnnotation: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weiBeiTextScale) private var textScale
    let request: ReaderSelectionTranslationRequest
    let dismiss: () -> Void
    @State private var result: Result<String, ReaderTranslationProblem>?
    @State private var readerBounds: CGRect?
    @State private var scrollableResultBounds = CGRect.null

    init(request: ReaderSelectionTranslationRequest, dismiss: @escaping () -> Void) {
        self.request = request
        self.dismiss = dismiss
    }

    var body: some View {
        GeometryReader { geometry in
            if let readerBounds {
                let point = CGPoint(x: request.anchor.x - readerBounds.minX, y: request.anchor.y - readerBounds.minY)
                if geometry.size.width > 16, geometry.size.height > 16 {
                    ReaderSelectionAnnotationLayout(
                        point: point, prefersAbove: request.anchor.prefersAbove,
                        selectionHeight: request.anchor.selectionHeight ?? 18 * textScale,
                        readableWidth: 320 * textScale
                    ) {
                        ViewThatFits(in: .vertical) {
                            message.fixedSize(horizontal: false, vertical: true).allowsHitTesting(false)
                            ScrollView {
                                message.textSelection(.enabled)
                            }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(request.id)) } action: {
                                scrollableResultBounds = $0
                            }
                            .onDisappear { scrollableResultBounds = .null }
                        }
                        .weiBeiText(13)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(WeiBeiTheme.paperRaised)
                                .allowsHitTesting(false)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(WeiBeiTheme.hairline.opacity(0.6), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: request.id)
        .background {
            ReaderSelectionAnnotationProbe(anchor: request.anchor) { bounds in
                if let readerBounds, readerBounds != bounds { dismiss() }
                else { readerBounds = bounds }
            } onInteraction: { point in
                if !scrollableResultBounds.contains(point) { dismiss() }
            } onDocumentScroll: { dismiss() }
            .accessibilityHidden(true)
        }
        .task {
            guard let service = request.service else {
                result = .failure(.missingConnection)
                return
            }
            do {
                guard let text = try await service.translate([request.selection.text]).first else {
                    throw ReaderTranslationService.Failure.invalidTranslation
                }
                try Task.checkCancellation()
                result = .success(text)
            } catch {
                guard !Task.isCancelled else { return }
                result = .failure(ReaderTranslationProblem(error))
            }
        }
    }

    @ViewBuilder
    private var message: some View {
        switch result {
        case let .success(text): Text(verbatim: text).foregroundStyle(WeiBeiTheme.ink)
        case let .failure(problem): Text(problem.message(store.interfaceLanguage)).foregroundStyle(WeiBeiTheme.secondaryInk)
        case nil: Text(store.ui("翻译中…", "Translating…")).foregroundStyle(WeiBeiTheme.secondaryInk)
        }
    }
}

private struct ReaderSelectionAnnotationLayout: Layout {
    let point: CGPoint
    let prefersAbove: Bool
    let selectionHeight: CGFloat
    let readableWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let annotation = subviews.first, bounds.width > 16, bounds.height > 16 else { return }
        let area = bounds.insetBy(dx: 8, dy: 8)
        let anchor = CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y)
        let aboveEdge = min(area.maxY, anchor.y - (prefersAbove ? 0 : selectionHeight) - 4)
        let belowEdge = max(area.minY, anchor.y + (prefersAbove ? selectionHeight : 0) + 4)
        let aboveRoom = max(0, aboveEdge - area.minY)
        let belowRoom = max(0, area.maxY - belowEdge)
        let width = min(readableWidth, area.width)
        let ideal = annotation.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let preferredRoom = prefersAbove ? aboveRoom : belowRoom
        let useAbove = ideal.height <= preferredRoom ? prefersAbove : aboveRoom > belowRoom
        let room = useAbove ? aboveRoom : belowRoom
        // A selection across the whole viewport may have both endpoints offscreen.
        let availableHeight = room >= min(20, ideal.height) ? room : area.height
        let positionProposal = ProposedViewSize(width: min(width, ideal.width),
            height: min(ideal.height, availableHeight, area.height / 3))
        let size = annotation.sizeThatFits(positionProposal)
        let x = min(max(anchor.x - size.width / 2, area.minX), max(area.minX, area.maxX - size.width))
        let y = min(max(useAbove ? aboveEdge - size.height : belowEdge, area.minY), area.maxY - size.height)
        annotation.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: positionProposal)
    }
}

// Report the reader's origin in the same coordinates as the native selection.
// Observe window input without consuming it, including scrolls in hosted readers.
#if targetEnvironment(macCatalyst)
private struct ReaderSelectionAnnotationProbe: UIViewRepresentable {
    let anchor: SelectionPopoverAnchor
    var onBoundsChange: (CGRect) -> Void
    var onInteraction: (CGPoint) -> Void
    var onDocumentScroll: () -> Void

    func makeUIView(context: Context) -> ReaderSelectionAnnotationProbeView {
        let view = ReaderSelectionAnnotationProbeView()
        view.isUserInteractionEnabled = false
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: ReaderSelectionAnnotationProbeView, context: Context) {
        view.anchor = anchor
        view.onBoundsChange = onBoundsChange
        view.onInteraction = onInteraction
        view.onDocumentScroll = onDocumentScroll
    }

    static func dismantleUIView(_ view: ReaderSelectionAnnotationProbeView, coordinator: ()) {
        view.detach()
    }
}

private final class ReaderSelectionAnnotationProbeView: UIView, UIGestureRecognizerDelegate {
    var anchor: SelectionPopoverAnchor?
    var onBoundsChange: (CGRect) -> Void = { _ in }
    var onInteraction: (CGPoint) -> Void = { _ in }
    var onDocumentScroll: () -> Void = {}
    private var reportedBounds: CGRect?
    private weak var observationWindow: UIWindow?
    private var scrollObservations: [NSKeyValueObservation] = []
    private lazy var observers: [UIGestureRecognizer] = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(interacted(_:)))
        let secondaryTap = UITapGestureRecognizer(target: self, action: #selector(interacted(_:)))
        secondaryTap.buttonMaskRequired = .secondary
        let pan = UIPanGestureRecognizer(target: self, action: #selector(interacted(_:)))
        pan.allowedScrollTypesMask = .all
        let observers: [UIGestureRecognizer] = [tap, secondaryTap, pan]
        for observer in observers {
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            observer.delegate = self
        }
        return observers
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        observationWindow = window
        if let window {
            for observer in observers { window.addGestureRecognizer(observer) }
        }
        reportBounds()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportBounds()
    }

    func detach() {
        scrollObservations.removeAll()
        reportedBounds = nil
        guard let observationWindow else { return }
        for observer in observers { observationWindow.removeGestureRecognizer(observer) }
        self.observationWindow = nil
    }

    private func reportBounds() {
        guard !bounds.isEmpty, let origin = SelectionAnchorContentPoint.fromLocalPoint(bounds.origin, in: self) else { return }
        let rect = CGRect(origin: CGPoint(x: origin.x, y: origin.y), size: bounds.size)
        guard rect != reportedBounds else { return }
        reportedBounds = rect
        DispatchQueue.main.async { [weak self] in
            guard let self, reportedBounds == rect else { return }
            observeScrollViews(at: rect)
            onBoundsChange(rect)
        }
    }

    private func observeScrollViews(at rect: CGRect) {
        scrollObservations.removeAll()
        guard let anchor, let window else { return }
        let point = CGPoint(
            x: min(max(1, anchor.x - rect.minX), max(1, rect.width - 1)),
            y: min(max(1, anchor.y - rect.minY + (anchor.prefersAbove ? 1 : -1)), max(1, rect.height - 1))
        )
        var view = window.hitTest(convert(point, to: window), with: nil)
        while let ancestor = view {
            if let scroll = ancestor as? UIScrollView {
                scrollObservations.append(scroll.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
                    if change.oldValue != change.newValue {
                        DispatchQueue.main.async { [weak self] in self?.onDocumentScroll() }
                    }
                })
            }
            view = ancestor.superview
        }
    }

    @objc private func interacted(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began || gesture.state == .ended {
            onInteraction(gesture.location(in: self))
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
#else
private struct ReaderSelectionAnnotationProbe: NSViewRepresentable {
    let anchor: SelectionPopoverAnchor
    var onBoundsChange: (CGRect) -> Void
    var onInteraction: (CGPoint) -> Void
    var onDocumentScroll: () -> Void

    func makeNSView(context: Context) -> ReaderSelectionAnnotationProbeView {
        let view = ReaderSelectionAnnotationProbeView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ReaderSelectionAnnotationProbeView, context: Context) {
        view.anchor = anchor
        view.onBoundsChange = onBoundsChange
        view.onInteraction = onInteraction
        view.onDocumentScroll = onDocumentScroll
    }

    static func dismantleNSView(_ view: ReaderSelectionAnnotationProbeView, coordinator: ()) {
        view.detach()
    }
}

private final class ReaderSelectionAnnotationProbeView: NSView {
    override var isFlipped: Bool { true }
    var anchor: SelectionPopoverAnchor?
    var onBoundsChange: (CGRect) -> Void = { _ in }
    var onInteraction: (CGPoint) -> Void = { _ in }
    var onDocumentScroll: () -> Void = {}
    private var reportedBounds: CGRect?
    private var eventMonitor: Any?
    private var scrollMonitor: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        if window != nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
                if let self, event.window === window {
                    onInteraction(convert(event.locationInWindow, from: nil))
                }
                return event
            }
            scrollMonitor = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, let clip = notification.object as? NSClipView, clip.window === window,
                      let anchor, let readerBounds = reportedBounds else { return }
                let location = CGPoint(x: anchor.x - readerBounds.minX, y: anchor.y - readerBounds.minY)
                if clip.bounds.contains(convert(location, to: clip)) {
                    DispatchQueue.main.async { [weak self] in self?.onDocumentScroll() }
                }
            }
        }
        reportBounds()
    }

    override func layout() {
        super.layout()
        reportBounds()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func detach() {
        reportedBounds = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let scrollMonitor {
            NotificationCenter.default.removeObserver(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func reportBounds() {
        guard !bounds.isEmpty, let origin = SelectionAnchorContentPoint.fromLocalPoint(bounds.origin, in: self) else { return }
        let rect = CGRect(origin: CGPoint(x: origin.x, y: origin.y), size: bounds.size)
        guard rect != reportedBounds else { return }
        reportedBounds = rect
        DispatchQueue.main.async { [weak self] in self?.onBoundsChange(rect) }
    }
}
#endif
