import AppKit
import Foundation
import WebKit

let sampleMarkdown = """
---
course: 货币金融学
tags:
  - finance/rate
---

# 魏碑 Markdown Web 验收

| 能力 | 状态 |
| --- | --- |
| 表格 | 可编辑 |
| Agent | 可追问 |
| 双链 | [[货币理论\\|理论别名]] |
| 转义 | A \\| B |

- [ ] todo
- [x] done
- 普通列表
  - 嵌套列表

~~删除线~~、==重点高亮==、[[货币理论|理论别名]]、[[货币理论#利率]]、[[货币理论#^rate-block]]、[[#本页标题]]、[[^^利率搜索]]。
%%这是一条只在写作时弱显示的注释%%
%%
这是一段块注释
跨行也应该弱显示
%%
#finance #nested/tag
重点段落 ^rate-block

脚注引用[^1]，行内脚注^[行内脚注内容]。

[^1]: 这是脚注内容。

> [!note]- 可编辑标题
>
> 温和洞察应该放在不打断阅读的位置。

行内公式 $E = mc^2$、$\\alpha_1 + \\beta^2$、$A^*$，普通金额 $5 不应该被误伤。

Milkdown 公式插件应直接渲染 $text^*$，不能额外生成源码灰块。

$$
\\frac{a_1}{b^2} + \\sum_{i=1}^{n} x_i
$$

$$
\\begin{bmatrix}
a & b \\\\
c & d
\\end{bmatrix}
$$

```swift
let note = "魏碑"
print(note)
```

```mermaid
graph TD
  A[阅读] --> B[整理]
```

![魏碑测试图|100x80](assets/weibei.svg)
![[assets/weibei.svg|100]]
![[货币理论#利率]]
"""

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("web-editor-check failed: \(message)\n", stderr)
        exit(1)
    }
}

func json(_ value: String) -> String {
    let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
    return String(data: data, encoding: .utf8) ?? "\"\""
}

final class EditorHarness: NSObject, WKScriptMessageHandler {
    private let webView: WKWebView
    private var isDone = false
    private var failure: String?
    private var activatedWikiTitle: String?
    private var attachmentRequests = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let source = """
        window.initialMarkdown = \(json(sampleMarkdown));
        window.weiBeiDocumentID = "web-editor-check";
        window.weiBeiMarkdownEditable = true;
        window.weiBeiEditorCheckMode = true;
        window.weiBeiLocalImageScheme = "weibeiimage";
        window.weiBeiMarkdownBaseURL = \(json(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/WeiBei/Resources/Editor/").absoluteString));
        """
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 960, height: 720), configuration: configuration)
        super.init()
        for name in ["editorReady", "markdownChanged", "selectionChanged", "askAgentWithSelection", "wikiLinkActivated", "imageAttachmentRequested"] {
            controller.add(self, name: name)
        }
    }

    func run() {
        let indexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())

        let timeout = Date().addingTimeInterval(15)
        while !isDone && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if let failure {
            fputs("web-editor-check failed: \(failure)\n", stderr)
            exit(1)
        }
        expect(isDone, "editor did not become ready")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "editorReady":
            guard (message.body as? [String: Any])?["documentID"] as? String == "web-editor-check" else {
                fail("editorReady did not include the current document identity")
                return
            }
            validateInitialMarkdown()
        case "wikiLinkActivated":
            activatedWikiTitle = (message.body as? [String: Any])?["title"] as? String
        case "imageAttachmentRequested":
            attachmentRequests += 1
        default:
            break
        }
    }

    private func validateInitialMarkdown() {
        webView.evaluateJavaScript("window.WeiBeiEditor.getMarkdown()") { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("getMarkdown threw \(error.localizedDescription)")
                return
            }
            guard let markdown = value as? String else {
                self.fail("getMarkdown did not return text")
                return
            }
            self.validate(markdown)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.validateObsidianDecorations {
                    self.validateRenderedImageSource {
                        self.validateWikiLinkActivation()
                    }
                }
            }
        }
    }

    private func validateObsidianDecorations(completion: @escaping () -> Void) {
        let script = """
        (() => ({
          wikilinkText: document.querySelector('.weibei-wikilink')?.textContent || '',
          inlineFootnoteText: document.querySelector('.weibei-inline-footnote')?.textContent || '',
          inlineFootnotes: document.querySelectorAll('.weibei-inline-footnote').length,
          comments: document.querySelectorAll('.weibei-comment').length,
          tags: document.querySelectorAll('.weibei-tag').length,
          blockIds: document.querySelectorAll('.weibei-block-id').length,
          embeds: document.querySelectorAll('.weibei-embed-preview').length,
          noteEmbedLinks: document.querySelectorAll('.weibei-embed-note[role="link"][tabindex="0"][data-wikilink-title]').length,
          mermaid: document.querySelectorAll('.weibei-mermaid-render').length,
          mermaidSvg: document.querySelectorAll('.weibei-mermaid-render svg').length,
          mermaidPlaceholder: document.body.textContent.includes('渲染器未安装完成') ? 1 : 0,
          mermaidText: document.querySelector('.weibei-mermaid-render')?.textContent || '',
          mermaidSourceOpacity: getComputedStyle(document.querySelector('.weibei-mermaid-block') || document.body).opacity,
          mathInline: document.querySelectorAll('span[data-type="math_inline"], .math-inline, .katex').length,
          mathInlineBackground: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body).backgroundColor,
          mathInlineContainerColor: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body).color,
          mathInlineContainerFontSize: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body).fontSize,
          mathInlineKatexColor: getComputedStyle(document.querySelector('span[data-type="math_inline"] > .katex, .math-inline > .katex') || document.body).color,
          mathInlineKatexFontSize: getComputedStyle(document.querySelector('span[data-type="math_inline"] > .katex, .math-inline > .katex') || document.body).fontSize,
          mathInlineDirectTextNodes: (() => {
            const node = document.querySelector('span[data-type="math_inline"], .math-inline');
            if (!node) return -1;
            return Array.from(node.childNodes).filter((child) => child.nodeType === Node.TEXT_NODE && child.nodeValue.trim()).length;
          })(),
          mathInlineSourceChildrenVisible: (() => {
            const node = document.querySelector('span[data-type="math_inline"], .math-inline');
            if (!node) return false;
            return Array.from(node.children).some((child) => {
              if (child.classList.contains('katex')) return false;
              const style = getComputedStyle(child);
              return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
            });
          })(),
          mathInlinePseudoBefore: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body, '::before').content,
          mathInlinePseudoAfter: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body, '::after').content,
          mathInlineMathMLHidden: (() => {
            const mathML = document.querySelector('span[data-type="math_inline"] .katex-mathml, .math-inline .katex-mathml');
            if (!mathML) return false;
            const style = getComputedStyle(mathML);
            return style.position === 'absolute' && style.overflow === 'hidden' && (style.clipPath !== 'none' || style.clip !== 'auto');
          })(),
          mathBlock: document.querySelectorAll('div[data-type="math_block"], .math-block, .katex-display').length,
          rawMathArtifacts: document.querySelectorAll('[class*="weibei-raw-math"]').length,
          rawMathPlainText: (() => {
            const root = document.querySelector('.ProseMirror');
            if (!root) return 0;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              const parent = node.parentElement;
              if (!node.nodeValue.includes('$text^*$')) continue;
              if (parent?.closest('[data-type="math_inline"], .math-inline')) continue;
              count += 1;
            }
            return count;
          })(),
          foldedCallout: document.querySelector('blockquote.weibei-callout')?.getAttribute('data-callout-fold') || '',
          calloutTitle: document.querySelector('blockquote.weibei-callout')?.getAttribute('data-callout-title') || '',
          calloutSourceHidden: (() => {
            const source = document.querySelector('blockquote.weibei-callout .weibei-callout-heading-source');
            if (!source) return false;
            const style = getComputedStyle(source);
            return style.opacity === '0' && (style.height === '0px' || style.fontSize === '0px');
          })()
        }))();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("Obsidian decoration check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("Obsidian decoration check returned \(String(describing: value))")
                return
            }
            if result["wikilinkText"] as? String != "理论别名" {
                self.fail("alias wikilink did not display alias")
                return
            }
            if result["inlineFootnoteText"] as? String != "行内脚注内容"
                || (result["inlineFootnotes"] as? Int ?? 0) < 1 {
                self.fail("inline footnote was not decorated")
                return
            }
            for key in ["comments", "tags", "blockIds", "embeds", "mermaid"] {
                if (result[key] as? Int ?? 0) < 1 {
                    self.fail("missing Obsidian decoration: \(key)")
                    return
                }
            }
            if (result["comments"] as? Int ?? 0) < 2 {
                self.fail("block comment was not decorated")
                return
            }
            if (result["noteEmbedLinks"] as? Int ?? 0) < 1 {
                self.fail("note embed was not keyboard/click activatable")
                return
            }
            if (result["mermaidSvg"] as? Int ?? 0) < 1 || (result["mermaidPlaceholder"] as? Int ?? 0) > 0 {
                self.fail("Mermaid block did not render to SVG: \(result["mermaidText"] as? String ?? "")")
                return
            }
            if let opacityText = result["mermaidSourceOpacity"] as? String,
               (Double(opacityText) ?? 0) < 0.7 {
                self.fail("Mermaid source block is too faint to edit: \(opacityText)")
                return
            }
            if (result["mathInline"] as? Int ?? 0) < 1 {
                self.fail("inline math did not render as a math node")
                return
            }
            if result["mathInlineBackground"] as? String != "rgba(0, 0, 0, 0)" {
                self.fail("inline math should not render as a filled source block")
                return
            }
            if result["mathInlineContainerColor"] as? String != "rgba(0, 0, 0, 0)" {
                self.fail("inline math container should hide raw source text")
                return
            }
            if result["mathInlineContainerFontSize"] as? String != "0px" {
                self.fail("inline math source container should collapse raw source font size")
                return
            }
            if result["mathInlineKatexColor"] as? String == "rgba(0, 0, 0, 0)" {
                self.fail("inline math rendered KaTeX should remain visible")
                return
            }
            if result["mathInlineKatexFontSize"] as? String == "0px" {
                self.fail("inline math rendered KaTeX should keep readable font size")
                return
            }
            if (result["mathInlineDirectTextNodes"] as? Int ?? 1) > 0 {
                self.fail("inline math should not render raw source text beside KaTeX")
                return
            }
            if result["mathInlineSourceChildrenVisible"] as? Bool == true {
                self.fail("inline math source child should not occupy layout beside KaTeX")
                return
            }
            if result["mathInlinePseudoBefore"] as? String != "none"
                || result["mathInlinePseudoAfter"] as? String != "none" {
                self.fail("inline math should not render source pseudo-elements")
                return
            }
            if result["mathInlineMathMLHidden"] as? Bool != true {
                self.fail("inline math MathML should be visually hidden")
                return
            }
            if (result["mathBlock"] as? Int ?? 0) < 1 {
                self.fail("block math did not render as a math node")
                return
            }
            if (result["rawMathArtifacts"] as? Int ?? 0) > 0 {
                self.fail("raw inline math fallback artifacts should not be rendered")
                return
            }
            if (result["rawMathPlainText"] as? Int ?? 0) > 0 {
                self.fail("inline math source remained visible as plain text")
                return
            }
            if result["foldedCallout"] as? String != "-" {
                self.fail("callout folded marker was not recognized")
                return
            }
            if result["calloutTitle"] as? String != "可编辑标题" {
                self.fail("callout title swallowed body text")
                return
            }
            if result["calloutSourceHidden"] as? Bool != true {
                self.fail("callout source marker should not remain visible in writing mode")
                return
            }
            completion()
        }
    }

    private func validateRenderedImageSource(completion: @escaping () -> Void) {
        let script = """
        Array.from(document.querySelectorAll('.ProseMirror img')).map((image) => image.getAttribute('src') || image.src || '').join('\\n')
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("image source check threw \(error.localizedDescription)")
                return
            }
            guard let rawSrc = value as? String else {
                self.fail("local markdown image did not use controlled scheme: \(String(describing: value))")
                return
            }
            let src = rawSrc.trimmingCharacters(in: .whitespacesAndNewlines)
            guard src.hasPrefix("weibeiimage://image") else {
                self.fail("local markdown image did not use controlled scheme: \(src)")
                return
            }
            completion()
        }
    }

    private func validateWikiLinkActivation() {
        let script = """
        const link = document.querySelector('.weibei-wikilink');
        if (!link) throw new Error('missing wikilink decoration');
        link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("wikilink click threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论" else {
                    self.fail("wikilink did not send canonical title to native bridge: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateHeadingWikiLinkActivation()
            }
        }
    }

    private func validateHeadingWikiLinkActivation() {
        activatedWikiTitle = nil
        let script = """
        (() => {
        const links = Array.from(document.querySelectorAll('.weibei-wikilink'));
        const link = links.find((node) => node.getAttribute('data-wikilink-target') === '货币理论#利率');
        if (!link) {
          return { ok: false, targets: links.map((node) => node.getAttribute('data-wikilink-target')).join('|') };
        }
        link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        return { ok: true, targets: links.map((node) => node.getAttribute('data-wikilink-target')).join('|') };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("heading wikilink click threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any], result["ok"] as? Bool == true else {
                self.fail("missing heading wikilink decoration: \((value as? [String: Any])?["targets"] as? String ?? String(describing: value))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论#利率" else {
                    self.fail("heading wikilink did not keep target fragment: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateEmbedWikiLinkActivation()
            }
        }
    }

    private func validateEmbedWikiLinkActivation() {
        activatedWikiTitle = nil
        let script = """
        (() => {
          const embed = document.querySelector('.weibei-embed-note[data-wikilink-target="货币理论#利率"]');
          if (!embed) return false;
          embed.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("note embed click threw \(error.localizedDescription)")
                return
            }
            guard value as? Bool == true else {
                self.fail("missing clickable note embed")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论#利率" else {
                    self.fail("note embed did not keep target fragment: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateReadOnlyImagePaste()
            }
        }
    }

    private func validateReadOnlyImagePaste() {
        let script = """
        window.WeiBeiEditor.setEditable(false);
        const editor = document.querySelector('.ProseMirror');
        const data = new DataTransfer();
        data.items.add(new File([new Uint8Array([1, 2, 3])], 'readonly.png', { type: 'image/png' }));
        const event = new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data });
        editor.dispatchEvent(event);
        window.WeiBeiEditor.setEditable(true);
        event.defaultPrevented;
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("readonly paste check threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.attachmentRequests != 0 {
                    self.fail("readonly image paste should not request attachment save")
                    return
                }
                self.validateSelectionReplacement()
            }
        }
    }

    private func validateSelectionReplacement() {
        replaceFirst("可追问", with: "已改写") { [weak self] in
            guard let self else { return }
            self.replaceFirst("温和洞察", with: "Agent 洞察") { [weak self] in
                guard let self else { return }
                self.webView.evaluateJavaScript("window.WeiBeiEditor.getMarkdown()") { [weak self] value, error in
                    guard let self else { return }
                    if let error {
                        self.fail("getMarkdown after replacement threw \(error.localizedDescription)")
                        return
                    }
                    guard let markdown = value as? String else {
                        self.fail("replacement markdown did not return text")
                        return
                    }
                    let tableReplaced = markdown.contains("| Agent | 已改写 |")
                        || (markdown.contains("| Agent") && markdown.contains("已改写"))
                    if !tableReplaced {
                        self.fail("table selection replacement was not serialized back to markdown")
                        return
                    }
                    if !markdown.contains("> [!note]- 可编辑标题") || !markdown.contains("Agent 洞察") {
                        self.fail("callout selection replacement was not serialized back to markdown")
                        return
                    }
                    self.validateAgentPatch()
                }
            }
        }
    }

    private func replaceFirst(_ needle: String, with replacement: String, completion: @escaping () -> Void) {
        let script = """
        if (!window.WeiBeiEditor.selectFirstTextForCheck(\(json(needle)))) {
          throw new Error("missing selection target: \(needle)");
        }
        window.WeiBeiEditor.replaceSelection(\(json(replacement)));
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.fail("replaceSelection threw \(error.localizedDescription)")
                return
            }
            completion()
        }
    }

    private func validateAgentPatch() {
        let patch = "\n## Agent 整理建议\n补充一条可写回的整理建议。"
        webView.evaluateJavaScript("window.WeiBeiEditor.applyAgentPatch(\(json(patch)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("applyAgentPatch threw \(error.localizedDescription)")
                return
            }
            self.webView.evaluateJavaScript("window.WeiBeiEditor.getMarkdown()") { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after patch threw \(error.localizedDescription)")
                    return
                }
                guard let markdown = value as? String else {
                    self.fail("patched markdown did not return text")
                    return
                }
                if !markdown.contains("Agent 整理建议") || !markdown.contains("补充一条可写回的整理建议") {
                    self.fail("Agent patch was not serialized back to markdown")
                    return
                }
                self.validateCommandInsertion()
            }
        }
    }

    private func validateCommandInsertion() {
        let snippet = "\n$$\n\\frac{x}{y}\n$$\n"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("insertMarkdown command threw \(error.localizedDescription)")
                return
            }
            self.webView.evaluateJavaScript("window.WeiBeiEditor.getMarkdown()") { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after insert command threw \(error.localizedDescription)")
                    return
                }
                guard let markdown = value as? String else {
                    self.fail("inserted markdown did not return text")
                    return
                }
                if !markdown.contains("\\frac{x}{y}") || !markdown.contains("$$") {
                    self.fail("insertMarkdown command did not serialize block math correctly")
                    return
                }
                self.validateCursorMarkerInsertion()
            }
        }
    }

    private func validateCursorMarkerInsertion() {
        let snippet = "\n> [!note] 标题\n>\n> {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}}\n"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("insertMarkdown cursor marker command threw \(error.localizedDescription)")
                return
            }
            let script = """
            (() => ({
              markdown: window.WeiBeiEditor.getMarkdown(),
              selectedText: window.WeiBeiEditor.selectedTextForCheck()
            }))()
            """
            self.webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after cursor marker insert threw \(error.localizedDescription)")
                    return
                }
                guard let result = value as? [String: Any],
                      let markdown = result["markdown"] as? String,
                      let selectedText = result["selectedText"] as? String else {
                    self.fail("cursor marker inserted markdown did not return text")
                    return
                }
                if markdown.contains("{{WEIBEI_CURSOR}}")
                    || markdown.contains("{{WEIBEI_SELECT_START}}")
                    || markdown.contains("{{WEIBEI_SELECT_END}}") {
                    self.fail("insertMarkdown cursor marker leaked into saved markdown")
                    return
                }
                if !markdown.contains("> [!note] 标题\n>\n> 内容") {
                    self.fail("insertMarkdown cursor marker command did not keep the callout: \(markdown)")
                    return
                }
                if selectedText.trimmingCharacters(in: .whitespacesAndNewlines) != "内容" {
                    self.fail("insertMarkdown cursor marker did not select the editable placeholder")
                    return
                }
                self.validateInlineFormulaCursorMarkerInsertion()
            }
        }
    }

    private func validateInlineFormulaCursorMarkerInsertion() {
        let snippet = "${{WEIBEI_SELECT_START}}x_i = \\frac{a}{b}{{WEIBEI_SELECT_END}}$"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("inline formula marker command threw \(error.localizedDescription)")
                return
            }
            let script = """
            (() => ({
              markdown: window.WeiBeiEditor.getMarkdown(),
              selectedText: window.WeiBeiEditor.selectedTextForCheck()
            }))()
            """
            self.webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after inline formula marker insert threw \(error.localizedDescription)")
                    return
                }
                guard let result = value as? [String: Any],
                      let markdown = result["markdown"] as? String,
                      let selectedText = result["selectedText"] as? String else {
                    self.fail("inline formula marker inserted markdown did not return text")
                    return
                }
                if markdown.contains("{{WEIBEI_SELECT_START}}")
                    || markdown.contains("{{WEIBEI_SELECT_END}}") {
                    self.fail("inline formula marker leaked into saved markdown")
                    return
                }
                if !markdown.contains("\\frac{a}{b}") || !markdown.contains("$") {
                    self.fail("inline formula marker command did not keep formula markdown: \(markdown)")
                    return
                }
                if selectedText.trimmingCharacters(in: .whitespacesAndNewlines) != "x_i = \\frac{a}{b}" {
                    self.fail("inline formula marker did not select the editable formula")
                    return
                }
                self.validateTypedInlineFormula()
            }
        }
    }

    private func validateTypedInlineFormula() {
        let script = """
        window.WeiBeiEditor.insertMarkdown("\\n\\n{{WEIBEI_CURSOR}}");
        if (!window.WeiBeiEditor.typeTextForCheck('$A^*$')) {
          throw new Error('typeTextForCheck unavailable');
        }
        (() => ({
          markdown: window.WeiBeiEditor.getMarkdown(),
          mathNodes: document.querySelectorAll('span[data-type="math_inline"], .math-inline').length,
          typedMathNode: !!document.querySelector('span[data-type="math_inline"][data-value="A^*"], .math-inline[data-value="A^*"]'),
          typedMathColor: getComputedStyle(document.querySelector('span[data-type="math_inline"][data-value="A^*"], .math-inline[data-value="A^*"]') || document.body).color,
          typedMathFontSize: getComputedStyle(document.querySelector('span[data-type="math_inline"][data-value="A^*"], .math-inline[data-value="A^*"]') || document.body).fontSize,
          typedKatexFontSize: getComputedStyle(document.querySelector('span[data-type="math_inline"][data-value="A^*"] > .katex, .math-inline[data-value="A^*"] > .katex') || document.body).fontSize,
          rawFormulaText: (() => {
            const root = document.querySelector('.ProseMirror');
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              const parent = node.parentElement;
              if (!node.nodeValue.includes('$A^*$')) continue;
              if (parent?.closest('[data-type="math_inline"], .math-inline')) continue;
              count += 1;
            }
            return count;
          })(),
          mathBackground: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body).backgroundColor
        }))();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("typed inline formula check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any],
                  let markdown = result["markdown"] as? String else {
                self.fail("typed inline formula check did not return result")
                return
            }
            if !markdown.contains("$A^*$") {
                self.fail("typed inline formula did not serialize as Markdown math: \(markdown)")
                return
            }
            if (result["mathNodes"] as? Int ?? 0) < 1 {
                self.fail("typed inline formula did not become a math node")
                return
            }
            if result["typedMathNode"] as? Bool != true {
                self.fail("typed inline formula did not create a math node for A^*")
                return
            }
            if result["typedMathColor"] as? String != "rgba(0, 0, 0, 0)"
                || result["typedMathFontSize"] as? String != "0px" {
                self.fail("typed inline formula source container should be invisible and collapsed")
                return
            }
            if result["typedKatexFontSize"] as? String == "0px" {
                self.fail("typed inline formula rendered KaTeX should stay readable")
                return
            }
            if (result["rawFormulaText"] as? Int ?? 0) > 0 {
                self.fail("typed inline formula left a raw source text block beside KaTeX")
                return
            }
            if result["mathBackground"] as? String != "rgba(0, 0, 0, 0)" {
                self.fail("typed inline formula should not look like a filled source chip")
                return
            }
            self.isDone = true
        }
    }

    private func validate(_ markdown: String) {
        let checks = [
            ("table", "| 能力"),
            ("escaped table wikilink", "[[货币理论\\|理论别名]]"),
            ("task unchecked", "[ ] todo"),
            ("task checked", "[x] done"),
            ("strikethrough", "~~删除线~~"),
            ("highlight", "==重点高亮=="),
            ("alias wikilink", "[[货币理论|理论别名]]"),
            ("heading wikilink", "[[货币理论#利率]]"),
            ("block wikilink", "[[货币理论#^rate-block]]"),
            ("block id", "^rate-block"),
            ("embed image", "![[assets/weibei.svg|100]]"),
            ("embed note", "![[货币理论#利率]]"),
            ("footnote", "[^1]: 这是脚注内容。"),
            ("inline footnote", "^[行内脚注内容]"),
            ("callout", "> [!note]- 可编辑标题"),
            ("inline math", "E = mc^2"),
            ("star inline math", "A^*"),
            ("normal dollar", "$5 不应该被误伤"),
            ("plugin-rendered inline math", "$text^*$"),
            ("matrix math", "\\begin{bmatrix}"),
            ("fraction math", "\\frac{a_1}{b^2}"),
            ("mermaid", "```mermaid"),
            ("comment", "%%这是一条只在写作时弱显示的注释%%"),
            ("block comment", "%%\n这是一段块注释\n跨行也应该弱显示\n%%"),
            ("tag", "#nested/tag"),
            ("frontmatter", "course: 货币金融学"),
            ("code fence", "```swift"),
            ("image size", "![魏碑测试图|100x80](assets/weibei.svg)")
        ]
        for (name, fragment) in checks {
            if !markdown.contains(fragment) {
                fail("missing \(name): \(fragment)\n--- markdown ---\n\(markdown)")
                return
            }
        }
    }

    private func fail(_ message: String) {
        failure = message
        isDone = true
    }
}

NSApplication.shared.setActivationPolicy(.prohibited)
EditorHarness().run()
print("WeiBei web editor check passed")
