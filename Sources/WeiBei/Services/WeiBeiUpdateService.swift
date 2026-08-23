import AppKit
import Combine
import Sparkle

struct WeiBeiAvailableUpdate: Equatable {
    let version: String
    let releaseNotesLines: [String]
    let informationOnly: Bool
    let informationURL: URL?

    var summaryLines: [String] {
        Self.summaryLines(from: releaseNotesLines)
    }

    var helpText: String {
        (["魏碑 \(version)"] + summaryLines).joined(separator: "\n")
    }

    static func summaryLines(from rawNotes: String?) -> [String] {
        summaryLines(from: releaseNotesLines(from: rawNotes))
    }

    static func releaseNotesLines(from rawNotes: String?) -> [String] {
        guard var text = rawNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return []
        }
        for marker in ["</li>", "</p>", "</h1>", "</h2>", "</h3>", "<br>", "<br/>", "<br />"] {
            text = text.replacingOccurrences(of: marker, with: "\n", options: .caseInsensitive)
        }
        text = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        let lines = text
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
            }
            .filter { !$0.isEmpty }
        return lines
    }

    private static func summaryLines(from lines: [String]) -> [String] {
        let highlights = priorityHighlights(in: lines)
        let excludedIndexes = Set(highlights.flatMap { [$0.headingIndex, $0.detailIndex] })
        let fillers = lines.enumerated()
            .filter { !excludedIndexes.contains($0.offset) }
            .prefix(max(0, 5 - highlights.count))
            .map { (index: $0.offset, text: $0.element) }
        return (fillers + highlights.map { (index: $0.detailIndex, text: $0.text) })
            .sorted { $0.index < $1.index }
            .map { $0.text }
    }

    private static func priorityHighlights(
        in lines: [String]
    ) -> [(headingIndex: Int, detailIndex: Int, text: String)] {
        let titles: Set<String> = [
            "破坏性变化", "破坏性变更", "迁移", "迁移说明", "已知问题",
            "Breaking Changes", "Migration", "Known Issues",
        ]
        let headings = lines.indices.compactMap { index -> (index: Int, title: String)? in
            let title = lines[index]
                .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                .trimmingCharacters(in: CharacterSet(charactersIn: "：:"))
            return titles.contains(title) ? (index, title) : nil
        }
        return headings.enumerated().flatMap { offset, heading in
            let endIndex = offset + 1 < headings.count ? headings[offset + 1].index : lines.endIndex
            return ((heading.index + 1)..<endIndex).map { detailIndex in
                (heading.index, detailIndex, "\(heading.title)：\(lines[detailIndex])")
            }
        }
    }
}

@MainActor
final class WeiBeiUpdateService: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case available
        case downloading
        case extracting
        case installing
        case upToDate
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var availableUpdate: WeiBeiAvailableUpdate?

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .extracting, .installing:
            true
        default:
            false
        }
    }

    var showsToolbarControl: Bool {
        guard availableUpdate != nil else { return false }
        switch status {
        case .available, .downloading, .extracting, .installing, .failed:
            return true
        case .idle, .checking, .upToDate:
            return false
        }
    }

    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: self,
        delegate: nil
    )
    private var updateChoiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var retryInstallWhenFound = false

    override init() {
        super.init()
        do {
            try updater.start()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        status = .checking
        updater.checkForUpdates()
    }

    func installAvailableUpdate() {
        guard let update = availableUpdate, !isBusy else { return }
        if update.informationOnly {
            if let informationURL = update.informationURL {
                NSWorkspace.shared.open(informationURL)
            }
            return
        }

        status = .downloading
        if let updateChoiceReply {
            self.updateChoiceReply = nil
            updateChoiceReply(.install)
        } else {
            retryInstallWhenFound = true
            updater.checkForUpdates()
        }
    }

}

extension WeiBeiUpdateService: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        )
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        if availableUpdate == nil {
            status = .checking
        }
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let update = WeiBeiAvailableUpdate(
            version: appcastItem.displayVersionString,
            releaseNotesLines: Self.releaseNotesLines(for: appcastItem),
            informationOnly: appcastItem.isInformationOnlyUpdate,
            informationURL: appcastItem.infoURL
        )
        availableUpdate = update

        if update.informationOnly {
            retryInstallWhenFound = false
            status = .available
            reply(.dismiss)
            return
        }

        if retryInstallWhenFound || state.stage == .installing {
            retryInstallWhenFound = false
            status = state.stage == .installing ? .installing : .downloading
            reply(.install)
        } else {
            updateChoiceReply = reply
            status = .available
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard let text = String(data: downloadData.data, encoding: .utf8),
              let update = availableUpdate else { return }
        let lines = WeiBeiAvailableUpdate.releaseNotesLines(from: text)
        guard !lines.isEmpty else { return }
        availableUpdate = WeiBeiAvailableUpdate(
            version: update.version,
            releaseNotesLines: lines,
            informationOnly: update.informationOnly,
            informationURL: update.informationURL
        )
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error) async {
        availableUpdate = nil
        retryInstallWhenFound = false
        updateChoiceReply = nil
        status = .upToDate
    }

    func showUpdaterError(_ error: Error) async {
        retryInstallWhenFound = false
        updateChoiceReply = nil
        status = .failed(error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        status = .downloading
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        status = .extracting
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        status = .extracting
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        status = .installing
        return .install
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        status = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        availableUpdate = nil
        status = .idle
    }

    func dismissUpdateInstallation() {
        updateChoiceReply = nil
        retryInstallWhenFound = false
        if case .failed = status {
            return
        }
        status = availableUpdate == nil ? .idle : .available
    }

    private static func releaseNotesLines(for item: SUAppcastItem) -> [String] {
        let lines = WeiBeiAvailableUpdate.releaseNotesLines(from: item.itemDescription)
        if !lines.isEmpty { return lines }
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           title != item.displayVersionString {
            return [title]
        }
        return []
    }
}
