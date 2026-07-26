import AppKit
import PDFKit
import SwiftUI
import WebKit
import WeiBeiCore

struct MarkdownDocumentReaderView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var markdown: String
    var markdownBaseURL: URL?
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    var selectionAskMarks: String = "[]"
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onSelectionAskMark: (String) -> Void = { _ in }
    var onSelectionChange: (String, CGPoint?) -> Void
    @State private var command: NoteEditorCommand?

    var body: some View {
        RichMarkdownEditorView(
            markdown: .constant(markdown),
            command: $command,
            isEditable: false,
            markdownBaseURL: markdownBaseURL,
            searchQuery: searchQuery,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage,
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onSelectionChange,
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut,
            selectionAskMarks: selectionAskMarks,
            onSelectionAskMark: onSelectionAskMark
        )
    }
}

struct MarkdownReadFailureView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var fileName: String

    var body: some View {
        ReaderStateMessage(
            title: store.ui("无法读取 Markdown", "Could not read Markdown"),
            detail: fileName,
            systemImage: "exclamationmark.triangle"
        )
    }
}

struct EmptyReaderView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        ReaderStateMessage(
            title: store.ui("选择资料", "Choose Material"),
            detail: store.ui("从课程目录打开 HTML、PDF 或 Markdown。", "Open HTML, PDF, or Markdown from the course index."),
            systemImage: "doc.text.magnifyingglass"
        )
    }
}

struct NotebookSelectedReaderView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        ReaderStateMessage(
            title: store.ui("当前是笔记", "This is a note"),
            detail: store.ui("阅读区只显示资料，右侧继续写作当前笔记。", "The reader shows materials only. Continue writing this note on the side."),
            systemImage: "square.and.pencil"
        )
    }
}

struct ReaderStateMessage: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.62))
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(WeiBeiTheme.ink)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
    }
}

struct PlainTextReaderView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var text: String
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var onSelectionChange: (String, CGPoint?) -> Void

    var body: some View {
        SelectablePlainTextReader(
            text: text,
            searchQuery: searchQuery,
            appearanceMode: appearanceMode,
            underlineSnippets: store.selectionAskThreads.map(\.selectionText),
            onSelectionChange: onSelectionChange
        )
            .padding(32)
    }
}

struct SelectablePlainTextReader: NSViewRepresentable {
    var text: String
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var underlineSnippets: [String]
    var onSelectionChange: (String, CGPoint?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        WeiBeiQuietScrollers.configure(scrollView, hasHorizontalScroller: false)
        scrollView.drawsBackground = false

        let textView = ReaderSelectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.backgroundColor = .clear
        applyTheme(to: textView)
        applyAttributedText(to: textView)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyTheme(to: textView)
        applyAttributedText(to: textView)
        context.coordinator.applySearch(searchQuery, in: textView)
    }

    private func applyAttributedText(to textView: NSTextView) {
        let ink = WeiBeiNativePalette.ink(for: appearanceMode)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: ink,
            ]
        )
        let full = NSRange(location: 0, length: attributed.length)
        let cinnabar = NSColor(calibratedRed: 0.56, green: 0.16, blue: 0.12, alpha: 1)
        for snippet in underlineSnippets {
            let needle = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard needle.count >= 4 else { continue }
            var search = full
            while search.length > 0 {
                let found = (attributed.string as NSString).range(of: needle, options: [], range: search)
                guard found.location != NSNotFound else { break }
                attributed.addAttributes(
                    [
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: cinnabar,
                    ],
                    range: found
                )
                let next = found.location + found.length
                search = NSRange(location: next, length: max(0, attributed.length - next))
            }
        }
        if textView.attributedString().string != attributed.string
            || textView.attributedString().length != attributed.length {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            // Refresh underline attributes without resetting caret when possible.
            textView.textStorage?.setAttributedString(attributed)
        }
    }

    private func applyTheme(to textView: NSTextView) {
        textView.textColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.insertionPointColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.selectedTextAttributes = [
            .backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode),
            .foregroundColor: WeiBeiNativePalette.selectedText(for: appearanceMode)
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (String, CGPoint?) -> Void
        private var lastSearchQuery = ""
        private var suppressSelectionReport = false

        init(onSelectionChange: @escaping (String, CGPoint?) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !suppressSelectionReport else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let stringRange = Range(range, in: textView.string) else {
                onSelectionChange("", nil)
                return
            }
            onSelectionChange(String(textView.string[stringRange]), Self.anchor(for: range, in: textView))
        }

        private static func anchor(for range: NSRange, in textView: NSTextView) -> CGPoint? {
            guard let window = textView.window else { return nil }
            let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard !rect.isEmpty else { return nil }
            let screenPoint = CGPoint(x: rect.midX, y: rect.minY)
            return SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)
        }

        func applySearch(_ query: String, in textView: NSTextView) {
            let query = ReaderSearch.cleaned(query)
            guard query != lastSearchQuery else { return }
            lastSearchQuery = query
            guard !query.isEmpty else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                return
            }
            onSelectionChange("", nil)
            guard let range = ReaderSearch.firstMatch(in: textView.string, query: query) else { return }
            suppressSelectionReport = true
            textView.setSelectedRange(range)
            suppressSelectionReport = false
            textView.scrollRangeToVisible(range)
        }
    }
}

