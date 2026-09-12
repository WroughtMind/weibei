import AppKit
import WebKit

/// Uses the real editor in an invisible WebKit view, without a shared clipboard or library.
final class NotesTypographyHarness: NSObject, WKScriptMessageHandler {
    private var ready = false
    private var error: String?
    private let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: """
            window.initialMarkdown = '# 书写与阅读\\n\\n中文笔记 Typography 123，让文字有合适的呼吸。\\n\\n## 二级标题\\n\\n### 三级标题\\n\\n#### 四级标题\\n\\n##### 五级标题\\n\\n###### 六级标题\\n\\n- 列表内容\\n  - 嵌套内容\\n\\n> 引用内容\\n\\n| 项目 | 内容 |\\n| --- | --- |\\n| 表格 | 可编辑 |\\n\\n```swift\\nlet note = "中文"\\n```\\n\\n' + '连续书写的测试段落，中英文混排 Markdown 123。\\n\\n'.repeat(20);
            window.weiBeiMarkdownEditable = true;
            window.weiBeiEditorCheckMode = true;
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), configuration: configuration)
        super.init()
        controller.add(self, name: "editorReady")
        controller.add(self, name: "editorFailure")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "editorReady" { ready = true }
        else { error = String(describing: message.body) }
    }

    private func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(30)
        while !condition() && error == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        expect(error == nil && condition(), "notes check timed out or failed: \(error ?? "timeout")")
    }

    @discardableResult private func js(_ source: String) -> Any? {
        var done = false
        var result: Any?
        webView.evaluateJavaScript(source) { value, failure in
            result = value
            if let failure { self.error = String(describing: failure) }
            done = true
        }
        wait { done }
        return result
    }

    private func check(_ expression: String, _ reason: String) {
        expect(js(expression) as? Bool == true, reason)
    }

    private func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.12)) }

    private func capture(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["WEIBEI_NOTES_CAPTURE_DIR"] else { return }
        var done = false
        webView.takeSnapshot(with: nil) { image, failure in
            if let data = image?.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                do { try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")) }
                catch { self.error = error.localizedDescription }
            } else { self.error = failure?.localizedDescription ?? "Snapshot returned no image" }
            done = true
        }
        wait { done }
    }

    func run() {
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/Resources/Editor")
        webView.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
        wait { ready }
        js("window.fontsLoaded = false; document.fonts.ready.then(() => window.fontsLoaded = true); 0")
        wait { js("window.fontsLoaded") as? Bool == true }
        check("document.fonts.check('16px Mplus1p') && document.fonts.check('16px \"Mplus1p Heading\"')", "Onigiri fonts load locally")
        js("window.savedMarkdown = window.WeiBeiEditor.getMarkdown(); window.css = s => getComputedStyle(document.querySelector(s)); 0")
        js("window.WeiBeiEditor.setMarkdown('正文 **粗体中文 Bold**'); 0")
        check("parseFloat(css('.ProseMirror strong').fontWeight) >= 600", "bold notes select a bold weight instead of reusing the light body face")
        capture("notes-bold")
        js("window.WeiBeiEditor.setMarkdown(window.savedMarkdown); 0")
        check("css('.ProseMirror').fontSize === '16px' && css('.ProseMirror p').lineHeight === '28px'", "notes use the measured Onigiri body size and line spacing")
        check("Math.abs(document.querySelector('.ProseMirror').getBoundingClientRect().width - 984) < 1", "wide notes match Onigiri's 1024px page including its two 20px gutters")
        check("Math.abs(document.querySelector('.ProseMirror').getBoundingClientRect().left - (document.getElementById('editor').clientWidth - 984) / 2) < 1", "the writing area is centered")
        capture("notes-wide")
        js("window.beforeSizes = ['p','h1','h2','h3','h4','h5','h6'].map(s => parseFloat(css('.ProseMirror '+s).fontSize)); window.WeiBeiEditor.setTextScale(1.25); 0")
        check("['p','h1','h2','h3','h4','h5','h6'].every((s,i) => Math.abs(parseFloat(css('.ProseMirror '+s).fontSize) / window.beforeSizes[i] - 1.25) < .01)", "all six headings and body text scale together")
        js("window.WeiBeiEditor.setTextScale(1); 0")
        webView.frame.size.width = 420
        settle()
        check("document.getElementById('editor').scrollWidth <= 421 && document.querySelector('.ProseMirror').getBoundingClientRect().width <= 380", "split-pane notes fit without horizontal page overflow")
        check("parseFloat(css('.ProseMirror h1').fontSize) < 48", "narrow panes use Onigiri's responsive heading scale")
        capture("notes-narrow")
        webView.frame.size.width = 1280
        settle()
        // DOM input exercises the real editor and its scroll plugin, without touching the OS clipboard.
        js("window.WeiBeiEditor.setTypewriterMode(true); const e=document.querySelector('.ProseMirror'); e.focus(); const r=document.createRange(); r.selectNodeContents(e.lastElementChild); r.collapse(false); const s=getSelection(); s.removeAllRanges(); s.addRange(r); 0")
        settle()
        js("document.querySelector('.ProseMirror').dispatchEvent(new InputEvent('beforeinput', {bubbles:true,inputType:'insertText',data:'验证'})); document.execCommand('insertText',false,'验证'); 0")
        settle()
        check("(() => {const s=getSelection(); const r=s.getRangeAt(0).cloneRange(); const b=r.getBoundingClientRect(); const e=document.getElementById('editor'); return b.height>0 && Math.abs((b.top+b.bottom)/2-e.getBoundingClientRect().top-e.clientHeight/2)<35;})()", "typing keeps the caret in the middle of the writing viewport")
        capture("notes-typewriter")
        js("document.getElementById('editor').dispatchEvent(new WheelEvent('wheel')); document.getElementById('editor').scrollTop=80; 0")
        settle()
        check("document.getElementById('editor').scrollTop === 80", "manual scrolling is not pulled back to the caret")
        js("document.querySelector('.ProseMirror').dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true})); document.querySelector('.ProseMirror').dispatchEvent(new InputEvent('beforeinput',{bubbles:true,inputType:'insertCompositionText',data:'拼'})); document.execCommand('insertText',false,'拼'); 0")
        settle()
        check("document.getElementById('editor').scrollTop === 80", "composition does not move the candidate anchor while Chinese input is active")
        js("document.querySelector('.ProseMirror').dispatchEvent(new CompositionEvent('compositionend',{bubbles:true,data:'拼'})); 0")
        settle()
        check("(() => {const b=getSelection().getRangeAt(0).getBoundingClientRect(); return b.height>0 && Math.abs((b.top+b.bottom)/2-400)<35;})()", "completed composition resumes caret centering")
        js("window.WeiBeiEditor.setTypewriterMode(false); 0")
        check("document.body.dataset.typewriter === 'false' && parseFloat(css('#editor').paddingTop) === 36", "turning typewriter mode off restores normal document spacing")
        check("window.WeiBeiEditor.getMarkdown().replace('验证拼','') === window.savedMarkdown", "typography, zoom and typewriter toggles preserve note contents")
        js("window.WeiBeiEditor.setMarkdown('段落位置检查\\n\\n'.repeat(30)); window.WeiBeiEditor.selectDocumentEndForCheck(); window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}'); window.plusAligned = () => { const button=document.querySelector('.weibei-line-plus'); const b=button.getBoundingClientRect(); const p=document.querySelector('.ProseMirror p:last-child'); const r=p.querySelector('br').getBoundingClientRect(); const viewport=document.getElementById('editor').getBoundingClientRect(); if(r.bottom<=viewport.top || r.top>=viewport.bottom) return button.hidden; return !button.hidden && b.right < r.left && Math.abs((b.top+b.bottom-r.top-r.bottom)/2) < 1; }; 0")
        settle()
        js("document.querySelector('.ProseMirror p:last-child').scrollIntoView({block:'center'}); 0")
        wait { js("!document.querySelector('.weibei-line-plus').hidden && plusAligned()") as? Bool == true }
        check("!document.querySelector('.weibei-line-plus').hidden && plusAligned()", "the insert button is centered beside the empty-line caret")
        js("document.getElementById('editor').scrollTop -= 80; 0")
        wait { js("plusAligned()") as? Bool == true }
        check("plusAligned()", "the insert button follows manual scrolling")
        webView.frame.size.width = 420
        js("window.WeiBeiEditor.setTextScale(1.25); 0")
        settle()
        js("document.querySelector('.ProseMirror p:last-child').scrollIntoView({block:'center'}); 0")
        // Hidden WebKit delivers resize/scroll notifications asynchronously.
        wait { js("!document.querySelector('.weibei-line-plus').hidden && plusAligned()") as? Bool == true }
        check("!document.querySelector('.weibei-line-plus').hidden && plusAligned()", "the insert button stays beside the caret after split-pane resizing and text scaling")
        capture("notes-plus-narrow")
        js("window.WeiBeiEditor.setTextScale(1); 0")
        js("window.WeiBeiEditor.setEditable(false); 0")
        check("css('.ProseMirror').fontSize === '17px' && document.body.dataset.typewriter === 'false'", "read-only documents retain their own typography and do not enable typewriter scrolling")
        print("Notes typography check passed: layout, local fonts, six heading scales, split pane, typing, manual scroll, toggle, content preservation, read-only isolation")
    }
}
