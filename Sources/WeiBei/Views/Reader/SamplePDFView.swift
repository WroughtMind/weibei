import AppKit
import PDFKit
import SwiftUI
import WebKit
import WeiBeiCore

struct SamplePDFView: View {
    var appearanceMode: WeiBeiAppearanceMode
    var language: WeiBeiInterfaceLanguage
    var onSelectionChange: (String, CGPoint?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SamplePDFSelectablePageView(
                    appearanceMode: appearanceMode,
                    language: language,
                    onSelectionChange: onSelectionChange
                )
                .frame(maxWidth: 620, minHeight: 820, alignment: .topLeading)
                .background(WeiBeiTheme.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(WeiBeiTheme.hairline, lineWidth: 1)
                }
                .shadow(color: WeiBeiTheme.ink.opacity(0.075), radius: 16, y: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
        }
        .background(WeiBeiTheme.paper)
    }
}

struct SamplePDFSelectablePageView: NSViewRepresentable {
    var appearanceMode: WeiBeiAppearanceMode
    var language: WeiBeiInterfaceLanguage
    var onSelectionChange: (String, CGPoint?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = ReaderSelectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 42, height: 44)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.delegate = context.coordinator
        applyContent(to: textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        applyContent(to: textView, coordinator: context.coordinator)
    }

    private func applyContent(to textView: NSTextView, coordinator: Coordinator) {
        coordinator.appearanceMode = appearanceMode
        if coordinator.appliedAppearanceMode != appearanceMode || coordinator.appliedLanguage != language {
            textView.textStorage?.setAttributedString(Self.attributedText(for: appearanceMode, language: language))
            coordinator.appliedAppearanceMode = appearanceMode
            coordinator.appliedLanguage = language
        }
        textView.selectedTextAttributes = [
            .foregroundColor: WeiBeiNativePalette.selectedText(for: appearanceMode),
            .backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode)
        ]
    }

    private static func attributedText(for appearanceMode: WeiBeiAppearanceMode, language: WeiBeiInterfaceLanguage) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let ink = WeiBeiNativePalette.ink(for: appearanceMode)
        let secondary = ink.withAlphaComponent(0.62)
        let tertiary = ink.withAlphaComponent(0.45)
        let titleFont = NSFont.systemFont(ofSize: 34, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 17, weight: .regular)
        let smallFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let footerFont = NSFont.systemFont(ofSize: 12, weight: .medium)

        func paragraph(lineSpacing: CGFloat = 0, paragraphSpacing: CGFloat = 0) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            style.paragraphSpacing = paragraphSpacing
            return style
        }

        func append(_ string: String, font: NSFont, color: NSColor, style: NSParagraphStyle) {
            output.append(NSAttributedString(string: string, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style
            ]))
        }

        append(language.text("Mishkin 教材样例                                      PDF 阅读样例\n", "Mishkin Textbook Sample                         PDF Reading Sample\n"), font: smallFont, color: tertiary, style: paragraph(paragraphSpacing: 20))
        append(language.text("金融体系的功能\n", "Functions of the Financial System\n"), font: titleFont, color: ink, style: paragraph(paragraphSpacing: 24))
        append(language.text("金融市场和金融中介能够把储蓄者的资金转移给有投资机会的人。它们降低交易成本，缓解信息不对称，并帮助社会更有效地配置资源。\n", "Financial markets and intermediaries move funds from savers to people with investment opportunities. They reduce transaction costs, ease information problems, and help allocate resources more effectively.\n"), font: bodyFont, color: ink, style: paragraph(lineSpacing: 8, paragraphSpacing: 22))
        append(language.text("这一页是内置 PDF 阅读样例。导入真实 PDF 后，中央区域会切换为 PDFKit 阅读器。现在这个样例页也可以像真实 PDF 一样选中文字并唤起选区 Agent。\n", "This page is the built-in PDF reading sample. After you import a real PDF, the center area switches to the PDFKit reader. This sample page also supports text selection and the selection Agent.\n"), font: bodyFont, color: secondary, style: paragraph(lineSpacing: 8, paragraphSpacing: 240))
        append(language.text("页 1                                                        魏碑", "Page 1                                                     WeiBei"), font: footerFont, color: tertiary, style: paragraph())
        return output
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (String, CGPoint?) -> Void
        var appearanceMode: WeiBeiAppearanceMode = .paper
        var appliedAppearanceMode: WeiBeiAppearanceMode?
        var appliedLanguage: WeiBeiInterfaceLanguage?

        init(onSelectionChange: @escaping (String, CGPoint?) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ notification: Notification) {
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
    }
}

class ReaderSelectableTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

struct EscapeKeyBridge: NSViewRepresentable {
    var isEnabled = true
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onEscape: () -> Void
        private var monitor: Any?

        init(isEnabled: Bool, onEscape: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onEscape = onEscape
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53,
                      self?.isEnabled == true,
                      NSApp.modalWindow == nil,
                      event.window?.attachedSheet == nil else { return event }
                self?.onEscape()
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
