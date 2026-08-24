import Foundation
import WeiBeiCore

/// workspace.json 快照的滚动备份、坏档隔离与最佳快照恢复。
/// 约束：坏档永远留证据不删；恢复优先最近的好备份；备份旋转失败绝不阻塞保存。
enum WorkspaceSnapshotRecovery {
    static let backupGenerations = 3
    static let quarantinedKeepCount = 3

    static func backupURL(generation: Int, primary: URL) -> URL {
        primary.deletingLastPathComponent()
            .appendingPathComponent("workspace.backup-\(generation).json")
    }

    /// 覆盖主快照前旋转备份链：backup-2→3、backup-1→2、现主文件→1。
    /// 主文件被移走后若本次写入失败，下次启动仍能从 backup-1 恢复。
    static func rotateBackups(primary: URL) {
        let fm = FileManager.default
        let urls = (1...backupGenerations).map { backupURL(generation: $0, primary: primary) }
        for index in stride(from: urls.count - 1, through: 1, by: -1) {
            let source = urls[index - 1]
            let destination = urls[index]
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.removeItem(at: destination)
            try? fm.moveItem(at: source, to: destination)
        }
        if fm.fileExists(atPath: primary.path) {
            try? fm.moveItem(at: primary, to: urls[0])
        }
    }

    /// 坏档改名留存为 workspace.corrupt-<时间戳>.json，只保留最新几份。
    @discardableResult
    static func quarantineCorruptSnapshot(at url: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let quarantined = url.deletingLastPathComponent()
            .appendingPathComponent("workspace.corrupt-\(formatter.string(from: Date())).json")
        do {
            try fm.moveItem(at: url, to: quarantined)
        } catch {
            return nil
        }
        pruneQuarantinedSnapshots(around: url)
        return quarantined
    }

    private static func pruneQuarantinedSnapshots(around primary: URL) {
        let fm = FileManager.default
        guard
            let names = try? fm.contentsOfDirectory(atPath: primary.deletingLastPathComponent().path)
        else { return }
        let sorted = names
            .filter { $0.hasPrefix("workspace.corrupt-") && $0.hasSuffix(".json") }
            .sorted()
        guard sorted.count > quarantinedKeepCount else { return }
        for name in sorted.prefix(sorted.count - quarantinedKeepCount) {
            try? fm.removeItem(
                at: primary.deletingLastPathComponent().appendingPathComponent(name)
            )
        }
    }

    static func isValidSnapshot(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(PersistedWorkspace.self, from: data)) != nil
    }

    enum Notice {
        case restoredFromBackup
        case unrecoverable
    }

    struct RecoveryResult {
        var data: Data?
        var notice: Notice?
    }

    /// 主快照可用 → 直接用；不可用 → 隔离留证，再从 backup-1/2/3 找最近的好档。
    /// 首次启动（主文件不存在且无备份）不算事故，返回无提示的空结果。
    static func bestAvailable(primary: URL) -> RecoveryResult {
        let fm = FileManager.default
        let primaryExists = fm.fileExists(atPath: primary.path)
        if let data = try? Data(contentsOf: primary), isValidSnapshot(data) {
            return RecoveryResult(data: data, notice: nil)
        }
        let hadAnySnapshot = primaryExists
            || (1...backupGenerations).contains {
                fm.fileExists(atPath: backupURL(generation: $0, primary: primary).path)
            }
        guard hadAnySnapshot else {
            return RecoveryResult(data: nil, notice: nil)
        }
        quarantineCorruptSnapshot(at: primary)
        for generation in 1...backupGenerations {
            let url = backupURL(generation: generation, primary: primary)
            if let data = try? Data(contentsOf: url), isValidSnapshot(data) {
                return RecoveryResult(data: data, notice: .restoredFromBackup)
            }
        }
        return RecoveryResult(data: nil, notice: .unrecoverable)
    }
}

extension WorkspaceStore {
    /// 启动加载入口：拿最佳可用快照数据，损坏/恢复事件转为全局横幅提示，
    /// 从备份恢复后立刻排一次保存以重建主快照。
    func restoredSnapshotDataOrNotice(storageURL: URL) -> Data? {
        let recovery = WorkspaceSnapshotRecovery.bestAvailable(primary: storageURL)
        switch recovery.notice {
        case .restoredFromBackup:
            showImportantOperationError(ui(
                "工作区总账本曾损坏，已自动恢复到最近的好备份；原文件已留存为坏档备查。",
                "The workspace ledger was damaged; it has been restored from the latest good backup, and the damaged copy was kept."
            ))
            // Task 推迟一拍：等 load() 把备份状态应用完再重建主快照。
            Task { @MainActor [weak self] in self?.save() }
        case .unrecoverable:
            showImportantOperationError(ui(
                "工作区总账本损坏且无可用备份，原文件已留存为坏档；课程文件夹未受影响，请重新创建或挂载课程空间。",
                "The workspace ledger is damaged with no usable backup; course folders are untouched — please re-create or re-link the course space."
            ))
        case nil:
            break
        }
        return recovery.data
    }
}
