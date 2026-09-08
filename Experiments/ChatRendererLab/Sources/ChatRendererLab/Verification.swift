import ChatRendererKit
import AppKit
import Foundation
import MarkdownView

enum LabFailure: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case let .message(value): return value } }
}

struct LabCheck: Codable {
    let name: String
    let passed: Bool
    let detail: String
}

struct LabReport: Encodable {
    let scope = "stage-A-candidate-component-only"
    let isProductionComparison = false
    let isFPSMeasurement = false
    let candidateRevision = "757b6fcc4b3095e84f4c0613f4b98147f49dcd09"
    let timestamp: String
    let operatingSystem: String
    let checks: [LabCheck]
    let timings: [LabTiming]
    let unverified: [String]
    var passed: Bool { !checks.isEmpty && checks.allSatisfy(\.passed) }
}

@MainActor
enum CandidateVerification {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw LabFailure.message(message) }
    }

    /// Timeout is a harness watchdog, not a performance acceptance threshold.
    static func waitForDisplay(_ document: CandidateDocument, revision: Int) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while document.displayedRevision < revision {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw LabFailure.message("Timed out waiting for the requested snapshot")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func settle(_ host: CandidateHost) async throws {
        var previous: CGFloat = -1
        var stable = 0
        for _ in 0..<80 {
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            if host.contentHeight == previous { stable += 1 } else { stable = 0 }
            if stable >= 2 { return }
            previous = host.contentHeight
            try await Task.sleep(for: .milliseconds(10))
        }
        throw LabFailure.message("Candidate height did not settle after content/width update")
    }

    static func run(host: CandidateHost, document: CandidateDocument, directory: URL) async throws -> LabReport {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var checks: [LabCheck] = []
        var timings: [LabTiming] = []

        func runCase(_ name: String, _ body: () async throws -> String) async {
            do {
                let detail = try await body()
                checks.append(.init(name: name, passed: true, detail: detail))
            } catch {
                checks.append(.init(name: name, passed: false, detail: String(describing: error)))
            }
            timings += document.timings + host.timings
        }

        await runCase("rich_content_readable_copy_and_math_resources") {
            let began = ProcessInfo.processInfo.systemUptime
            document.reset(); host.reset()
            try await waitForDisplay(document, revision: document.submit(LabSamples.rich))
            try await settle(host)
            let copied = host.copyAllWithoutPasteboard()
            try require(copied.contains(LabSamples.finalMarker), "Final source marker missing from copied text")
            try require(copied.contains(LabSamples.codeLine), "Code indentation/content did not survive copying")
            try require(copied.contains("Alpha") && copied.contains("Beta"), "Table content missing from copied text")
            try require(!copied.contains("\u{fffc}"), "Copy leaked an object replacement character")
            try require(host.measurementIsValid && host.contentHeight.isFinite && host.contentHeight > 1, "Invalid rich content height")
            guard let content = document.content else { throw LabFailure.message("No prepared document") }
            let codeKeys = content.blocks.compactMap { block -> Int? in
                guard case let .codeBlock(language, source) = block else { return nil }
                return CodeHighlighter.current.key(for: source, language: language)
            }
            while !codeKeys.allSatisfy({ CodeHighlighter.current.renderCache.value(forKey: $0)?.isEmpty == false }) {
                try require(ProcessInfo.processInfo.systemUptime - began < 10, "Asynchronous code highlighting did not finish")
                try await Task.sleep(for: .milliseconds(10))
            }
            timings.append(.init(operation: "cold_content_and_code_highlight_ready", milliseconds:
                (ProcessInfo.processInfo.systemUptime - began) * 1_000, revision: document.displayedRevision))
            try require(!content.rendered.isEmpty && content.rendered.values.allSatisfy { $0.image != nil },
                        "Math image creation failed; verify bundled fonts/resources")
            // Drawing probes are diagnostic only, outside all timing measurements.
            // A readable copied string alone does not prove visible code is drawn.
            try host.saveViewport(to: directory.appendingPathComponent("rich-top.png"))
            try host.saveRenderingDiagnostics(to: directory)
            if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true", let window = host.window {
                // A hosted CI runner is an isolated desktop, not the user's Mac.
                // Compare hidden-window capture with an ordered window; never do
                // this in local verification or claim it measures touchpad FPS.
                window.orderBack(nil)
                try await Task.sleep(for: .milliseconds(150))
                try await settle(host)
                try host.saveViewport(to: directory.appendingPathComponent("rich-ordered-window.png"))
                // Capture only our synthetic window on the isolated CI desktop.
                // Failure (e.g. recording permission) is recorded, not hidden.
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(window.windowNumber),
                    directory.appendingPathComponent("rich-windowserver.png").path]
                do {
                    try capture.run()
                    capture.waitUntilExit()
                    try "exit=\(capture.terminationStatus)\n".write(
                        to: directory.appendingPathComponent("window-capture.txt"), atomically: true, encoding: .utf8)
                } catch {
                    try String(describing: error).write(to: directory.appendingPathComponent("window-capture.txt"),
                                                       atomically: true, encoding: .utf8)
                }
                window.orderOut(nil)
            }
            host.scrollToBottom()
            try host.saveViewport(to: directory.appendingPathComponent("rich-bottom.png"))
            return "Read-only copy includes code, table text and final marker; math resources loaded. Visual placement is not asserted by copy."
        }

        await runCase("long_answer_resize_and_repeat_measurement") {
            document.reset(); host.reset()
            host.setFrameSize(NSSize(width: 768, height: 560))
            try await waitForDisplay(document, revision: document.submit(LabSamples.longAnswer))
            try await settle(host)
            let wide = host.contentHeight
            let parses = document.parseCount
            host.setFrameSize(NSSize(width: 392, height: 560))
            try await settle(host)
            let narrow = host.contentHeight
            try require(narrow > wide, "Long prose did not reflow when narrowed")
            host.setFrameSize(NSSize(width: 768, height: 560))
            try await settle(host)
            try require(abs(host.contentHeight - wide) <= 1, "Same width did not reproduce the same long-answer height")
            let measured = host.measurementCount
            for _ in 0..<6 { host.needsLayout = true; host.layoutSubtreeIfNeeded() }
            try require(host.measurementCount == measured, "Unchanged layout repeatedly requested full measurement")
            try require(document.parseCount == parses, "Width-only changes triggered parsing")
            try require(host.copyAllWithoutPasteboard().contains(LabSamples.finalMarker), "Long answer lost its tail")
            return "Wide=\(wide), narrow=\(narrow); width-only changes reuse parsed content. This does not verify a production scroll anchor."
        }

        await runCase("streaming_progress_final_snapshot_and_stale_reset") {
            document.reset(); host.reset()
            let chars = Array(LabSamples.rich)
            let middle = max(1, chars.count / 2)
            let initialRevision = document.submit(String(chars.prefix(middle)))
            try await waitForDisplay(document, revision: initialRevision)
            try require(document.content != nil, "No intermediate content was displayed")
            for end in stride(from: middle + 1, to: chars.count, by: 37) {
                document.submit(String(chars.prefix(end)))
                await Task.yield()
            }
            let finalRevision = document.submit(LabSamples.rich)
            try await waitForDisplay(document, revision: finalRevision)
            try await settle(host)
            try require(host.copyAllWithoutPasteboard().contains(LabSamples.finalMarker), "Streaming omitted final content")
            let parseCount = document.parseCount
            document.submit(LabSamples.rich)
            try require(document.parseCount == parseCount, "An identical final snapshot was parsed again")
            timings += document.timings + host.timings
            // Force a superseded in-flight input, then change to another document.
            document.submit(LabSamples.longAnswer)
            await Task.yield()
            document.reset(); host.reset()
            let fresh = "另一份独立内容。NEW_DOCUMENT_ONLY"
            try await waitForDisplay(document, revision: document.submit(fresh))
            try await settle(host)
            let copied = host.copyAllWithoutPasteboard()
            try require(copied.contains("NEW_DOCUMENT_ONLY") && !copied.contains(LabSamples.finalMarker),
                        "An obsolete result overwrote the new document")
            return "Intermediate and final snapshots displayed; reset excludes obsolete document results. Selection during editing remains unverified."
        }

        await runCase("prepared_document_remount_without_reparse") {
            document.reset(); host.reset()
            try await waitForDisplay(document, revision: document.submit(LabSamples.rich))
            guard let content = document.content else { throw LabFailure.message("No content to remount") }
            let parses = document.parseCount
            let replacement = CandidateHost(frame: host.bounds)
            replacement.present(content, theme: document.theme, revision: document.displayedRevision)
            try await settle(replacement)
            try require(replacement.copyAllWithoutPasteboard().contains(LabSamples.finalMarker), "Remount failed to bind prepared content")
            try require(document.parseCount == parses, "View remount reparsed the source")
            return "A new AppKit host can bind the existing prepared document; actual table reuse is stage B."
        }

        await runCase("native_extensions_images_wiki_and_callout_state") {
            let prepared = CandidateDocument()
            let view = CandidateTextView()
            var loadedImage = false
            view.imageLoader = { _, completion in
                loadedImage = true
                let image = NSImage(size: NSSize(width: 80, height: 40), flipped: false) { rect in
                    NSColor.red.setFill(); rect.fill(); return true
                }
                completion(image.tiffRepresentation)
            }
            view.bind(prepared)
            let source = "[[实验笔记|别名]]\n\n> [!note]- 提示\n> 展开后保留的文字\n\n![说明图](fixture-image)"
            try await waitForDisplay(prepared, revision: prepared.submit(source))
            view.frame = NSRect(x: 0, y: 0, width: 500, height: view.measuredHeight(for: 500))
            view.layoutSubtreeIfNeeded()
            let initial = view.textLabelView.attributedText.string
            try require(initial.contains("别名") && !initial.contains("[["), "Wiki alias did not become a link")
            try require(!initial.contains("展开后保留的文字"), "Collapsed callout displayed its body")
            try require(loadedImage && prepared.images["fixture-image"] != nil, "Image was not decoded into an actual native image")
            let parseCount = prepared.parseCount
            prepared.toggleCallout(0)
            try require(view.textLabelView.attributedText.string.contains("展开后保留的文字"), "Callout did not expand")
            try require(prepared.parseCount == parseCount, "Callout reparsed the source")
            view.unbind()
            let revisit = CandidateTextView()
            revisit.bind(prepared)
            try require(revisit.textLabelView.attributedText.string.contains("展开后保留的文字"), "Recycled callout lost expansion state")
            revisit.unbind()
            return "Native image decoded; wiki alias and retained callout expansion use the real candidate document."
        }

        let report = LabReport(timestamp: ISO8601DateFormatter().string(from: Date()),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            checks: checks, timings: timings, unverified: [
                "No TextKit baseline or production AgentPaneView comparison",
                "No claim about screen FPS, touchpad smoothness or reading-anchor stability",
                "Standalone viewer does not exercise the full source/action/Mermaid/GenUI workflow",
                "Actions/card drafts and selection during streaming/reuse not verified",
                "Compatibility with WeiBei's SwiftMath fork and root package not verified",
                "No minimum-OS, Intel/Apple-Silicon matrix claim"
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        return report
    }
}
