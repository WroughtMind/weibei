import Foundation
import CryptoKit
import WebKit
import XCTest
import WeiBeiCore
@testable import WeiBei

@MainActor
final class HTMLResourceImportTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    // One dragged page must retain styles and working scripts after its original folder is gone.
    func testPortableHTMLRendersAfterSourceFolderIsRemoved() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try Data(contentsOf: fixture.page)
        let imported = try ImportFileCopy.copyPreservingOriginal(from: fixture.page, into: fixture.library)
        XCTAssertEqual(try Data(contentsOf: fixture.page), original)
        XCTAssertEqual(try ImportFileCopy.copyPreservingOriginal(from: fixture.page, into: fixture.library), imported)
        let data = try Data(contentsOf: imported)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(HTMLResourceImport.missingResourcesMetaName),
                       String(decoding: data, as: UTF8.self))
        let moved = fixture.root.appendingPathComponent("moved.html")
        try FileManager.default.moveItem(at: imported, to: moved)
        try FileManager.default.removeItem(at: fixture.source)

        let reader = WebReaderRepresentable(url: moved, appearanceMode: .glassSlate, onSelectionChange: { _, _ in })
        let coordinator = reader.makeCoordinator()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(coordinator.htmlResourceSchemeHandler,
                                          forURLScheme: WebReaderResourceSchemeHandler.scheme)
        configuration.userContentController.addUserScript(WKUserScript(
            source: WebReaderRepresentable.readerStyleScript(for: .glassSlate, adaptsDocumentColors: false),
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        coordinator.webView = web
        coordinator.loadedSignature = moved.path
        web.navigationDelegate = coordinator
        coordinator.loadUTF8HTML(at: moved, signature: moved.path, into: web)
        let deadline = Date().addingTimeInterval(12)
        var result: [String: Any]?
        while Date() < deadline {
            result = try? await web.evaluateJavaScript("""
            (() => {
              const sheet = document.querySelector('.sheet');
              if (!sheet) return null;
              const s = getComputedStyle(sheet);
              return {color:s.color, background:s.backgroundColor, width:s.maxWidth,
                border:s.borderTopWidth, image:document.querySelector('img').naturalWidth,
                responsive:document.querySelector('#responsive').naturalWidth > 0,
                font:[...document.fonts].some(f => f.family === 'Portable' && f.status === 'loaded'),
                quiz:window.quizReady === true, module:window.moduleAnswer === 42,
                inlineModule:window.inlineAnswer === 42,
                text:sheet.textContent.includes('计量上机')};
            })()
            """) as? [String: Any]
            if result?["quiz"] as? Bool == true, result?["module"] as? Bool == true,
               result?["image"] as? Int == 2, result?["border"] as? String == "3px",
               result?["font"] as? Bool == true { break }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTAssertEqual(result?["color"] as? String, "rgb(12, 34, 56)")
        XCTAssertEqual(result?["background"] as? String, "rgb(240, 230, 220)")
        XCTAssertEqual(result?["width"] as? String, "720px")
        XCTAssertEqual(result?["border"] as? String, "3px")
        XCTAssertEqual(result?["image"] as? Int, 2)
        XCTAssertEqual(result?["responsive"] as? Bool, true)
        XCTAssertEqual(result?["font"] as? Bool, true)
        XCTAssertEqual(result?["quiz"] as? Bool, true)
        XCTAssertEqual(result?["module"] as? Bool, true)
        XCTAssertEqual(result?["inlineModule"] as? Bool, true)
        XCTAssertEqual(result?["text"] as? Bool, true)
        XCTAssertEqual(try HTMLResourceImport.dataIfHTML(at: moved), data)
        web.stopLoading()
    }

    // Both actual import entrances must prepare the page, including course drag without a confirmation dialog.
    func testCommonAndCourseEntrancesImportOnePortableFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let workspace = fixture.root.appendingPathComponent("workspace")
        let store = WorkspaceStore(workspaceDirectory: workspace,
                                   startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        try store.configureCourseLibrary(at: fixture.library)
        let common = importFilesAndWait(store, [fixture.page])
        let courseID = try store.createCourseInLibrary(title: "HTML")
        let course = try store.waitForCourseFileOperation {
            await withCheckedContinuation { continuation in
                store.importCourseFilesFromURLs([fixture.page], courseID: courseID) {
                    continuation.resume(returning: $0)
                }
            }
        }
        XCTAssertEqual(common.count, 1)
        XCTAssertEqual(course.count, 1)
        let expected = try HTMLResourceImport.dataIfHTML(at: fixture.page)
        for item in common + course {
            let url = try XCTUnwrap(item.url)
            XCTAssertEqual(try Data(contentsOf: url), expected)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.page.path))
    }

    // A failed course save removes the transformed copy and keeps the source untouched.
    func testFailedCourseImportPreservesSourceAndRemovesUncommittedCopy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try Data(contentsOf: fixture.page)
        var failSave = false
        let store = WorkspaceStore(
            workspaceDirectory: fixture.root.appendingPathComponent("workspace"),
            courseProjectMutationHook: { stage in
                if failSave, stage == .beforeCourseFileWorkspaceSave { throw CocoaError(.fileWriteUnknown) }
            }, startsAtBlankEntries: true, startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: fixture.library)
        let courseID = try store.createCourseInLibrary(title: "HTML")
        let target = try XCTUnwrap(store.courseRootURL(for: courseID))
            .appendingPathComponent("文稿/lesson.html")
        failSave = true
        XCTAssertThrowsError(try store.waitForCourseFileOperation {
            try await store.importFileIntoCourse(fixture.page, courseID: courseID, role: .material)
        })
        XCTAssertEqual(try Data(contentsOf: fixture.page), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(store.courseMaterials(in: courseID).isEmpty)
    }

    // Missing or unsafe resources must never destroy readable content or copy symlink/private data.
    func testUnavailableResourcesAreNonblockingAndDoNotEscapeThroughLinks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let secret = fixture.root.appendingPathComponent("private.css")
        try Data("SECRET_SHOULD_NOT_BE_IMPORTED".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(at: fixture.source.appendingPathComponent("assets/link.css"),
                                                   withDestinationURL: secret)
        let html = """
        <!DOCTYPE html><meta charset="utf-8">
        <link rel="stylesheet" href="../assets/missing.css">
        <link rel="stylesheet" href="../assets/link.css">
        <link rel="stylesheet" href="../assets/cycle.css">
        <script src="../assets/quiz.js" integrity="sha384-invalid"></script>
        <p>正文仍须保存</p>
        """
        try Data(html.utf8).write(to: fixture.page)
        try Data("@import 'cycle.css'; p{color:red}".utf8).write(to: fixture.source.appendingPathComponent("assets/cycle.css"))
        let imported = try ImportFileCopy.copyPreservingOriginal(from: fixture.page, into: fixture.library)
        let data = try Data(contentsOf: imported)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(HTMLResourceImport.missingResourcesMetaName))
        XCTAssertTrue(text.contains("missing.css"))
        XCTAssertTrue(text.contains("link.css"))
        XCTAssertTrue(text.contains("cycle.css"))
        XCTAssertTrue(text.contains("quiz.js"))
        XCTAssertFalse(text.contains(Data("window.quizReady = true;".utf8).base64EncodedString()))
        XCTAssertFalse(text.contains(Data("SECRET_SHOULD_NOT_BE_IMPORTED".utf8).base64EncodedString()))
        XCTAssertEqual(try Data(contentsOf: fixture.page), Data(html.utf8))
        XCTAssertEqual(try HTMLResourceImport.dataIfHTML(at: imported), data)
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let page: URL
        let library: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("weibei-html-test-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            source = root.appendingPathComponent("source")
            page = source.appendingPathComponent("lessons/lesson.html")
            library = root.appendingPathComponent("library")
            for directory in [page.deletingLastPathComponent(), source.appendingPathComponent("assets/nested"), library] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            func write(_ path: String, _ value: String) throws {
                try Data(value.utf8).write(to: source.appendingPathComponent(path))
            }
            try write("lessons/lesson.html", """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <link rel="stylesheet" href="../assets/style.css">
            <script defer src="../assets/quiz.js"></script>
            <script type="module" src="../assets/module.js"></script>
            <script type="module">import{value}from'../assets/value.js';window.inlineAnswer=value;</script></head>
            <body><main class="sheet"><h1>计量上机</h1><span class="font">ABC</span>
            <img src="../assets/photo%20one.svg">
            <img id="responsive" srcset="../assets/photo%20one.svg 1x, ../assets/photo%20one.svg 2x">
            <pre>line 1\n    line 2</pre><svg viewBox="0 0 2 2"><path d="M0 0h2v2H0z"/></svg>
            </main></body></html>
            """)
            try write("assets/style.css", """
            @import url("nested/theme.css");
            @font-face{font-family:Portable;src:url('font.woff2')} .font{font-family:Portable}
            .sheet {max-width:720px;color:rgb(12,34,56);background-color:rgb(240,230,220)}
            .sheet::before {content:"url(not-a-resource.png)"}
            /* url(also-not-a-resource.png) */
            """)
            try write("assets/nested/theme.css", ".sheet{border-top:3px solid black;background-image:url('../photo\\20 one.svg')}")
            try write("assets/photo one.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"2\"><path d=\"M0 0h2v2H0z\"/></svg>")
            try write("assets/quiz.js", "window.quizReady = true;")
            try write("assets/module.js", "import {\n value\n} from './value.js'; window.moduleAnswer = value;")
            try write("assets/value.js", "export const value = 42;")
            let font = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/WeiBei/Resources/Editor/KaTeX_Main-Regular.woff2")
            try FileManager.default.copyItem(at: font, to: source.appendingPathComponent("assets/font.woff2"))
            let stylesheet = try Data(contentsOf: source.appendingPathComponent("assets/style.css"))
            let integrity = "sha384-" + Data(SHA384.hash(data: stylesheet)).base64EncodedString()
            let html = try String(contentsOf: page, encoding: .utf8)
                .replacingOccurrences(of: "href=\"../assets/style.css\"",
                                      with: "href=\"../assets/style.css\" integrity=\"\(integrity)\"")
            try Data(html.utf8).write(to: page)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
