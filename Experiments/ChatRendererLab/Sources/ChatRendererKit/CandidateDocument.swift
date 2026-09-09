import AppKit
import Foundation
import MarkdownParser
import MarkdownView

/// Each actor invocation parses one immutable snapshot. UI work stays on MainActor.
private actor ParseWorker {
    func parse(_ source: String) -> (MarkdownParser.ParseResult, Double) {
        let start = ProcessInfo.processInfo.systemUptime
        let result = MarkdownParser().parse(source)
        return (result, (ProcessInfo.processInfo.systemUptime - start) * 1_000)
    }
}

public struct LabTiming: Codable {
    public let operation: String
    public let milliseconds: Double
    public let revision: Int
    public init(operation: String, milliseconds: Double, revision: Int) {
        self.operation = operation; self.milliseconds = milliseconds; self.revision = revision
    }
}

/// Preparation belongs to the document, not the disposable display view.
/// One worker plus one latest pending snapshot; completed valid results can display
/// even if more input arrived. No network token pacing is implemented here.
@MainActor
public final class CandidateDocument {
    private struct Input {
        let source: String
        let revision: Int
        let epoch: Int
        let submittedAt: Double
    }

    private let parser = ParseWorker()
    private var pending: Input?
    private var working = false
    private var epoch = 0
    private var latestSource: String?
    private var parsed: MarkdownParser.ParseResult?
    public private(set) var attachments: [Int: CandidateAttachment] = [:]
    public private(set) var toggledCallouts: Set<Int> = []
    public var measuredHeights: [CGFloat: CGFloat] = [:]
    public var selectedRange: NSRange?
    public var images: [String: NSImage] = [:]
    public private(set) var requestedRevision = 0
    public private(set) var displayedRevision = 0
    public private(set) var parseCount = 0
    public private(set) var content: MarkdownContent?
    public private(set) var timings: [LabTiming] = []
    public private(set) var appliedRevisions: [Int] = []
    public private(set) var theme: MarkdownTheme
    public func record(_ timing: LabTiming) { timings.append(timing) }
    public var onApply: ((MarkdownContent, Int) -> Void)?

    public func configure(fontSize: CGFloat, ink: NSColor, secondaryInk: NSColor, accent: NSColor,
                          paper: NSColor, separator: NSColor, selection: NSColor) {
        var next = theme
        next.fonts.body = .systemFont(ofSize: fontSize)
        next.fonts.bold = .boldSystemFont(ofSize: fontSize)
        next.fonts.italic = NSFontManager.shared.convert(next.fonts.body, toHaveTrait: .italicFontMask)
        next.fonts.codeInline = .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        next.fonts.code = next.fonts.codeInline
        next.fonts.title = .boldSystemFont(ofSize: fontSize * 1.35)
        next.fonts.largeTitle = .boldSystemFont(ofSize: fontSize * 1.7)
        next.colors.body = ink
        next.colors.code = ink
        next.colors.highlight = accent
        next.colors.emphasis = secondaryInk
        next.colors.selectionBackground = selection
        next.table.headerBackgroundColor = paper
        next.table.borderColor = separator
        next.table.stripeCellBackgroundColor = paper.withAlphaComponent(0.35)
        guard next != theme else { return }
        theme = next
        if let parsed { prepare(parsed, revision: displayedRevision) }
    }

    public func toggleCallout(_ id: Int) {
        if toggledCallouts.contains(id) { toggledCallouts.remove(id) } else { toggledCallouts.insert(id) }
        if let parsed { prepare(parsed, revision: displayedRevision) }
    }

    private func prepare(_ parsed: MarkdownParser.ParseResult, revision: Int) {
        let start = ProcessInfo.processInfo.systemUptime
        var extensions = CandidateExtensions(toggledCallouts: toggledCallouts,
            displayMath: Set(parsed.displayMath.map {
                MarkdownParser.replacementText(for: .math, identifier: String($0))
            }))
        let blocks = extensions.blocks(parsed.document)
        attachments = extensions.attachments
        let prepared = MarkdownContent(blocks: blocks, rendered: parsed.renderedContent(theme: theme),
            highlightMaps: parsed.highlightMaps(theme: theme), locale: Locale(identifier: "zh_Hans_CN"))
        measuredHeights.removeAll(keepingCapacity: true)
        content = prepared
        displayedRevision = revision
        appliedRevisions.append(revision)
        timings.append(.init(operation: "main_prepare", milliseconds:
            (ProcessInfo.processInfo.systemUptime - start) * 1_000, revision: revision))
        onApply?(prepared, revision)
    }

    public init() {
        var theme = MarkdownTheme.default
        theme.fonts.body = .systemFont(ofSize: 16)
        theme.fonts.bold = .boldSystemFont(ofSize: 16)
        theme.fonts.italic = NSFontManager.shared.convert(theme.fonts.body, toHaveTrait: .italicFontMask)
        theme.fonts.codeInline = .monospacedSystemFont(ofSize: 15, weight: .regular)
        theme.fonts.code = .monospacedSystemFont(ofSize: 15, weight: .regular)
        theme.fonts.title = .boldSystemFont(ofSize: 21)
        theme.fonts.largeTitle = .boldSystemFont(ofSize: 26)
        self.theme = theme
    }

    /// Switch to another sample without allowing old parsing to apply to it.
    public func reset() {
        epoch += 1
        pending = nil
        latestSource = nil
        content = nil
        parsed = nil
        attachments.removeAll()
        toggledCallouts.removeAll()
        measuredHeights.removeAll()
        images.removeAll()
        selectedRange = nil
        requestedRevision = 0
        displayedRevision = 0
        parseCount = 0
        timings.removeAll()
        appliedRevisions.removeAll()
    }

    @discardableResult
    public func submit(_ source: String) -> Int {
        if latestSource == source { return requestedRevision }
        latestSource = source
        requestedRevision += 1
        pending = Input(source: source, revision: requestedRevision, epoch: epoch,
                        submittedAt: ProcessInfo.processInfo.systemUptime)
        guard !working else { return requestedRevision }
        working = true
        Task { [weak self] in
            guard let self else { return }
            while let input = self.pending {
                self.pending = nil
                let (parsed, parseMS) = await self.parser.parse(input.source)
                guard input.epoch == self.epoch else { continue }
                self.parseCount += 1
                self.timings.append(.init(operation: "background_parse", milliseconds: parseMS, revision: input.revision))
                self.parsed = parsed
                self.prepare(parsed, revision: input.revision)
                self.timings.append(.init(operation: "submitted_to_apply", milliseconds:
                    (ProcessInfo.processInfo.systemUptime - input.submittedAt) * 1_000, revision: input.revision))
            }
            self.working = false
        }
        return requestedRevision
    }
}
