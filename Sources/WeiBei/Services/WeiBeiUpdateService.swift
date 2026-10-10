import Combine
import Foundation
#if !targetEnvironment(macCatalyst)
import AppKit
import Sparkle
#endif
#if canImport(WeiBeiCore)
import WeiBeiCore
#endif

struct WeiBeiAvailableUpdate: Equatable {
    let version: String
    let releaseNotesLines: [String]
    let informationOnly: Bool
    let informationURL: URL?
    var publishedDate: Date? = nil

    static func isHeading(_ line: String) -> Bool {
        line.hasPrefix("#") || [
            "新增", "改进", "修复", "本次更新", "破坏性变化", "破坏性变更", "迁移", "迁移说明", "已知问题",
            "New", "Improvements", "Fixed", "Fixes", "Breaking Changes", "Migration", "Known Issues",
        ].contains(line.trimmingCharacters(in: CharacterSet(charactersIn: "：:")))
    }

    static func displayText(_ line: String) -> String {
        line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    }

    static func releaseNotesLines(from rawNotes: String?) -> [String] {
        guard var text = rawNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return [] }
        text = text.replacingOccurrences(of: "<h[1-6][^>]*>", with: "\n## ", options: [.regularExpression, .caseInsensitive])
        for marker in ["</li>", "</p>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>", "<br>", "<br/>", "<br />"] {
            text = text.replacingOccurrences(of: marker, with: "\n", options: .caseInsensitive)
        }
        text = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*• ")) }
            .filter { !$0.isEmpty }
    }
}

@MainActor
final class WeiBeiUpdateService: NSObject, ObservableObject {
    enum Status: String, Equatable {
        case idle, checking, available, downloading, extracting, ready, saving, installing, upToDate, failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var availableUpdate: WeiBeiAvailableUpdate?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var errorDescription: String?
    /// The application owns editor snapshots and workspace persistence.
    static let pendingInstallationBuildKey = "WeiBeiPendingUpdateBuild"
    static let pendingInstallationVersionKey = "WeiBeiPendingUpdateVersion"
    var prepareForInstallation: (@MainActor () async -> Bool)?

    var isBusy: Bool {
        [.checking, .downloading, .extracting, .saving, .installing].contains(status)
    }

    var showsToolbarControl: Bool {
        availableUpdate != nil && ![.idle, .checking, .upToDate].contains(status)
    }

    func actionLabel(english: Bool) -> String {
        switch status {
        case .ready: return english ? "Install and Relaunch" : "安装并重启"
        case .downloading: return english ? "Downloading" : "下载中"
        case .extracting: return english ? "Preparing" : "准备中"
        case .saving: return english ? "Saving" : "正在保存"
        case .installing: return english ? "Installing" : "安装中"
        case .failed: return english ? "Retry" : "重试"
        default:
            if availableUpdate?.informationOnly == true { return english ? "View Update" : "查看更新" }
            return english ? "Download Update" : "下载更新"
        }
    }

#if targetEnvironment(macCatalyst)
    override init() {
        super.init()
        CatalystDesktopWindow.shared.observeUpdates { [weak self] snapshot in
            guard let self else { return }
            self.availableUpdate = (snapshot["version"] as? String).map {
                WeiBeiAvailableUpdate(version: $0,
                    releaseNotesLines: snapshot["notes"] as? [String] ?? [],
                    informationOnly: snapshot["informationOnly"] as? Bool ?? false,
                    informationURL: snapshot["informationURL"] as? URL,
                    publishedDate: snapshot["date"] as? Date)
            }
            self.downloadProgress = snapshot["progress"] as? Double
            self.errorDescription = snapshot["error"] as? String
            self.status = Status(rawValue: snapshot["status"] as? String ?? "") ?? .failed
        }
    }

    func checkForUpdates() { CatalystDesktopWindow.shared.checkForUpdates() }
    func installAvailableUpdate() {
        guard !isBusy else { return }
        CatalystDesktopWindow.shared.installAvailableUpdate { [weak self] completion in
            Task { @MainActor in
                completion(await self?.prepareForInstallation?() ?? false)
            }
        }
    }
#else
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
    private var updateChoiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var readyToInstall = false
    private var retryInstallWhenFound = false
    private var targetBuild: String?
    private var receivedBytes: UInt64 = 0
    private var expectedBytes: UInt64 = 0

    override convenience init() { self.init(startsUpdater: true) }

    init(startsUpdater: Bool, availableUpdate: WeiBeiAvailableUpdate? = nil) {
        super.init()
        self.availableUpdate = availableUpdate
        guard startsUpdater else { return }
        do { try updater.start() }
        catch { recordFailure(error) }
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        // A second check must not discard an already prepared installation.
        guard !readyToInstall else { return }
        errorDescription = nil
        status = .checking
        updater.checkForUpdates()
    }

    func installAvailableUpdate() {
        guard let update = availableUpdate, !isBusy else { return }
        if update.informationOnly {
            if let url = update.informationURL { NSWorkspace.shared.open(url) }
            return
        }
        errorDescription = nil
        if readyToInstall {
            status = .saving
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard await self.prepareForInstallation?() == true else {
                    self.errorDescription = "笔记与工作区尚未安全保存，请重试。"
                    self.status = .failed
                    return
                }
                guard self.readyToInstall, let reply = self.updateChoiceReply else { return }
                self.readyToInstall = false
                self.updateChoiceReply = nil
                self.status = .installing
                if let targetBuild = self.targetBuild {
                    UserDefaults.standard.set(targetBuild, forKey: Self.pendingInstallationBuildKey)
                    UserDefaults.standard.set(update.version, forKey: Self.pendingInstallationVersionKey)
                }
                reply(.install)
            }
            return
        }
        resetProgress()
        status = .downloading
        if let reply = updateChoiceReply {
            updateChoiceReply = nil
            reply(.install)
        } else {
            retryInstallWhenFound = true
            updater.checkForUpdates()
        }
    }

    private func resetProgress() {
        receivedBytes = 0
        expectedBytes = 0
        downloadProgress = nil
    }

    private func refreshProgress() {
        // Content length can be missing or inaccurate. Never invent a percentage.
        downloadProgress = expectedBytes > 0 && receivedBytes <= expectedBytes
            ? Double(receivedBytes) / Double(expectedBytes) : nil
    }

    private func recordFailure(_ error: Error) {
        retryInstallWhenFound = false
        if readyToInstall { updateChoiceReply?(.dismiss) }
        updateChoiceReply = nil
        readyToInstall = false
        errorDescription = error.localizedDescription
        WeiBeiLog.workspace.error("code=updater_failed underlying=\(WeiBeiLog.code(error), privacy: .public)")
        status = .failed
    }
#endif
}

#if !targetEnvironment(macCatalyst)
extension WeiBeiUpdateService: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: true, automaticUpdateDownloading: false, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        if availableUpdate == nil { status = .checking }
    }

    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        targetBuild = item.versionString
        availableUpdate = WeiBeiAvailableUpdate(version: item.displayVersionString,
            releaseNotesLines: Self.releaseNotesLines(for: item), informationOnly: item.isInformationOnlyUpdate,
            informationURL: item.infoURL, publishedDate: item.date)
        errorDescription = nil
        if item.isInformationOnlyUpdate {
            retryInstallWhenFound = false
            status = .available
            reply(.dismiss)
        } else if state.stage == .installing {
            // A resumed installation also needs an explicit click and a save receipt.
            retryInstallWhenFound = false
            readyToInstall = true
            updateChoiceReply = reply
            status = .ready
        } else if retryInstallWhenFound {
            retryInstallWhenFound = false
            status = .downloading
            reply(.install)
        } else {
            updateChoiceReply = reply
            status = .available
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard let text = String(data: downloadData.data, encoding: .utf8), var update = availableUpdate else { return }
        let lines = WeiBeiAvailableUpdate.releaseNotesLines(from: text)
        guard !lines.isEmpty else { return }
        update = WeiBeiAvailableUpdate(version: update.version, releaseNotesLines: lines,
            informationOnly: update.informationOnly, informationURL: update.informationURL, publishedDate: update.publishedDate)
        availableUpdate = update
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        errorDescription = error.localizedDescription
    }

    func showUpdateNotFoundWithError(_ error: Error) async {
        let error = error as NSError
        guard let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value,
              error.domain == SUSparkleErrorDomain, error.code == SUError.noUpdateError.rawValue,
              reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue
                || reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue else {
            recordFailure(error)
            return
        }
        availableUpdate = nil
        retryInstallWhenFound = false
        updateChoiceReply = nil
        status = .upToDate
    }

    func showUpdaterError(_ error: Error) async { recordFailure(error) }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        resetProgress()
        status = .downloading
    }
    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) {
        expectedBytes = length
        refreshProgress()
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        refreshProgress()
    }
    func showDownloadDidStartExtractingUpdate() { status = .extracting }
    func showExtractionReceivedProgress(_ progress: Double) { status = .extracting }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        await withCheckedContinuation { continuation in
            readyToInstall = true
            updateChoiceReply = { continuation.resume(returning: $0) }
            status = .ready
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                             retryTerminatingApplication: @escaping () -> Void) { status = .installing }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        availableUpdate = nil
        status = .idle
    }

    func dismissUpdateInstallation() {
        if readyToInstall { updateChoiceReply?(.dismiss) }
        updateChoiceReply = nil
        readyToInstall = false
        retryInstallWhenFound = false
        if status != .failed { status = availableUpdate == nil ? .idle : .available }
    }

    private static func releaseNotesLines(for item: SUAppcastItem) -> [String] {
        WeiBeiAvailableUpdate.releaseNotesLines(from: item.itemDescription)
    }
}
#endif
