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
        .frame(minWidth: 440, idealWidth: 900, minHeight: 440, idealHeight: 650)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(Color(weiBeiNativeColor: WeiBeiNativePalette.foregroundWorkspaceSurface(for: store.appearanceMode)))
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.ui("导出 PDF", "Export PDF")).font(.headline)
                if let source {
                    Text(source.title).font(.subheadline).foregroundStyle(WeiBeiTheme.secondaryInk).lineLimit(1)
                }
            }
            Spacer()
            Button {
                showsOptions.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(WeiBeiIconButtonStyle(active: showsOptions, size: 28))
            .accessibilityLabel(store.ui("排版设置", "Layout Settings"))
            .accessibilityValue(showsOptions ? store.ui("已显示", "Shown") : store.ui("已收起", "Hidden"))
            .help(showsOptions ? store.ui("收起排版设置", "Hide Layout Settings")
                               : store.ui("显示排版设置", "Show Layout Settings"))
        }
        .padding(.horizontal, 16)
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
                    inspector.frame(width: wide ? 252 : nil, height: wide ? nil : geometry.size.height * 0.44)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let rendered, rendered.options == options, renderError == nil {
                let count = rendered.document.pageCount
                Text(store.ui("\(count) 页", count == 1 ? "1 page" : "\(count) pages"))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .font(.subheadline)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var preview: some View {
        ZStack {
            WeiBeiTheme.paperInset
            if let rendered {
                NotePDFPreview(document: rendered.document)
            }
            if let renderError {
                VStack(spacing: 8) {
                    Text(renderError)
                    Button(store.ui("重试", "Try Again")) { retry += 1 }
                }
                .padding(16)
                .background(WeiBeiTheme.paperRaised, in: RoundedRectangle(cornerRadius: 8))
            } else if rendered?.options != options {
                ProgressView(store.ui("正在排版…", "Preparing PDF…"))
                    .controlSize(.small)
                    .padding(12)
                    .background(WeiBeiTheme.paperRaised, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text(store.ui("排版", "Layout")).font(.headline)
                Picker(store.ui("主题", "Theme"), selection: $options.theme) {
                    ForEach([WeiBeiAppearanceMode.paper, .xuan, .inkstone, .stele], id: \.self) { theme in
                        Text(theme.label(language: store.interfaceLanguage)).tag(theme)
                    }
                }
                Picker(store.ui("字体", "Font"), selection: $options.font) {
                    Text(store.ui("沿用笔记", "From Note")).tag(NotePDFOptions.Font.note)
                    Text(store.ui("苹方", "System Sans")).tag(NotePDFOptions.Font.sans)
                    Text(store.ui("宋体", "Songti")).tag(NotePDFOptions.Font.serif)
                }
                Stepper(value: $options.size, in: 7...32, step: 0.5) {
                    LabeledContent(store.ui("字号", "Size"), value: options.size.formatted() + " pt")
                }
                Stepper(value: $options.lineSpacing, in: 1...3, step: 0.1) {
                    LabeledContent(store.ui("行距", "Line Spacing"), value: options.lineSpacing.formatted(.number.precision(.fractionLength(1...2))))
                }
                Stepper(value: $options.paragraphSpacing, in: 0...2, step: 0.1) {
                    LabeledContent(store.ui("段距", "Paragraph Spacing"), value: options.paragraphSpacing.formatted(.number.precision(.fractionLength(1...2))))
                }
                Divider()
                DisclosureGroup(store.ui("页面", "Page")) {
                    VStack(alignment: .leading, spacing: 10) {
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
                    }.padding(.top, 8)
                }
                DisclosureGroup(store.ui("首页装饰", "First Page")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(store.ui("魏碑标志", "WeiBei Mark"), isOn: $options.logo)
                        Toggle(store.ui("兰亭题图", "Orchid Pavilion Artwork"), isOn: $options.illustration)
                    }.padding(.top, 8)
                }
            }
            .controlSize(.small)
            .pickerStyle(.menu)
            .padding(16)
        }
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
    func makeUIView(context: Context) -> PDFView { makePreview() }
    func updateUIView(_ view: PDFView, context: Context) { updatePreview(view) }
#else
    func makeNSView(context: Context) -> PDFView { makePreview() }
    func updateNSView(_ view: PDFView, context: Context) { updatePreview(view) }
#endif

    private func makePreview() -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.displaysPageBreaks = true
        view.backgroundColor = WeiBeiNativePalette.paperInset()
        return view
    }

    private func updatePreview(_ view: PDFView) {
        guard view.document !== document else { return }
        let index = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        view.document = document
        if index > 0, let page = document.page(at: min(index, document.pageCount - 1)) {
            view.go(to: page)
        }
    }
}
