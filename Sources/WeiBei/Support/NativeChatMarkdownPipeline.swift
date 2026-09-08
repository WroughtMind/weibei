import Foundation
import WeiBeiCore

/// One worker and one replaceable pending snapshot. A completed result is published
/// before draining pending input, so continuous streaming cannot starve display.
@MainActor
final class NativeChatMarkdownPipeline {
    struct Snapshot: Equatable, Sendable {
        var markdown: String
        var messageID: UUID?
        var toggledCallouts: Set<Int> = []
        var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
        var plainText = false

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.markdown.utf16.elementsEqual(rhs.markdown.utf16) && lhs.messageID == rhs.messageID
                && lhs.toggledCallouts == rhs.toggledCallouts && lhs.interfaceLanguage == rhs.interfaceLanguage && lhs.plainText == rhs.plainText
        }
    }
    private var latest: Snapshot?
    private var pending: Snapshot?
    private var epoch = 0
    private(set) var working = false
    private var worker: Task<(NativeChatMarkdownDocument, NativeChatMarkdownEdit)?, Never>?
    private var displayed = NativeChatMarkdownDocument()
    var onApply: ((NativeChatMarkdownDocument, NativeChatMarkdownEdit) -> Void)?
    var parse: @Sendable (Snapshot) -> NativeChatMarkdownDocument = {
        $0.plainText ? .init(runs: [.init(text: $0.markdown)])
            : NativeChatMarkdownParser.parse($0.markdown, toggledCallouts: $0.toggledCallouts, interfaceLanguage: $0.interfaceLanguage)
    }

    func submit(_ snapshot: Snapshot) {
        guard latest != snapshot else { return }
        if let latest, latest.messageID != snapshot.messageID || latest.toggledCallouts != snapshot.toggledCallouts || latest.interfaceLanguage != snapshot.interfaceLanguage || latest.plainText != snapshot.plainText || !snapshot.markdown.utf16.starts(with: latest.markdown.utf16) {
            epoch += 1
            worker?.cancel()
        }
        latest = snapshot
        pending = snapshot
        drain()
    }

    func invalidate() { epoch += 1; pending = nil; latest = nil; onApply = nil; worker?.cancel() }

    deinit { worker?.cancel() }

    private func drain() {
        guard !working, let input = pending else { return }
        pending = nil; working = true
        let generation = epoch, baseline = displayed, parse = parse
        let worker = Task.detached(priority: .userInitiated) { () -> (NativeChatMarkdownDocument, NativeChatMarkdownEdit)? in
            guard !Task.isCancelled else { return nil }
            let document = parse(input)
            // An invalidated conversation must not spend time diffing its discarded text.
            guard !Task.isCancelled else { return nil }
            return (document, NativeChatMarkdownEdit.between(baseline, document))
        }
        self.worker = worker
        Task { [weak self] in
            let result = await worker.value
            guard let self else { return }
            self.working = false
            self.worker = nil
            if self.epoch == generation, let result {
                self.displayed = result.0
                self.onApply?(result.0, result.1)
            }
            self.drain()
        }
    }
}
