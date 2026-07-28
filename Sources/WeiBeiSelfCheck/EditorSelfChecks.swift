import Foundation
import WeiBeiCore

/**
 * 验证网页编辑器资源、模块边界与交互源码契约。
 */
enum EditorSelfChecks {
    /**
     * 执行该领域的自检。
     */
    static func run(repositoryURL: URL) throws {
        let editorIndexURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
        let editorIndexSource = (try? String(contentsOf: editorIndexURL, encoding: .utf8)) ?? ""
        expect(!editorIndexSource.contains("WeiBeiStele")
            && !editorIndexSource.contains("--font-brand-latin")
            && !editorIndexSource.contains("font-family: var(--font-brand-latin)")
            && editorIndexSource.contains(".ProseMirror h1,\n    .ProseMirror h2,\n    .ProseMirror h3")
            && editorIndexSource.contains("letter-spacing: 0;"), "Web Markdown editor does not apply bundled WeiBei display fonts inside Markdown file content")
        expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout::before { content: attr(data-callout-title); }")
            && !editorIndexSource.contains("content: \"札记\"")
            && !editorIndexSource.contains("content: \"提示\"")
            && !editorIndexSource.contains("content: \"重点\"")
            && !editorIndexSource.contains("content: \"风险\""), "Markdown callout labels come from data-callout-title instead of hardcoded Chinese CSS")
        expect(
            editorIndexSource.contains(".ProseMirror span[data-type=\"math_inline\"],")
                && editorIndexSource.contains(".ProseMirror span[data-type=\"math-inline\"],")
                && editorIndexSource.contains(".ProseMirror div[data-type=\"math-block\"],")
                && editorIndexSource.contains(".ProseMirror .math-inline")
                && editorIndexSource.contains(".ProseMirror .math-block"),
            "math styling hides raw source for common Milkdown math node attribute and class shapes"
        )
        expect(
            editorIndexSource.contains(".ProseMirror .math-inline {\n      color: transparent")
                && editorIndexSource.contains("font-size: 0;")
                && editorIndexSource.contains("font-size: 1rem;")
                && editorIndexSource.contains(".ProseMirror .katex-error {\n      color: var(--cinnabar)"),
            "math styling collapses raw source while keeping KaTeX and errors readable"
        )
        expect(editorIndexSource.contains("color: rgba(58, 46, 38, .56)") && !editorIndexSource.contains("color: rgba(58, 46, 38, .36)"), "editable markdown markers stay readable on paper")
        expect(editorIndexSource.contains(".frontmatter-title {\n      color: var(--muted)") && editorIndexSource.contains("li[data-item-type=\"task\"][data-checked=\"true\"] {\n      color: var(--muted)"), "small frontmatter and completed task text avoid faint low-contrast ink")
        if let frontmatterStart = editorIndexSource.range(of: ":root[data-weibei-theme=\"inkstone\"] #frontmatter-panel")?.lowerBound,
           let frontmatterEnd = editorIndexSource[frontmatterStart...].range(of: "\n\n    .ProseMirror")?.lowerBound {
            let darkFrontmatterSource = String(editorIndexSource[frontmatterStart..<frontmatterEnd])
            expect(darkFrontmatterSource.contains("background: var(--paper-raised);")
                && darkFrontmatterSource.contains("border-color: var(--line);")
                && darkFrontmatterSource.contains("border-left-color: var(--cinnabar-line);")
                && !darkFrontmatterSource.contains("rgba(28, 28, 28")
                && !darkFrontmatterSource.contains("border-color: #2d2d2d"), "dark frontmatter panel uses shared theme variables instead of hardcoded ink blocks")
        } else {
            expect(false, "dark frontmatter panel style is readable")
        }
        expect(editorIndexSource.contains(".weibei-source-reference") && editorIndexSource.contains("border-bottom: 1px dotted"), "source references have readable link styling")
        expect(editorIndexSource.contains("scrollbar-width: thin")
            && editorIndexSource.contains("scrollbar-color: transparent transparent")
            && editorIndexSource.contains("#editor::-webkit-scrollbar {\n      width: 6px;")
            && editorIndexSource.contains("#editor.weibei-scroll-active::-webkit-scrollbar-thumb")
            && editorIndexSource.contains(".ProseMirror pre::-webkit-scrollbar-thumb")
            && editorIndexSource.contains("width: 5px;")
            && editorIndexSource.contains("background: transparent;")
            && editorIndexSource.contains(".ProseMirror pre.weibei-scroll-active::-webkit-scrollbar-thumb")
            && editorIndexSource.contains("background: rgba(92, 70, 46, .16)"), "web editor root and internal code/math scrollbars fade in while active instead of disappearing completely")
        expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout[data-callout-title=\"阅读线索\"]")
            && editorIndexSource.contains("background: rgba(251, 245, 234, .18);")
            && editorIndexSource.contains("box-shadow: none;")
            && editorIndexSource.contains("border-left-color: rgba(145, 38, 28, .28);"), "reading-line callouts render as light margin notes instead of heavy cards")
        expect(editorIndexSource.contains(":root[data-weibei-theme=\"inkstone\"] .ProseMirror blockquote.weibei-callout[data-callout-title=\"阅读线索\"]")
            && editorIndexSource.contains("background: rgba(166, 54, 43, .055);")
            && editorIndexSource.contains("border-left-color: rgba(166, 54, 43, .38);"), "reading-line callouts use a dark-theme wash instead of a stray pale paper block")
        expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout .weibei-callout-marker")
            && editorIndexSource.contains("display: inline-block !important;")
            && editorIndexSource.contains("opacity: 0 !important;")
            && editorIndexSource.contains("visibility: hidden !important;")
            && editorIndexSource.contains("width: 0 !important;")
            && editorIndexSource.contains("max-width: 0 !important;")
            && editorIndexSource.contains("overflow: hidden !important;"), "Obsidian callout source markers collapse inside rendered callouts")
        expect(editorIndexSource.contains("body[data-editable=\"true\"] .ProseMirror blockquote.weibei-callout.weibei-callout-has-heading::before")
            && editorIndexSource.contains("body[data-editable=\"false\"] .ProseMirror blockquote.weibei-callout .weibei-callout-heading {\n      display: none;"), "callout headings stay editable while read-only callouts show the rendered title instead of leaking the raw [!type] source line")
        expect(editorIndexSource.contains(".ProseMirror::selection,\n    .ProseMirror ::selection")
            && editorIndexSource.contains("background: var(--selection);"), "web editor selection highlight covers both root and nested ProseMirror text")
        expect(editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] #editor")
            && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] .milkdown")
            && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] .ProseMirror")
            && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"][data-weibei-theme=\"inkstone\"] body")
            && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"][data-weibei-theme=\"inkstone\"] #editor")
            && editorIndexSource.contains("min-height: 0;"), "web markdown renderer has a compact preview mode for inline agent answers without dark theme background blocks")
        let webEditorSourceDirectoryURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/WebEditor/src")
        let webEditorSourceURLs = ((FileManager.default.enumerator(
            at: webEditorSourceDirectoryURL,
            includingPropertiesForKeys: nil
        )?.allObjects as? [URL]) ?? [])
            .filter { $0.pathExtension == "js" }
            .sorted { $0.path < $1.path }
        let webEditorSource = webEditorSourceURLs
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let editorScriptSource = webEditorSource
        let webEditorRelativeSourcePaths = Set(webEditorSourceURLs.map {
            $0.path.replacingOccurrences(of: webEditorSourceDirectoryURL.path + "/", with: "")
        })
        expect(Set([
            "api.js",
            "core/bridge.js",
            "core/i18n.js",
            "core/theme.js",
            "editor.js",
            "features/code-rendering.js",
            "features/decorations.js",
            "features/images.js",
            "features/input-behaviors.js",
            "features/preview.js",
            "features/selection.js",
            "features/slash/commands.js",
            "features/slash/menu.js",
            "markdown/normalize.js",
            "markdown/obsidian.js",
        ]).isSubset(of: webEditorRelativeSourcePaths), "web editor behavior is split into explicit core, markdown, feature, slash, and public API modules")
        expect(editorScriptSource.contains("installQuietScrollIndicators")
            && editorScriptSource.contains("const quietScrollableSelector = '#editor, .ProseMirror pre")
            && editorScriptSource.contains("weibei-scroll-active")
            && editorScriptSource.contains("window.setTimeout(() =>")
            && editorScriptSource.contains("}, 850)"), "web editor removes internal scroll indicator state after a short idle delay")
        expect(editorScriptSource.contains("document.addEventListener('pointerdown', () =>")
            && editorScriptSource.contains("post('selectionChanged', { text: '', rect: null });"), "web editor clears stale selection context as soon as the user starts a new click or drag")
        expect(editorScriptSource.contains("import { liftListItem } from '@milkdown/kit/prose/schema-list';")
            && editorScriptSource.contains("const emptyListItemTypeAtSelection = (state) =>")
            && editorScriptSource.contains("const exitEmptyListItem = (view) =>")
            && editorScriptSource.contains("handleKeyDown(view, event)")
            && editorScriptSource.contains("event.key === 'Enter'")
            && editorScriptSource.contains("&& exitEmptyListItem(view)")
            && editorScriptSource.contains("event.preventDefault();")
            && editorScriptSource.contains("pressKeyForCheck")
            && editorScriptSource.contains("selection.checkAPI()"), "web editor exits an empty Markdown list item on a second Enter instead of looping bullets")
        expect(editorScriptSource.contains("const isCompactPreview = window.weiBeiMarkdownCompactPreview === true")
            && editorScriptSource.contains("post('contentHeightChanged', { height })")
            && editorScriptSource.contains("new ResizeObserver(reportContentHeight)")
            && editorScriptSource.contains("installContentHeightObserver()"), "web editor reports compact markdown preview height back to Swift")
        if let mermaidStart = editorIndexSource.range(of: ":root[data-weibei-theme=\"inkstone\"] .weibei-mermaid-render")?.lowerBound,
           let mermaidEnd = editorIndexSource[mermaidStart...].range(of: "\n    .weibei-mermaid-render svg")?.lowerBound {
            let darkMermaidSource = String(editorIndexSource[mermaidStart..<mermaidEnd])
            expect(darkMermaidSource.contains("background: var(--paper-raised);")
                && darkMermaidSource.contains("border-color: var(--line);")
                && !darkMermaidSource.contains("background: #151515;")
                && !darkMermaidSource.contains("border-color: #2d2d2d;"), "dark Mermaid render boxes use shared theme variables instead of hardcoded ink blocks")
        } else {
            expect(false, "dark Mermaid render style is readable")
        }
    }
}
