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
    private let noteTheme: WeiBeiAppearanceMode
    @State private var options: NotePDFOptions
    @State private var source: NotePDFSource?
    @State private var rendered: Rendered?
    @State private var showsOptions = true
    @State private var showsFileExporter = false
    @State private var renderError: String?
    @State private var saveError = false
    @State private var retry = 0

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
        noteTheme = theme
        _options = State(initialValue: NotePDFOptions(theme: theme, textScale: textScale))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pageLayout
            Divider()
            footer
        }
        .frame(minWidth: 440, idealWidth: 790, minHeight: 440, idealHeight: 650)
        .background(.background)
        .presentationBackground(.background)
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .modifier(WeiBeiFittedSheetPresentation())
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
        HStack(spacing: 14) {
            Text(store.ui("导出 PDF", "Export PDF"))
                .font(.title3.weight(.semibold))
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            if let source {
                Text(source.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                showsOptions.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .tint(.secondary)
            .accessibilityLabel(store.ui("排版设置", "Layout Settings"))
            .accessibilityValue(showsOptions ? store.ui("已显示", "Shown") : store.ui("已收起", "Hidden"))
            .help(showsOptions ? store.ui("收起排版设置", "Hide Layout Settings")
                               : store.ui("显示排版设置", "Show Layout Settings"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var pageLayout: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 600
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsOptions {
                    Divider()
                    inspector.frame(width: wide ? 262 : nil, height: wide ? nil : geometry.size.height * 0.44)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let rendered, rendered.options == options, renderError == nil {
                let count = rendered.document.pageCount
                Text(store.ui("\(count) 页", count == 1 ? "1 page" : "\(count) pages"))
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("note-pdf-page-count")
            }
            Spacer()
            Button(store.ui("取消", "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("note-pdf-cancel")
            Button(store.ui("导出…", "Export…")) { showsFileExporter = true }
                .buttonStyle(.borderedProminent)
                .tint(WeiBeiTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(rendered?.options != options || renderError != nil)
                .accessibilityIdentifier("note-pdf-save")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var preview: some View {
        ZStack {
            Color(weiBeiNativeColor: NotePDFPreview.canvasColor)
            if let rendered {
                NotePDFPreview(document: rendered.document)
            }
            if let renderError {
                VStack(spacing: 8) {
                    Text(renderError).accessibilityIdentifier("note-pdf-render-error")
                    Button(store.ui("重试", "Try Again")) { retry += 1 }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if rendered?.options != options {
                ProgressView(store.ui("正在排版…", "Preparing PDF…"))
                    .controlSize(.small)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 4) {
                    menuRow(store.ui("主题", "Theme"), selection: $options.theme,
                            current: options.theme.label(language: store.interfaceLanguage)) {
                        ForEach((noteTheme.isGlass ? [noteTheme] : []) + [.paper, .xuan, .inkstone, .stele], id: \.self) { theme in
                            Text(theme.label(language: store.interfaceLanguage)).tag(theme)
                        }
                    }
                    menuRow(store.ui("字体", "Font"), selection: $options.font, current: fontName(options.font)) {
                        ForEach(NotePDFOptions.Font.allCases, id: \.self) { font in
                            Text(fontName(font)).tag(font)
                        }
                    }
                    numberRow(store.ui("字号", "Size"), value: $options.size, in: 7...32, step: 0.5, unit: " pt")
                    numberRow(store.ui("行距", "Line Spacing"), value: $options.lineSpacing, in: 1...3, step: 0.1)
                    numberRow(store.ui("段距", "Paragraph Spacing"), value: $options.paragraphSpacing, in: 0...2, step: 0.1)
                }
                Divider()
                pageOptions
                DisclosureGroup(store.ui("首页装饰", "First Page")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(store.ui("魏碑标志", "WeiBei Mark"), isOn: $options.logo)
                        Toggle(store.ui("兰亭题图", "Orchid Pavilion Artwork"), isOn: $options.illustration)
                    }
                    .padding(.top, 8)
                }
            }
            .font(.subheadline)
            .controlSize(.small)
            .pickerStyle(.menu)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var pageOptions: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                Picker(store.ui("纸张", "Paper"), selection: $options.paper) {
                    ForEach(NotePDFOptions.Paper.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker(store.ui("方向", "Orientation"), selection: $options.landscape) {
                    Text(store.ui("纵向", "Portrait")).tag(false)
                    Text(store.ui("横向", "Landscape")).tag(true)
                }
                Picker(store.ui("页边距", "Margins"), selection: $options.margin) {
                    Text(store.ui("窄", "Narrow")).tag(14)
                    Text(store.ui("标准", "Standard")).tag(20)
                    Text(store.ui("宽", "Wide")).tag(27)
                }
                Picker(store.ui("页码", "Page Numbers"), selection: $options.folio) {
                    Text(store.ui("右下角", "Bottom Right")).tag(NotePDFOptions.Folio.right)
                    Text(store.ui("居中", "Centered")).tag(NotePDFOptions.Folio.center)
                    Text(store.ui("隐藏", "Hidden")).tag(NotePDFOptions.Folio.hidden)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text(store.ui("页面", "Page"))
                Spacer(minLength: 8)
                Text(options.paper.rawValue)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fontName(_ font: NotePDFOptions.Font) -> String {
        switch font {
        case .note: store.ui("沿用笔记", "From Note")
        case .sans: store.ui("苹方", "System Sans")
        case .serif: store.ui("宋体", "Songti")
        }
    }

    private func menuRow<Selection: Hashable, Choices: View>(
        _ title: String, selection: Binding<Selection>, current: String, @ViewBuilder choices: () -> Choices
    ) -> some View {
        settingRow(title) {
            Menu {
                Picker(title, selection: selection, content: choices)
                    .pickerStyle(.inline)
            } label: {
                Text(current).lineLimit(1)
            }
            .frame(maxWidth: 126, alignment: .trailing)
            .accessibilityLabel(title)
            .accessibilityValue(current)
        }
    }

    private func numberRow(
        _ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String = ""
    ) -> some View {
        let display = value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) + unit
        return settingRow(title) {
            Stepper(value: value, in: range, step: step) {
                Text(display)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(title)
            .accessibilityValue(display)
        }
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            control()
        }
        .frame(minHeight: 28)
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
        view.backgroundColor = Self.canvasColor
        return view
    }

    static var canvasColor: WeiBeiPlatformColor {
#if targetEnvironment(macCatalyst)
        .systemGray5
#else
        .underPageBackgroundColor
#endif
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
        let fit = min((bounds.width - 28) / size.width, (bounds.height - 28) / size.height)
        guard fit.isFinite, fit > 0, reset || fit != lastFit else { return }
        lastFit = fit
        if fit < minScaleFactor { minScaleFactor = fit }
        if fit > maxScaleFactor { maxScaleFactor = fit }
        scaleFactor = fit
    }
}
