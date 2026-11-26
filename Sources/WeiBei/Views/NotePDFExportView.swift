import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct NotePDFExportRequest: Identifiable {
    let itemID: String
    var id: String { itemID }
}

struct NotePDFExportMenuItem: View {
    @EnvironmentObject private var store: WorkspaceStore
    let itemID: String

    var body: some View {
        Button {
            store.notePDFExportRequest = NotePDFExportRequest(itemID: itemID)
        } label: {
            Label(store.ui("导出 PDF…", "Export PDF…"), systemImage: "square.and.arrow.up")
        }
    }
}

struct NotePDFExportView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let request: NotePDFExportRequest
    private let defaultOptions: NotePDFOptions
    @State private var options: NotePDFOptions
    @State private var source: NotePDFSource?
    @State private var rendered: Rendered?
    @State private var section: Section = .style
    @State private var showsLayoutOptions = false
    @State private var showsFileExporter = false
    @State private var renderError: String?
    @State private var saveError = false
    @State private var retry = 0

    private enum Section: CaseIterable { case style, page }

    private struct Rendered {
        let options: NotePDFOptions
        let file: ExportFile
        let document: PDFDocument
    }

    private struct RenderRequest: Equatable {
        let options: NotePDFOptions
        let retry: Int
    }

    init(request: NotePDFExportRequest, theme: WeiBeiAppearanceMode, textScale: CGFloat) {
        self.request = request
        let defaults = NotePDFOptions(theme: theme, textScale: textScale)
        defaultOptions = defaults
        _options = State(initialValue: defaults)
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 600 {
                HStack(alignment: .top, spacing: 24) {
                    previewColumn
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        inspector.frame(maxHeight: .infinity, alignment: .top)
                        actions
                    }
                    .frame(width: 248)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    previewColumn
                    inspector.frame(height: showsLayoutOptions ? geometry.size.height * 0.44 : nil)
                    actions
                }
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 780, minHeight: 490, idealHeight: 640)
        .foregroundStyle(WeiBeiTheme.ink)
        .background {
            if store.appearanceMode.isGlass {
                Rectangle().fill(.regularMaterial)
            }
        }
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .weiBeiFittedSheet()
        .task(id: RenderRequest(options: options, retry: retry)) {
            await updatePreview(for: options)
        }
        .fileExporter(isPresented: $showsFileExporter,
                      document: rendered?.file,
                      contentType: .pdf,
                      defaultFilename: source.map { store.safeFileStem($0.title) }) { result in
            switch result {
            case .success: dismiss()
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { saveError = true }
            }
        }
        .alert(store.ui("PDF 未能保存", "PDF Could Not Be Saved"), isPresented: $saveError) {
            Button(store.ui("好", "OK"), role: .cancel) {}
        } message: {
            Text(store.ui("请重试，或选择其他保存位置。", "Try again or choose another save location."))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.ui("导出 PDF", "Export PDF"))
                .weiBeiText(18, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            if let source {
                Text(source.title)
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
    }

    private var canSave: Bool {
        rendered?.options == options && renderError == nil
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(store.ui("取消", "Cancel")) { dismiss() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("note-pdf-cancel")
            Button(store.ui("导出…", "Export…")) { showsFileExporter = true }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .accessibilityIdentifier("note-pdf-save")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var previewColumn: some View {
        VStack(spacing: 0) {
            ZStack {
                if let rendered {
                    NotePDFPreview(document: rendered.document)
                }
                if let renderError {
                    VStack(spacing: 10) {
                        Text(renderError)
                            .weiBeiText(13)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("note-pdf-render-error")
                        Button(store.ui("重试", "Try Again")) { retry += 1 }
                            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(12)
                } else if rendered == nil {
                    ProgressView(store.ui("正在排版…", "Preparing PDF…"))
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            previewStatus.frame(height: 28)
        }
        .background(WeiBeiTheme.paperInset.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var previewStatus: some View {
        if let rendered, renderError == nil {
            if canSave {
                let count = rendered.document.pageCount
                Text(store.ui("\(count) 页", count == 1 ? "1 page" : "\(count) pages"))
                    .weiBeiText(12)
                    .monospacedDigit()
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .accessibilityIdentifier("note-pdf-page-count")
            } else {
                ProgressView(store.ui("正在更新预览…", "Updating Preview…"))
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(store.ui("正在更新预览", "Updating Preview"))
            }
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(options == defaultOptions
                     ? store.ui("沿用笔记样式", "From Note")
                     : store.ui("版式已调整", "Custom Layout"))
                    .weiBeiText(13, weight: .medium)
                Spacer(minLength: 0)
                Button {
                    showsLayoutOptions.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text(store.ui("调整版式", "Customize"))
                        Image(systemName: showsLayoutOptions ? "chevron.up" : "chevron.down")
                            .weiBeiText(9, weight: .semibold)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(
                    fontSize: 12, height: 28, neutralHoverWhenInactive: true
                ))
                .accessibilityValue(showsLayoutOptions ? store.ui("已展开", "Expanded") : store.ui("已收起", "Collapsed"))
                .accessibilityIdentifier("note-pdf-adjust-layout")
            }

            if showsLayoutOptions {
                layoutOptions
            } else {
                Text(pageSummary)
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .accessibilityIdentifier("note-pdf-layout-summary")
            }
        }
    }

    private var pageSummary: String {
        let direction = orientationLabel(options.landscape)
        let numbers = options.folio == .hidden ? store.ui("无页码", "No Page Numbers") : store.ui("含页码", "Page Numbers")
        return "\(options.paper.rawValue) \(direction) · \(numbers)"
    }

    private var layoutOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            segments(store.ui("导出设置", "Export Settings"), selection: $section, choices: Section.allCases) {
                switch $0 {
                case .style: store.ui("样式", "Style")
                case .page: store.ui("页面", "Page")
                }
            }

            ScrollView {
                switch section {
                case .style: styleOptions
                case .page: pageOptions
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var styleOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 5) {
                let theme = defaultOptions.theme
                let themes = (theme.isGlass ? [theme] : []) + [.paper, .xuan, .inkstone, .stele]
                menuRow(store.ui("主题", "Theme"), selection: $options.theme, choices: themes) {
                    $0.label(language: store.interfaceLanguage)
                }
                choiceRow(store.ui("字体", "Font"), selection: $options.font, choices: NotePDFOptions.Font.allCases) { font in
                    switch font {
                    case .note: store.ui("沿用", "Note")
                    case .sans: store.ui("苹方", "Sans")
                    case .serif: store.ui("宋体", "Songti")
                    }
                }
            }
            VStack(spacing: 12) {
                sliderRow(store.ui("字号", "Size"), value: $options.size, in: 7...32, step: 0.5, unit: " pt")
                    .accessibilityIdentifier("note-pdf-size")
                sliderRow(store.ui("行距", "Line Spacing"), value: $options.lineSpacing, in: 1...3, step: 0.05)
                sliderRow(store.ui("段距", "Paragraph Spacing"), value: $options.paragraphSpacing, in: 0...2, step: 0.05)
            }
        }
    }

    private var pageOptions: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(spacing: 5) {
                menuRow(store.ui("纸张", "Paper"), selection: $options.paper, choices: NotePDFOptions.Paper.allCases, label: \.rawValue)
                choiceRow(store.ui("方向", "Orientation"), selection: $options.landscape, choices: [false, true], label: orientationLabel)
                choiceRow(store.ui("页边距", "Margins"), selection: $options.margin, choices: [14, 20, 27]) { margin in
                    switch margin {
                    case 14: store.ui("窄", "Narrow")
                    case 27: store.ui("宽", "Wide")
                    default: store.ui("标准", "Standard")
                    }
                }
                choiceRow(store.ui("页码", "Page Numbers"), selection: $options.folio, choices: NotePDFOptions.Folio.allCases) { folio in
                    switch folio {
                    case .right: store.ui("右下", "Right")
                    case .center: store.ui("居中", "Center")
                    case .hidden: store.ui("隐藏", "Off")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(store.ui("首页装饰", "First Page"))
                    .weiBeiText(12, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .accessibilityAddTraits(.isHeader)
                toggleRow(store.ui("魏碑标志", "WeiBei Mark"), isOn: $options.logo)
                    .accessibilityIdentifier("note-pdf-logo")
                toggleRow(store.ui("兰亭题图", "Orchid Pavilion Artwork"), isOn: $options.illustration)
            }
        }
    }

    private func orientationLabel(_ landscape: Bool) -> String {
        landscape ? store.ui("横向", "Landscape") : store.ui("纵向", "Portrait")
    }

    private func choiceRow<Selection: Hashable>(
        _ title: String, selection: Binding<Selection>, choices: [Selection], label: @escaping (Selection) -> String
    ) -> some View {
        settingRow(title) {
            segments(title, selection: selection, choices: choices, height: 26, label: label)
                .frame(width: 146)
        }
    }

    private func segments<Selection: Hashable>(
        _ title: String, selection: Binding<Selection>, choices: [Selection],
        height: CGFloat = 28, label: @escaping (Selection) -> String
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.self) { choice in
                let isSelected = selection.wrappedValue == choice
                Button {
                    selection.wrappedValue = choice
                } label: {
                    Text(label(choice))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(
                    active: isSelected, fontSize: 12, height: height,
                    horizontalPadding: 4, neutralHoverWhenInactive: true, idleOpacity: 0,
                    cornerRadius: height / 2
                ))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                    guard let index = choices.firstIndex(of: selection.wrappedValue) else { return .ignored }
                    let next = index + (press.key == .leftArrow ? -1 : 1)
                    if choices.indices.contains(next) {
                        selection.wrappedValue = choices[next]
                    }
                    return .handled
                }
            }
        }
        .padding(2)
        .background { WeiBeiToolbarGroupBackground() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private func menuRow<Selection: Hashable>(
        _ title: String, selection: Binding<Selection>, choices: [Selection], label: @escaping (Selection) -> String
    ) -> some View {
        let current = label(selection.wrappedValue)
        return settingRow(title) {
            WeiBeiCompactMenu(title: current) {
                Picker(title, selection: selection) {
                    ForEach(choices, id: \.self) { choice in
                        Text(label(choice)).tag(choice)
                    }
                }
                .pickerStyle(.inline)
            }
            .accessibilityLabel(title)
            .accessibilityValue(current)
        }
    }

    private func sliderRow(
        _ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String = ""
    ) -> some View {
        let display = value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) + unit
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).weiBeiText(13)
                Spacer(minLength: 8)
                Text(display)
                    .weiBeiText(12)
                    .monospacedDigit()
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .accessibilityHidden(true)
            NotePDFSlider(value: value, range: range, step: step, label: title, display: display)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        settingRow(title) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(WeiBeiTheme.accent)
        }
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(title).weiBeiText(13)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: WeiBeiMetric.inputHeight)
    }

    private func updatePreview(for current: NotePDFOptions) async {
        renderError = nil
        do {
            let note: NotePDFSource
            if let source {
                note = source
                try await Task.sleep(for: .milliseconds(160))
            } else {
                note = try await store.notePDFSource(itemID: request.itemID)
                try Task.checkCancellation()
                source = note
            }
            let data = try await NotePDFRenderer().render(note, options: current, language: store.interfaceLanguage)
            try Task.checkCancellation()
            guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw NotePDFRenderer.Failure.page }
            rendered = Rendered(options: current, file: ExportFile(data: data), document: document)
        } catch {
            guard !Task.isCancelled else { return }
            renderError = source == nil
                ? store.ui("读取笔记失败。请确认笔记文件可用。", "Could not read the note. Check that its file is available.")
                : store.ui("无法生成 PDF 预览。", "Could not prepare the PDF preview.")
        }
    }


}

private struct NotePDFSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    let display: String

    @FocusState private var focused: Bool
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let travel = max(1, geometry.size.width - thumbSize)
            let offset = travel * (value - range.lowerBound) / span

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WeiBeiTheme.ink.opacity(0.14))
                    .frame(height: 4)
                    .padding(.horizontal, thumbSize / 2)
                Capsule()
                    .fill(WeiBeiTheme.secondaryInk.opacity(0.72))
                    .frame(width: offset, height: 4)
                    .padding(.leading, thumbSize / 2)
                Circle()
                    .fill(.background)
                    .overlay { Circle().fill(WeiBeiTheme.paperRaised) }
                    .overlay { Circle().strokeBorder(WeiBeiTheme.ink.opacity(0.22), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: offset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                focused = true
                let progress = (drag.location.x - thumbSize / 2) / travel
                setValue(range.lowerBound + progress * span)
            })
        }
        .frame(height: 24)
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            setValue(value + (press.key == .rightArrow ? step : -step))
            return .handled
        }
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) { Text(label) }
                .accessibilityValue(Text(display))
        }
    }

    private func setValue(_ target: Double) {
        let snapped = range.lowerBound + ((target - range.lowerBound) / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }
}

private struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if targetEnvironment(macCatalyst)
private typealias NotePDFPreviewRepresentable = UIViewRepresentable
#else
private typealias NotePDFPreviewRepresentable = NSViewRepresentable
#endif

private struct NotePDFPreview: NotePDFPreviewRepresentable {
    let document: PDFDocument

#if targetEnvironment(macCatalyst)
    func makeUIView(context: Context) -> NotePDFPageView { makePreview() }
    func updateUIView(_ view: NotePDFPageView, context: Context) { updatePreview(view) }
#else
    func makeNSView(context: Context) -> NotePDFPageView { makePreview() }
    func updateNSView(_ view: NotePDFPageView, context: Context) { updatePreview(view) }
#endif

    private func makePreview() -> NotePDFPageView {
        let view = NotePDFPageView()
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        return view
    }

    private func updatePreview(_ view: NotePDFPageView) {
        guard view.document !== document else { return }
        let index = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        view.document = document
        view.fitPage(reset: true)
        if index > 0, let page = document.page(at: min(index, document.pageCount - 1)) {
            view.go(to: page)
        }
    }
}

private final class NotePDFPageView: PDFView {
    private var lastFit: CGFloat?

#if targetEnvironment(macCatalyst)
    override func layoutSubviews() {
        super.layoutSubviews()
        fitPage()
    }
#else
    override func layout() {
        super.layout()
        fitPage()
    }
#endif

    func fitPage(reset: Bool = false) {
        guard let page = document?.page(at: 0) else { return }
        let size = page.bounds(for: .cropBox).size
        let gutter = min(10, min(bounds.width, bounds.height) / 10)
        let fit = min((bounds.width - 2 * gutter) / size.width, (bounds.height - 2 * gutter) / size.height)
        guard fit.isFinite, fit > 0, reset || fit != lastFit else { return }
        lastFit = fit
        if fit < minScaleFactor { minScaleFactor = fit }
        if fit > maxScaleFactor { maxScaleFactor = fit }
        scaleFactor = fit
    }
}
