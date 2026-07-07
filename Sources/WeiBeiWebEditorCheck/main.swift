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

HTML 换行第一行<br />第二行，选区应读作两行。

脚注引用[^1]，行内脚注^[行内脚注内容]。

[^1]: 这是脚注内容。

> [!note]- 可编辑标题
>
> 温和洞察应该放在不打断阅读的位置。

> [!quote] 选区摘录
>
> 利率是资金使用价格的表达。
>
> 来源：Mishkin 教材样例，第 12 页

> [!quote] 旧摘录
>
> [!quote] 旧逻辑泄露
> 这行旧摘录正文不能带着控制符显示。

> > [!quote] 嵌套摘录
> >
> > 嵌套摘录里的控制符不应该露出来。

> [!attention]+ 自定义标题
>
> 自定义 Callout 不应该漏出源标记。

> 引用里的代码块：
>
> ```txt
> \\#quoted-code \\$5 \\[!note] <br />
> ```

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

行内代码 `<br />` 不应被当成换行。
双反引号 ``内部 ` <br />`` 也要保留源码。
行内代码 `[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />` 不应触发魏碑语法装饰。
行内代码 `\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]` 保存时不能被清理反斜杠。
转义反引号 \\` 后面的 \\[\\[转义双链\\]\\] \\#escaped-tag \\$5 仍应按正文保存。

```html
<span>保留<br />源码</span>
```

```txt
\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]
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
                    self.validateReadOnlyInkstoneDecorations {
                        self.validateRenderedImageSource {
                            self.validateWikiLinkActivation()
                        }
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
          commentsWeak: (() => {
            const comments = Array.from(document.querySelectorAll('.weibei-comment'));
            if (comments.length < 1) return false;
            return comments.every((comment) => {
              const style = getComputedStyle(comment);
              return parseFloat(style.opacity || '1') <= 0.72
                || style.color === 'rgba(0, 0, 0, 0)'
                || parseFloat(style.fontSize || '16') <= 12;
            });
          })(),
          tags: document.querySelectorAll('.weibei-tag').length,
          blockIds: document.querySelectorAll('.weibei-block-id').length,
          embeds: document.querySelectorAll('.weibei-embed-preview').length,
          hardBreaks: document.querySelectorAll('.ProseMirror br').length,
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
          calloutHeadingVisible: (() => {
            const heading = document.querySelector('blockquote.weibei-callout .weibei-callout-heading');
            if (!heading) return false;
            const style = getComputedStyle(heading);
            return style.opacity !== '0' && style.fontSize !== '0px' && heading.textContent.includes('可编辑标题');
          })(),
          calloutMarkerHidden: (() => {
            const marker = document.querySelector('blockquote.weibei-callout .weibei-callout-heading .weibei-callout-marker');
            if (!marker) return false;
            const style = getComputedStyle(marker);
            return style.color === 'rgba(0, 0, 0, 0)' && style.fontSize === '0px';
          })(),
          quoteCalloutTitle: document.querySelector('blockquote.weibei-callout-quote')?.getAttribute('data-callout-title') || '',
          quoteCalloutText: document.querySelector('blockquote.weibei-callout-quote')?.textContent || '',
          quoteCalloutCount: document.querySelectorAll('blockquote.weibei-callout-quote').length,
          quoteCalloutMarkerVisible: (() => {
            const marker = document.querySelector('blockquote.weibei-callout-quote .weibei-callout-marker');
            if (!marker) return true;
            const style = getComputedStyle(marker);
            return style.visibility !== 'hidden'
              || Array.from(marker.getClientRects()).some((rect) => rect.width > 0.5 || rect.height > 0.5);
          })(),
          quoteCalloutMarkerHidden: (() => {
            const marker = document.querySelector('blockquote.weibei-callout-quote .weibei-callout-marker');
            if (!marker) return false;
            const style = getComputedStyle(marker);
            return style.display === 'inline-block'
              && style.color === 'rgba(0, 0, 0, 0)'
              && style.visibility === 'hidden'
              && style.fontSize === '0px'
              && style.width === '0px'
              && marker.getBoundingClientRect().width === 0;
          })(),
          visibleBareCalloutMarkers: (() => {
            const root = document.querySelector('.ProseMirror');
            if (!root) return -1;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              if (!/\\[![A-Za-z]/.test(node.nodeValue || '')) continue;
              const parent = node.parentElement;
              if (parent?.closest('code, pre')) continue;
              if (parent?.closest('.weibei-callout-marker')) continue;
              if (!parent?.closest('blockquote.weibei-callout')) continue;
              const style = getComputedStyle(parent);
              const visible = style.display !== 'none'
                && style.visibility !== 'hidden'
                && style.opacity !== '0'
                && style.color !== 'rgba(0, 0, 0, 0)'
                && parseFloat(style.fontSize || '0') > 0;
              if (visible) count += 1;
            }
            return count;
          })(),
          visibleRawCalloutMarkers: (() => {
            const root = document.querySelector('.ProseMirror');
            if (!root) return -1;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              if (!/\\[![A-Za-z]/.test(node.nodeValue || '')) continue;
              const parent = node.parentElement;
              if (parent?.closest('code, pre')) continue;
              if (parent?.closest('.weibei-callout-marker')) continue;
              const style = getComputedStyle(parent);
              const visible = style.display !== 'none'
                && style.visibility !== 'hidden'
                && style.opacity !== '0'
                && style.color !== 'rgba(0, 0, 0, 0)'
                && parseFloat(style.fontSize || '0') > 0;
              if (visible) count += 1;
            }
            return count;
          })(),
          cleanedCalloutSelection: (() => {
            if (!window.WeiBeiEditor.selectFirstTextForCheck('[!quote] 选区摘录')) return '__missing__';
            return window.WeiBeiEditor.selectedTextForCheck();
          })(),
          customCalloutType: document.querySelector('blockquote.weibei-callout-custom')?.getAttribute('data-callout') || '',
          customCalloutFold: document.querySelector('blockquote.weibei-callout-custom')?.getAttribute('data-callout-fold') || '',
          customCalloutTitle: document.querySelector('blockquote.weibei-callout-custom')?.getAttribute('data-callout-title') || '',
          customCalloutText: document.querySelector('blockquote.weibei-callout-custom')?.textContent || '',
          customCalloutMarkerVisible: (() => {
            const marker = document.querySelector('blockquote.weibei-callout-custom .weibei-callout-marker');
            if (!marker) return true;
            const style = getComputedStyle(marker);
            return style.visibility !== 'hidden'
              || Array.from(marker.getClientRects()).some((rect) => rect.width > 0.5 || rect.height > 0.5);
          })(),
          customCalloutMarkerHidden: (() => {
            const marker = document.querySelector('blockquote.weibei-callout-custom .weibei-callout-marker');
            if (!marker) return false;
            const style = getComputedStyle(marker);
            return style.display === 'inline-block'
              && style.color === 'rgba(0, 0, 0, 0)'
              && style.visibility === 'hidden'
              && style.fontSize === '0px'
              && style.width === '0px'
              && marker.getBoundingClientRect().width === 0;
          })(),
          inlineCodeSyntaxDecorations: document.querySelectorAll('code .weibei-wikilink, code .weibei-highlight, code .weibei-comment, code .weibei-tag, code .weibei-html-break-source').length,
          inlineCodeSyntaxText: Array.from(document.querySelectorAll('code'))
            .map((node) => node.textContent || '')
            .find((text) => text.includes('[[不是链接]]')) || ''
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
            if result["commentsWeak"] as? Bool != true {
                self.fail("Obsidian comments should be weakly visible, not compete with body text")
                return
            }
            if (result["hardBreaks"] as? Int ?? 0) < 1 {
                self.fail("HTML break syntax was not normalized into a real editor line break")
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
            if result["calloutHeadingVisible"] as? Bool != true {
                self.fail("callout title should stay visible and editable in writing mode")
                return
            }
            if result["calloutMarkerHidden"] as? Bool != true {
                self.fail("callout source marker should not remain visible in writing mode")
                return
            }
            if result["quoteCalloutTitle"] as? String != "选区摘录" {
                self.fail("quote callout title should be kept without exposing the source marker")
                return
            }
            if !(result["quoteCalloutText"] as? String ?? "").contains("利率是资金使用价格的表达。") {
                self.fail("quote callout body text disappeared")
                return
            }
            if (result["quoteCalloutCount"] as? Int ?? 0) < 2 {
                self.fail("nested quote callout was not recognized")
                return
            }
            if result["quoteCalloutMarkerHidden"] as? Bool != true {
                self.fail("quote callout marker should collapse in writing and preview surfaces")
                return
            }
            if result["quoteCalloutMarkerVisible"] as? Bool == true {
                self.fail("quote callout marker should not have visible boxes")
                return
            }
            if (result["visibleBareCalloutMarkers"] as? Int ?? -1) != 0 {
                self.fail("callout source markers should not leak as visible bare text")
                return
            }
            if (result["visibleRawCalloutMarkers"] as? Int ?? -1) != 0 {
                self.fail("nested callout source markers should not leak as visible text")
                return
            }
            let cleanedCalloutSelection = result["cleanedCalloutSelection"] as? String ?? ""
            if cleanedCalloutSelection == "__missing__"
                || cleanedCalloutSelection.contains("[!quote]")
                || !cleanedCalloutSelection.contains("选区摘录") {
                self.fail("callout control marker leaked into selected text: \(cleanedCalloutSelection)")
                return
            }
            if result["customCalloutType"] as? String != "attention" {
                self.fail("unknown Obsidian callout type was not recognized")
                return
            }
            if result["customCalloutFold"] as? String != "+" {
                self.fail("unknown Obsidian callout fold marker was not preserved")
                return
            }
            if result["customCalloutTitle"] as? String != "自定义标题" {
                self.fail("unknown Obsidian callout title was not preserved")
                return
            }
            if !(result["customCalloutText"] as? String ?? "").contains("自定义 Callout 不应该漏出源标记。") {
                self.fail("unknown Obsidian callout body disappeared")
                return
            }
            if result["customCalloutMarkerHidden"] as? Bool != true {
                self.fail("unknown Obsidian callout marker should collapse")
                return
            }
            if result["customCalloutMarkerVisible"] as? Bool == true {
                self.fail("unknown Obsidian callout marker should not have visible boxes")
                return
            }
            if (result["inlineCodeSyntaxDecorations"] as? Int ?? -1) != 0
                || !(result["inlineCodeSyntaxText"] as? String ?? "").contains("[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />") {
                self.fail("inline code should not receive WeiBei Markdown syntax decorations")
                return
            }
            completion()
        }
    }

    private func validateReadOnlyInkstoneDecorations(completion: @escaping () -> Void) {
        let prepare = """
        window.WeiBeiEditor.setTheme('inkstone');
        window.WeiBeiEditor.setEditable(false);
        """
        webView.evaluateJavaScript(prepare) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("read-only inkstone setup threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.inspectReadOnlyInkstone(completion: completion)
            }
        }
    }

    private func inspectReadOnlyInkstone(completion: @escaping () -> Void) {
        let script = """
        (() => {
          const root = document.querySelector('.ProseMirror');
          const quote = document.querySelector('blockquote.weibei-callout-quote');
          const marker = quote?.querySelector('.weibei-callout-marker');
          const heading = quote?.querySelector('.weibei-callout-heading');
          const textNodeWalker = document.createTreeWalker(root || document.body, NodeFilter.SHOW_TEXT);
          let visibleBareMarkers = 0;
          let node;
          while ((node = textNodeWalker.nextNode())) {
            if (!/\\[![A-Za-z]/.test(node.nodeValue || '')) continue;
            const parent = node.parentElement;
            if (parent?.closest('.weibei-callout-marker')) continue;
            if (!parent?.closest('blockquote.weibei-callout')) continue;
            const style = getComputedStyle(parent);
            const visible = style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.opacity !== '0'
              && style.color !== 'rgba(0, 0, 0, 0)'
              && parseFloat(style.fontSize || '0') > 0;
            if (visible) visibleBareMarkers += 1;
          }
          const markerStyle = marker ? getComputedStyle(marker) : null;
          const headingStyle = heading ? getComputedStyle(heading) : null;
          const sampleText = quote?.querySelector('p:last-child') || quote || root || document.body;
          const sampleColor = getComputedStyle(sampleText).color;
          return {
            editable: document.body.dataset.editable || '',
            theme: document.documentElement.dataset.weibeiTheme || '',
            markerHidden: markerStyle
              ? markerStyle.color === 'rgba(0, 0, 0, 0)' && markerStyle.fontSize === '0px'
              : false,
            headingHidden: headingStyle ? headingStyle.display === 'none' : false,
            visibleBareMarkers,
            sampleColor
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("read-only inkstone check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("read-only inkstone check returned \(String(describing: value))")
                return
            }
            if result["editable"] as? String != "false" || result["theme"] as? String != "inkstone" {
                self.fail("read-only inkstone state was not applied: \(result)")
                return
            }
            if result["markerHidden"] as? Bool != true || result["headingHidden"] as? Bool != true {
                self.fail("read-only callout heading or marker leaked: \(result)")
                return
            }
            if (result["visibleBareMarkers"] as? Int ?? -1) != 0 {
                self.fail("read-only callout source marker leaked as visible text")
                return
            }
            if (result["sampleColor"] as? String ?? "").contains("255, 255, 255") {
                self.fail("read-only inkstone text fell back to pure white")
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
            self.validateTypedHtmlBreak()
        }
    }

    private func validateTypedHtmlBreak() {
        let script = """
        window.WeiBeiEditor.insertMarkdown("\\n\\n{{WEIBEI_CURSOR}}");
        if (!window.WeiBeiEditor.typeTextForCheck('手动换行第一行<br />第二行')) {
          throw new Error('typeTextForCheck unavailable');
        }
        window.WeiBeiEditor.getMarkdown();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("typed HTML break check threw \(error.localizedDescription)")
                return
            }
            guard let markdown = value as? String else {
                self.fail("typed HTML break check did not return markdown")
                return
            }
            guard let range = markdown.range(of: "手动换行第一行") else {
                self.fail("typed HTML break text did not serialize")
                return
            }
            let suffix = String(markdown[range.upperBound...])
            if !suffix.hasPrefix("  \n第二行")
                && !suffix.hasPrefix("  \n> 第二行")
                && !suffix.hasPrefix("\\\n第二行")
                && !suffix.hasPrefix("\\\n> 第二行")
                && !suffix.hasPrefix("\n第二行")
                && !suffix.hasPrefix("\n> 第二行") {
                self.fail("typed HTML break did not become a Markdown hard break: \(markdown)")
                return
            }
            if markdown.contains("手动换行第一行<br") {
                self.fail("typed HTML break leaked raw HTML syntax into saved markdown")
                return
            }
            self.validateTypedMarkdownShortcuts()
        }
    }

    private func validateTypedMarkdownShortcuts() {
        let script = """
        (() => {
        const cases = [
          ['## 现场标题', 'h2', '## 现场标题', '现场标题'],
          ['- 现场条目', 'li', '现场条目', '现场条目'],
          ['- [ ] 现场待办', 'li[data-item-type="task"], li', '现场待办', '现场待办'],
          ['**现场加粗**', 'strong', '**现场加粗**', '现场加粗'],
          ['~~现场删除~~', 's, del', '~~现场删除~~', '现场删除'],
          ['==现场高亮==', '.weibei-highlight', '==现场高亮==', '现场高亮'],
          ['[[现场概念|显示名]]', '.weibei-wikilink[data-wikilink-target="现场概念"]', '[[现场概念|显示名]]', '显示名']
        ];
        for (const [typed, selector, expectedMarkdown, visibleText] of cases) {
          window.WeiBeiEditor.setMarkdown('# 输入语法验收\\n');
          window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
          if (!window.WeiBeiEditor.typeTextForCheck(typed)) {
            return { ok: false, reason: 'typeTextForCheck unavailable for ' + typed };
          }
          const markdown = window.WeiBeiEditor.getMarkdown();
          const node = document.querySelector(selector);
          if (!markdown.includes(expectedMarkdown) || !node || !node.textContent.includes(visibleText)) {
            return { ok: false, reason: 'typed Markdown shortcut did not render in place: ' + typed, markdown, html: document.querySelector('.ProseMirror')?.innerHTML || '' };
          }
        }
        return { ok: true, markdown: window.WeiBeiEditor.getMarkdown() };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("typed Markdown shortcut check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("typed Markdown shortcut check did not return result")
                return
            }
            if result["ok"] as? Bool != true {
                self.fail("typed Markdown shortcut check failed: \(result)")
                return
            }
            guard let markdown = result["markdown"] as? String, markdown.contains("[[现场概念|显示名]]") else {
                self.fail("typed Markdown shortcut check did not finish: \(result)")
                return
            }
            self.validateBlockEnterExit()
        }
    }

    private func validateBlockEnterExit() {
        let script = """
        (() => {
        try {
        const cases = [
          ['\\n\\n- 项目{{WEIBEI_CURSOR}}', '退出无序列表', ['- 项目', '* 项目', '+ 项目'], '\\n\\n退出无序列表'],
          ['\\n\\n- \u{200B}{{WEIBEI_CURSOR}}', '退出视觉空白无序列表', [], '\\n\\n退出视觉空白无序列表'],
          ['\\n\\n1. 项目{{WEIBEI_CURSOR}}', '退出有序列表', ['1. 项目'], '\\n\\n退出有序列表'],
          ['\\n\\n- [ ] 待办{{WEIBEI_CURSOR}}', '退出任务列表', ['- [ ] 待办', '* [ ] 待办', '+ [ ] 待办'], '\\n\\n退出任务列表'],
          ['\\n\\n> 引用{{WEIBEI_CURSOR}}', '退出引用', ['> 引用'], '\\n\\n退出引用'],
          ['\\n\\n> [!note] 标题\\n>\\n> 内容{{WEIBEI_CURSOR}}', '退出 Callout', ['> 内容'], '\\n\\n退出 Callout']
        ];
        for (const [markdown, text, expectedBeforeOptions, expectedAfter] of cases) {
          window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
          window.WeiBeiEditor.insertMarkdown(markdown);
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for first Enter');
          }
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for second Enter');
          }
          if (!window.WeiBeiEditor.typeTextForCheck(text)) {
            throw new Error('typeTextForCheck unavailable after list exit');
          }
          const current = window.WeiBeiEditor.getMarkdown();
          if ((expectedBeforeOptions.length > 0 && !expectedBeforeOptions.some((expectedBefore) => current.includes(expectedBefore))) || !current.includes(expectedAfter)) {
            throw new Error('empty block Enter did not create a normal paragraph after the block: ' + text + '\\n' + current);
          }
          if (current.includes('\\n- ' + text)
              || current.includes('\\n* ' + text)
              || current.includes('\\n+ ' + text)
              || current.includes('\\n1. ' + text)
              || current.includes('\\n2. ' + text)
              || current.includes('\\n- [ ] ' + text)
              || current.includes('\\n> ' + text)) {
            throw new Error('empty block Enter kept following text in the block: ' + text + '\\n' + current);
          }
        }
        window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
        window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
        if (!window.WeiBeiEditor.typeTextForCheck('- 手写项目')) {
          throw new Error('typeTextForCheck unavailable for typed bullet');
        }
        if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
          throw new Error('pressKeyForCheck unavailable for typed bullet first Enter');
        }
        if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
          throw new Error('pressKeyForCheck unavailable for typed bullet second Enter');
        }
        if (!window.WeiBeiEditor.typeTextForCheck('手写退出列表')) {
          throw new Error('typeTextForCheck unavailable after typed bullet exit');
        }
        const typedMarkdown = window.WeiBeiEditor.getMarkdown();
        if (!['- 手写项目', '* 手写项目', '+ 手写项目'].some((marker) => typedMarkdown.includes(marker))
            || !typedMarkdown.includes('\\n\\n手写退出列表')
            || typedMarkdown.includes('\\n- 手写退出列表')
            || typedMarkdown.includes('\\n* 手写退出列表')
            || typedMarkdown.includes('\\n+ 手写退出列表')) {
          throw new Error('typed bullet Enter did not exit to a normal paragraph\\n' + typedMarkdown);
        }
        if (Array.from(document.querySelectorAll('.ProseMirror li')).some((item) => item.textContent.includes('手写退出列表'))) {
          throw new Error('typed bullet exit kept following text inside a list item\\n' + document.querySelector('.ProseMirror')?.innerHTML);
        }
        window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
        window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
        if (!window.WeiBeiEditor.typeTextForCheck('- ')) {
          throw new Error('typeTextForCheck unavailable for empty bullet shortcut');
        }
        if (!document.querySelector('.ProseMirror li')) {
          throw new Error('empty bullet shortcut did not create a real list item');
        }
        if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
          throw new Error('pressKeyForCheck unavailable for empty bullet exit');
        }
        if (!window.WeiBeiEditor.typeTextForCheck('空项目退出列表')) {
          throw new Error('typeTextForCheck unavailable after empty bullet exit');
        }
        const emptyShortcutMarkdown = window.WeiBeiEditor.getMarkdown();
        if (!emptyShortcutMarkdown.includes('\\n\\n空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n- 空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n* 空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n+ 空项目退出列表')
            || Array.from(document.querySelectorAll('.ProseMirror li')).some((item) => item.textContent.includes('空项目退出列表'))) {
          throw new Error('empty bullet shortcut Enter did not exit to a normal paragraph\\n' + emptyShortcutMarkdown + '\\n' + document.querySelector('.ProseMirror')?.innerHTML);
        }
        return { ok: true, markdown: window.WeiBeiEditor.getMarkdown() };
        } catch (error) {
          return { ok: false, reason: String(error?.message || error), stack: String(error?.stack || '') };
        }
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("list Enter exit check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("list Enter exit check did not return result")
                return
            }
            if let ok = result["ok"] as? Bool, ok == false {
                self.fail("list Enter exit check failed: \(result)")
                return
            }
            guard let markdown = result["markdown"] as? String else {
                self.fail("list Enter exit check did not return markdown: \(result)")
                return
            }
            if !markdown.contains("空项目退出列表") {
                self.fail("block Enter exit check did not finish all isolated cases: \(markdown)")
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
            ("quoted code block", "> \\#quoted-code \\$5 \\[!note] <br />"),
            ("code fence", "```swift"),
            ("inline html break code", "`<br />`"),
            ("double backtick html break code", "``内部 ` <br />``"),
            ("inline code markdown syntax", "`[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />`"),
            ("inline code escaped syntax", "`\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]`"),
            ("escaped backtick prose syntax", "转义反引号 \\` 后面的 [[转义双链]] #escaped-tag $5"),
            ("code block html break", "<span>保留<br />源码</span>"),
            ("code block escaped syntax", "\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]"),
            ("image size", "![魏碑测试图|100x80](assets/weibei.svg)")
        ]
        for (name, fragment) in checks {
            if !markdown.contains(fragment) {
                fail("missing \(name): \(fragment)\n--- markdown ---\n\(markdown)")
                return
            }
        }
        guard let htmlBreakRange = markdown.range(of: "HTML 换行第一行") else {
            fail("missing html break prefix\n--- markdown ---\n\(markdown)")
            return
        }
        let htmlBreakSuffix = String(markdown[htmlBreakRange.upperBound...])
        if !htmlBreakSuffix.hasPrefix("  \n第二行") && !htmlBreakSuffix.hasPrefix("\\\n第二行") && !htmlBreakSuffix.hasPrefix("\n第二行") {
            fail("HTML break was swallowed instead of becoming a Markdown hard break\n--- markdown ---\n\(markdown)")
            return
        }
        if markdown.contains("HTML 换行第一行第二行") || markdown.contains("HTML 换行第一行<br") {
            fail("HTML break serialized as joined text or raw HTML\n--- markdown ---\n\(markdown)")
            return
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
