import Foundation
import WeiBeiCore

/// 一个场景对应的日志、截图与隔离工作区路径。
public struct VerificationScenarioArtifacts: Equatable, Sendable {
    public let directoryURL: URL
    public let workspaceURL: URL
    public let stdoutURL: URL
    public let stderrURL: URL
    public let captureURL: URL
    public let windowReadyURL: URL
    public let completionURL: URL
    public let evidenceDirectoryURL: URL
    public let validationURL: URL

    /// 创建场景 artifacts 路径集合。
    public init(
        directoryURL: URL,
        workspaceURL: URL,
        stdoutURL: URL,
        stderrURL: URL,
        captureURL: URL,
        windowReadyURL: URL,
        completionURL: URL,
        evidenceDirectoryURL: URL,
        validationURL: URL
    ) {
        self.directoryURL = directoryURL
        self.workspaceURL = workspaceURL
        self.stdoutURL = stdoutURL
        self.stderrURL = stderrURL
        self.captureURL = captureURL
        self.windowReadyURL = windowReadyURL
        self.completionURL = completionURL
        self.evidenceDirectoryURL = evidenceDirectoryURL
        self.validationURL = validationURL
    }
}

/// 创建并维护一轮验收的持久 artifacts。
public final class VerificationArtifactStore {
    public let rootURL: URL
    public let runURL: URL
    private let fileManager: FileManager

    /// 在指定根目录创建唯一运行目录；默认根目录由调用方从仓库布局传入。
    public init(
        rootURL: URL,
        runID: String = VerificationArtifactStore.makeRunID(),
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        guard let runComponent = Self.safeComponent(runID) else {
            throw VerificationError(
                code: "artifact_run_id_invalid",
                message: "Verification artifact run ID must resolve to one non-empty path component."
            )
        }
        self.runURL = self.rootURL.appendingPathComponent(runComponent, isDirectory: true)
        do {
            try fileManager.createDirectory(at: self.runURL, withIntermediateDirectories: true)
        } catch {
            throw VerificationError(code: "artifact_creation_failed", message: error.localizedDescription)
        }
    }

    /// 为一个场景创建独立目录和工作区。
    public func prepareScenario(_ scenario: VerificationScenario) throws -> VerificationScenarioArtifacts {
        let directory = runURL.appendingPathComponent(scenario.id.rawValue, isDirectory: true)
        let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
        do {
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        } catch {
            throw VerificationError(code: "artifact_creation_failed", message: error.localizedDescription)
        }
        return VerificationScenarioArtifacts(
            directoryURL: directory,
            workspaceURL: workspace,
            stdoutURL: directory.appendingPathComponent("app-stdout.log"),
            stderrURL: directory.appendingPathComponent("app-stderr.log"),
            captureURL: directory.appendingPathComponent("window.png"),
            windowReadyURL: directory.appendingPathComponent("window-ready.json"),
            completionURL: directory.appendingPathComponent("scenario-complete.json"),
            evidenceDirectoryURL: directory.appendingPathComponent("evidence", isDirectory: true),
            validationURL: directory.appendingPathComponent("validation.json")
        )
    }

    /// 成功时只保留协议与声明证据；失败时完整保留现场。
    public func finishScenario(
        _ artifacts: VerificationScenarioArtifacts,
        succeeded: Bool,
        retainedEvidence: [String] = []
    ) throws {
        guard succeeded else {
            return
        }
        do {
            do {
                try VerificationContractIO.validateEvidencePaths(retainedEvidence)
            } catch {
                throw VerificationError(code: "scenario_evidence_invalid", message: error.localizedDescription)
            }
            try fileManager.createDirectory(
                at: artifacts.evidenceDirectoryURL,
                withIntermediateDirectories: true
            )
            for relativePath in retainedEvidence {
                let source = artifacts.directoryURL.appendingPathComponent(relativePath)
                guard fileManager.fileExists(atPath: source.path) else {
                    throw VerificationError(
                        code: "scenario_evidence_missing",
                        message: "Declared evidence is missing: \(relativePath)"
                    )
                }
                let destination = artifacts.evidenceDirectoryURL.appendingPathComponent(relativePath)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            }
            for disposable in [
                artifacts.workspaceURL,
                artifacts.stdoutURL,
                artifacts.stderrURL,
                artifacts.captureURL,
            ] where fileManager.fileExists(atPath: disposable.path) {
                try fileManager.removeItem(at: disposable)
            }
        } catch {
            if let verificationError = error as? VerificationError {
                throw verificationError
            }
            throw VerificationError(code: "artifact_cleanup_failed", message: error.localizedDescription)
        }
    }

    /// 将报告写入运行目录，并在完整运行结束后更新 `latest` 符号链接。
    public func completeRun(reportData: Data) throws {
        let reportURL = runURL.appendingPathComponent("report.json")
        do {
            try reportData.write(to: reportURL, options: .atomic)
            let latestURL = rootURL.appendingPathComponent("latest")
            let temporaryLinkURL = rootURL.appendingPathComponent(".latest-\(UUID().uuidString)")
            try? fileManager.removeItem(at: temporaryLinkURL)
            try fileManager.createSymbolicLink(
                atPath: temporaryLinkURL.path,
                withDestinationPath: runURL.lastPathComponent
            )
            if fileManager.fileExists(atPath: latestURL.path) || (try? fileManager.destinationOfSymbolicLink(atPath: latestURL.path)) != nil {
                try fileManager.removeItem(at: latestURL)
            }
            try fileManager.moveItem(at: temporaryLinkURL, to: latestURL)
        } catch {
            throw VerificationError(code: "artifact_finalization_failed", message: error.localizedDescription)
        }
    }

    /// 创建时间可读且避免冲突的运行标识。
    public static func makeRunID(date: Date = Date(), uuid: UUID = UUID()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "\(formatter.string(from: date).replacingOccurrences(of: ":", with: "-"))-\(uuid.uuidString.lowercased())"
    }

    /// Sanitizes a caller-provided run identifier into one path component.
    private static func safeComponent(_ value: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let component = String(sanitized)
        return component.isEmpty || component == "." || component == ".." ? nil : component
    }
}
