import AppKit
import Combine
import Sparkle

struct WeiBeiAvailableUpdate: Equatable {
    let version: String
    let summaryLines: [String]
    let informationOnly: Bool
    let informationURL: URL?

    var helpText: String {
        (["魏碑 \(version)"] + summaryLines.prefix(5)).joined(separator: "\n")
    }

    static func summaryLines(from rawNotes: String?) -> [String] {
        guard var text = rawNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return []
        }
        for marker in ["</li>", "</p>", "<br>", "<br/>", "<br />"] {
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
        return Array(lines.prefix(5))
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
    @Published private(set) var downloadProgress: Double?

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
    private var expectedDownloadLength: UInt64 = 0
    private var receivedDownloadLength: UInt64 = 0

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
        downloadProgress = nil
        if let updateChoiceReply {
            self.updateChoiceReply = nil
            updateChoiceReply(.install)
        } else {
            retryInstallWhenFound = true
            updater.checkForUpdates()
        }
    }

    private func resetDownloadProgress() {
        expectedDownloadLength = 0
        receivedDownloadLength = 0
        downloadProgress = nil
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
            summaryLines: Self.summaryLines(for: appcastItem),
            informationOnly: appcastItem.isInformationOnlyUpdate,
            informationURL: appcastItem.infoURL
        )
        availableUpdate = update
        resetDownloadProgress()

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
        let lines = WeiBeiAvailableUpdate.summaryLines(from: text)
        guard !lines.isEmpty else { return }
        availableUpdate = WeiBeiAvailableUpdate(
            version: update.version,
            summaryLines: lines,
            informationOnly: update.informationOnly,
            informationURL: update.informationURL
        )
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error) async {
        availableUpdate = nil
        retryInstallWhenFound = false
        updateChoiceReply = nil
        resetDownloadProgress()
        status = .upToDate
    }

    func showUpdaterError(_ error: Error) async {
        retryInstallWhenFound = false
        updateChoiceReply = nil
        resetDownloadProgress()
        status = .failed(error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        status = .downloading
        resetDownloadProgress()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedDownloadLength = expectedContentLength
        receivedDownloadLength = 0
        downloadProgress = expectedContentLength > 0 ? 0 : nil
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedDownloadLength += length
        guard expectedDownloadLength > 0 else { return }
        downloadProgress = min(1, Double(receivedDownloadLength) / Double(expectedDownloadLength))
    }

    func showDownloadDidStartExtractingUpdate() {
        status = .extracting
        downloadProgress = nil
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        status = .extracting
        downloadProgress = min(1, max(0, progress))
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
        resetDownloadProgress()
        if case .failed = status {
            return
        }
        status = availableUpdate == nil ? .idle : .available
    }

    private static func summaryLines(for item: SUAppcastItem) -> [String] {
        let lines = WeiBeiAvailableUpdate.summaryLines(from: item.itemDescription)
        if !lines.isEmpty { return lines }
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           title != item.displayVersionString {
            return [title]
        }
        return []
    }
}
