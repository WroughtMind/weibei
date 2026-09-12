// Run with: swift script/check_web_resources.swift BASE_APP NEW_APP OUTPUT_DIR
// Uses invisible WebKit views. No app window, system input, clipboard or library.
import AppKit
import CryptoKit
import WebKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("resource-check failed: \(message)\n", stderr); exit(1) }
}
func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(30)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    require(condition(), "WebKit timeout")
}
func encoded(_ value: Any) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), encoding: .utf8)!
}
let markdown = #"# 书写与阅读 Typography 123\n\n中文笔记与 English、かな、한글，**加粗**和 *倾斜*。\n\n## 二级标题\n\n### 三级标题\n\n#### 四级标题\n\n##### 五级标题\n\n###### 六级标题\n\n- 列表内容\n  - 嵌套内容\n\n> 引用内容\n\n| 项目 | 内容 |\n| --- | --- |\n| 表格 | 可编辑 |\n\n行内公式 $\alpha_1+\beta^2=\frac{x}{y}$。\n\n$$\mathbb{R}+\mathcal{F}+\mathfrak{g}+\sum_{i=1}^n x_i$$\n\n```swift\nlet note = "中文"\n```\n\n"#.replacingOccurrences(of: #"\n"#, with: "\n")
    + String(repeating: "连续书写的测试段落，中英文混排 Markdown 123。\n\n", count: 80)

final class Page: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let web: WKWebView
    private var loaded = false
    private(set) var visibleFontsReadyMS: Double = 0
    init(_ url: URL, editor: Bool, dark: Bool = false) {
        let started = ProcessInfo.processInfo.systemUptime
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(source: """
          window.initialMarkdown=\(encoded(markdown));
          window.weiBeiMarkdownEditable=true; window.weiBeiEditorCheckMode=true;
          window.weiBeiTheme='xuan';
          """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720), configuration: config)
        super.init()
        if !editor { config.userContentController.add(self, name: "size") }
        web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        web.navigationDelegate = self
        let directory = url.deletingLastPathComponent()
        // Match each production view: editor also reads Fonts; chat stays local.
        web.loadFileURL(url, allowingReadAccessTo: editor ? directory.deletingLastPathComponent() : directory)
        wait { self.loaded }
        if editor {
            wait { self.js("return Boolean(window.WeiBeiEditor && document.querySelector('.ProseMirror p'))") as? Bool == true }
            js("await document.fonts.ready; return true")
            visibleFontsReadyMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
            js("await Promise.all(Array.from(document.fonts, f => f.load())); await document.fonts.ready; return true")
            require(js("return [...document.fonts].every(f=>f.status==='loaded')") as? Bool == true, "local font loading")
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { require(false, error.localizedDescription) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { require(false, error.localizedDescription) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
    func close() { web.configuration.userContentController.removeAllScriptMessageHandlers(); web.stopLoading() }
    @discardableResult func js(_ body: String) -> Any? {
        var done = false
        var result: Any?
        Task { @MainActor in
            do { result = try await web.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page) }
            catch { require(false, "\((error as NSError).userInfo)\n\(body.prefix(200))") }
            done = true
        }
        wait { done }
        return result
    }
    func snapshot(_ path: URL) -> String {
        var done = false
        var digest = ""
        web.takeSnapshot(with: nil) { image, error in
            require(error == nil && image != nil, "snapshot: \(String(describing: error))")
            let bitmap = NSBitmapImageRep(data: image!.tiffRepresentation!)!
            try! bitmap.representation(using: .png, properties: [:])!.write(to: path)
            digest = SHA256.hash(data: Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)).map { String(format: "%02x", $0) }.joined()
            done = true
        }
        wait { done }
        return digest
    }
}

require(CommandLine.arguments.count == 4, "usage: BASE_APP NEW_APP OUTPUT_DIR")
NSApplication.shared.setActivationPolicy(.prohibited)
let roots = CommandLine.arguments[1...2].map { URL(fileURLWithPath: $0).appendingPathComponent("Contents/Resources") }
let output = URL(fileURLWithPath: CommandLine.arguments[3])
try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var report: [String: Any] = [:]
var cold = [[Double]](repeating: [], count: 2)
var visibleCold = cold
for trial in 0..<6 {
    for index in trial.isMultiple(of: 2) ? [0, 1] : [1, 0] {
        let started = ProcessInfo.processInfo.systemUptime
        let page = Page(roots[index].appendingPathComponent("Editor/index.html"), editor: true)
        cold[index].append((ProcessInfo.processInfo.systemUptime - started) * 1000)
        visibleCold[index].append(page.visibleFontsReadyMS)
        require(page.js("return document.fonts.check('16px Mplus1p') && document.fonts.check('16px \"Mplus1p Heading\"')") as? Bool == true, "Mplus font load")
    }
}
report["editor_load_all_fonts_ms"] = cold
report["editor_visible_fonts_ready_ms"] = visibleCold
let pages = roots.map { Page($0.appendingPathComponent("Editor/index.html"), editor: true) }
var layoutSamples = [[Double]](repeating: [], count: 2)
for theme in ["xuan", "paper", "inkstone", "stele"] {
    for width in [420, 680, 1280] {
        var signatures: [String] = []
        for (index, page) in pages.enumerated() {
            page.web.frame.size.width = CGFloat(width)
            page.js("window.WeiBeiEditor.setTheme(\(encoded(theme))); return true")
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let signature = page.js("""
              const elements=[...document.querySelectorAll('.ProseMirror p,.ProseMirror h1,.ProseMirror h2,.ProseMirror h3,.ProseMirror h4,.ProseMirror h5,.ProseMirror h6,.katex')];
              return JSON.stringify(elements.map(e=>{const b=e.getBoundingClientRect(),s=getComputedStyle(e);return [e.textContent,b.x,b.y,b.width,b.height,s.fontFamily,s.fontSize,s.color]}));
              """) as! String
            signatures.append(signature)
            let digest = page.snapshot(output.appendingPathComponent("editor-\(theme)-\(width)-\(index).png"))
            report["editor-\(theme)-\(width)-\(index)"] = digest
        }
        require(signatures[0] == signatures[1], "editor glyph metrics, line wrapping or theme changed: \(theme), \(width)")
        require(report["editor-\(theme)-\(width)-0"] as? String == report["editor-\(theme)-\(width)-1"] as? String, "editor pixels changed: \(theme), \(width)")
    }
}
for _ in 0..<7 {
    for (index, page) in pages.enumerated() {
        let ms = page.js("""
          const e=document.getElementById('editor'), start=performance.now();
          for(let i=0;i<120;i++){e.style.width=(i%2 ? 420 : 960)+'px';e.scrollTop=i*20;e.getBoundingClientRect();document.querySelector('.ProseMirror').getBoundingClientRect();}
          e.style.width='';e.scrollTop=0;return performance.now()-start;
          """) as! Double
        layoutSamples[index].append(ms)
    }
}
report["editor_120_resize_scroll_layouts_ms"] = layoutSamples

let diagrams = [
    "flowchart LR\n A[阅读很长的中文标题与 English wrapping] --> B{理解？}\n B -->|是| C[整理]\n B -->|否| A",
    "sequenceDiagram\n participant A as 用户\n participant B as 魏碑\n A->>B: 阅读与提问\n B-->>A: 引用与回答",
    "classDiagram\n Animal <|-- Duck\n Animal : +int age\n Duck : +quack()",
    "stateDiagram-v2\n [*] --> Reading\n Reading --> Writing\n Writing --> [*]",
    "erDiagram\n COURSE ||--o{ NOTE : contains",
    "gantt\n title 学习安排\n dateFormat YYYY-MM-DD\n section 阅读\n 第一章 :2026-09-01, 3d\n 第二章 :2026-09-04, 2d",
    "pie title 课程\n \"阅读\" : 60\n \"整理\" : 40",
    "journey\n title 阅读旅程\n section 学习\n 阅读: 5: 我\n 笔记: 4: 我",
    "gitGraph\n commit id: \"root\"\n branch notes\n checkout notes\n commit id: \"note\"\n checkout main\n merge notes id: \"merge\"",
    "mindmap\n root((魏碑))\n  阅读\n  笔记\n  问答",
    "timeline\n title 学习进度\n 2025 : 阅读\n 2026 : 复习",
    "xychart-beta\n x-axis [Mon, Tue, Wed]\n y-axis 0 --> 100\n bar [20, 60, 40]",
    "block-beta\n columns 3\n A B C\n A --> B\n B --> C",
    "quadrantChart\n x-axis Low --> High\n y-axis Low --> High\n Study: [0.4, 0.6]",
    "sankey-beta\nReading,Notes,10\nNotes,Review,5",
    "packet-beta\n 0-7: \"Header\"\n 8-15: \"Data\"",
    "kanban\n todo[Todo]\n  read[Reading]\n done[Done]\n  note[Notes]",
    "architecture-beta\n service db(database)[Database]\n service server(server)[Server]\n db:L -- R:server",
]
var diagramTimings = [[Double]](repeating: [], count: 2)
for dark in [false, true] {
    let views = roots.enumerated().map { index, root in
        Page(root.appendingPathComponent(index == 0 ? "Web/diagram.html" : "Editor/diagram.html"), editor: false, dark: dark)
    }
    for (fixture, source) in diagrams.enumerated() {
        var geometry: [String] = []
        for (index, page) in views.enumerated() {
            page.web.frame.size = NSSize(width: 1280, height: 900)
            let result = page.js("""
              const start=performance.now(); await renderDiagram(\(encoded(source)), \(fixture+1));
              const svg=document.querySelector('#diagram svg');
              if(!svg)throw new Error(document.querySelector('#error').textContent);
              return {ms:performance.now()-start, geometry:JSON.stringify([...svg.querySelectorAll('rect,circle,ellipse,path,line,polygon,foreignObject,text')].filter(e=>!e.closest('defs')).map(e=>{const b=e.getBBox();return [e.tagName,b.x,b.y,b.width,b.height,e.textContent]}))};
              """) as! [String: Any]
            diagramTimings[index].append(result["ms"] as! Double)
            geometry.append(result["geometry"] as! String)
            report["diagram-\(dark)-\(fixture)-\(index)"] = page.snapshot(output.appendingPathComponent("diagram-\(dark)-\(fixture)-\(index).png"))
            page.web.frame.size.width = 420
            require(page.js("const s=document.querySelector('#diagram svg');return s.width.baseVal.value>0 && s.height.baseVal.value>0 && Math.abs(s.getBoundingClientRect().width-s.viewBox.baseVal.width)<1") as? Bool == true, "diagram sizing after pane resize")
        }
        report["diagram_geometry_equal_\(dark)_\(fixture)"] = geometry[0] == geometry[1]
        if geometry[0] != geometry[1] { try! geometry.joined(separator: "\n").write(to: output.appendingPathComponent("diagram-diff-\(dark)-\(fixture).jsonl"), atomically: true, encoding: .utf8) }
    }
    views.forEach { $0.close() }
}
report["diagram_render_ms"] = diagramTimings
try! encoded(report).write(to: output.appendingPathComponent("results.json"), atomically: true, encoding: .utf8)
print("resource comparison complete: \(output.path)")
