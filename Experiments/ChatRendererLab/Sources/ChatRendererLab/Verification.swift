import AppKit
import Foundation

enum LabFailure: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case let .message(value): return value } }
}

struct LabCheck: Codable {
    let name: String
    let passed: Bool
    let detail: String
}

struct LabReport: Codable {
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
            try require(!content.rendered.isEmpty && content.rendered.values.allSatisfy { $0.image != nil },
                        "Math image creation failed; verify bundled fonts/resources")
            try host.saveViewport(to: directory.appendingPathComponent("rich-top.png"))
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

        let report = LabReport(timestamp: ISO8601DateFormatter().string(from: Date()),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            checks: checks, timings: timings, unverified: [
                "No TextKit baseline or production AgentPaneView comparison",
                "No claim about screen FPS, touchpad smoothness or reading-anchor stability",
                "Inline images, wiki/callout/source actions, Mermaid and GenUI not integrated",
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
