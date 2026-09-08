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

struct LabTiming: Codable {
    let operation: String
    let milliseconds: Double
    let revision: Int
}

/// Preparation belongs to the document, not the disposable display view.
/// One worker plus one latest pending snapshot; completed valid results can display
/// even if more input arrived. No network token pacing is implemented here.
@MainActor
final class CandidateDocument {
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
    private(set) var requestedRevision = 0
    private(set) var displayedRevision = 0
    private(set) var parseCount = 0
    private(set) var content: MarkdownContent?
    private(set) var timings: [LabTiming] = []
    private(set) var appliedRevisions: [Int] = []
    let theme: MarkdownTheme
    var onApply: ((MarkdownContent, Int) -> Void)?

    init() {
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
    func reset() {
        epoch += 1
        pending = nil
        latestSource = nil
        content = nil
        requestedRevision = 0
        displayedRevision = 0
        parseCount = 0
        timings.removeAll()
        appliedRevisions.removeAll()
    }

    @discardableResult
    func submit(_ source: String) -> Int {
        if let latestSource, latestSource.utf16.elementsEqual(source.utf16) { return requestedRevision }
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
                let start = ProcessInfo.processInfo.systemUptime
                // This upstream initializer is MainActor, including math rendering.
                // Record it separately; do not claim the entire preparation is off-main.
                let prepared = MarkdownContent(parserResult: parsed, theme: self.theme,
                                               locale: Locale(identifier: "zh_Hans_CN"))
                self.timings.append(.init(operation: "main_prepare", milliseconds:
                    (ProcessInfo.processInfo.systemUptime - start) * 1_000, revision: input.revision))
                self.content = prepared
                self.displayedRevision = input.revision
                self.appliedRevisions.append(input.revision)
                self.onApply?(prepared, input.revision)
                self.timings.append(.init(operation: "submitted_to_apply", milliseconds:
                    (ProcessInfo.processInfo.systemUptime - input.submittedAt) * 1_000, revision: input.revision))
            }
            self.working = false
        }
        return requestedRevision
    }
}
