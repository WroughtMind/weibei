import AppKit
import Foundation
import WeiBeiCore

struct PaneContinuityRoleSample: Codable {
    let role: String
    let hostID: String
    let parentID: String
    let contentHostID: String?
    let contentParentID: String?
    let contentAttached: Bool
    let slotHasVisibleArea: Bool
    let visibleContentReady: Bool
    let hidden: Bool
    let modelFrame: CGRect
    let presentationFrame: CGRect
}

struct PaneContinuitySample: Codable {
    let recorderID: String
    let transition: Int
    let frame: Int
    let timestamp: TimeInterval
    let stableOwnership: Bool
    let noBlankVisibleSlots: Bool
    let containerBounds: CGRect
    let roles: [PaneContinuityRoleSample]
}

/// 采集 pane 连续性证据，并在 finish 屏障后只发布一次最终 summary。
@MainActor
final class PaneContinuityRecorder {
    private static weak var activeRecorder: PaneContinuityRecorder?

    private let directory: URL
    private let writesIndividualSamples: Bool
    private let recorderID = UUID().uuidString
    private var transitionIndex = 0
    private var sampleCount = 0
    private var pendingSampleCount = 0
    private var ownershipFailureCount = 0
    private var blankVisibleFailureCount = 0
    private var identityFailureCount = 0
    private var roleIdentities: [String: PaneContinuityRoleIdentity] = [:]
    private var writeTasks: [Task<Void, Error>] = []
    private var setupError: Error?
    private var didFinish = false

    /// 从 Runner 显式传入的 trace 目录创建 recorder。
    static func configuredFromEnvironment() -> PaneContinuityRecorder? {
        let path = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_PANE_TRACE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        let recorder = PaneContinuityRecorder(
            directory: URL(fileURLWithPath: path, isDirectory: true),
            writesIndividualSamples: ProcessInfo.processInfo.environment["WEIBEI_VERIFY_PANE_TRACE_SAMPLES"] == "1"
        )
        activeRecorder = recorder
        return recorder
    }

    /// 等待当前场景的全部采样和串行文件写入，再发布最终 summary。
    static func finishConfigured() async throws {
        guard let recorder = activeRecorder else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await recorder.finish()
    }

    init(directory: URL, writesIndividualSamples: Bool) {
        self.directory = directory
        self.writesIndividualSamples = writesIndividualSamples
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            setupError = error
        }
    }

    /// 在调度延迟采样前登记全部未完成任务。
    func recordTransition(view: StableDocumentSplitView?, duration: TimeInterval) {
        guard let view, !didFinish else { return }
        transitionIndex += 1
        let transition = transitionIndex
        let interval = 1.0 / 60.0
        let frameCount = max(2, Int(ceil(duration / interval)) + 3)
        pendingSampleCount += frameCount

        for frame in 0..<frameCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(frame)) { [weak self, weak view] in
                guard let self else { return }
                defer { self.pendingSampleCount -= 1 }
                guard let view else {
                    self.setupError = CocoaError(.validationMissingMandatoryProperty)
                    return
                }
                let sample = view.continuitySample(
                    recorderID: self.recorderID,
                    transition: transition,
                    frame: frame
                )
                self.updateSummary(with: sample)
                guard self.writesIndividualSamples else { return }
                do {
                    let data = try JSONEncoder().encode(sample)
                    let name = String(
                        format: "container-%@-transition-%02d-frame-%02d.json",
                        self.recorderID,
                        transition,
                        frame
                    )
                    let destination = self.directory.appendingPathComponent(name)
                    let previousTask = self.writeTasks.last
                    self.writeTasks.append(Task.detached {
                        _ = try await previousTask?.value
                        try data.write(to: destination, options: .atomic)
                    })
                } catch {
                    self.setupError = error
                }
            }
        }
    }

    /// 等待所有异步阶段后原子发布唯一 summary。
    func finish() async throws {
        guard !didFinish else { return }
        while pendingSampleCount > 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        for task in writeTasks {
            try await task.value
        }
        if let setupError {
            throw setupError
        }
        let summary = PaneContinuitySummary(
            recorderID: recorderID,
            samples: sampleCount,
            transitions: transitionIndex,
            ownershipFailures: ownershipFailureCount,
            blankVisibleFailures: blankVisibleFailureCount,
            identityFailures: identityFailureCount,
            roleIdentities: roleIdentities
        )
        try VerificationContractIO.publish(
            summary,
            to: directory.appendingPathComponent("summary.json"),
            within: directory
        )
        didFinish = true
    }

    /// 在 MainActor 上更新 ownership、blank slot 与 role identity 统计。
    private func updateSummary(with sample: PaneContinuitySample) {
        sampleCount += 1
        if !sample.stableOwnership {
            ownershipFailureCount += 1
        }
        if !sample.noBlankVisibleSlots {
            blankVisibleFailureCount += 1
        }
        for role in sample.roles {
            let identity = PaneContinuityRoleIdentity(
                hostID: role.hostID,
                parentID: role.parentID,
                contentHostID: role.contentHostID,
                contentParentID: role.contentParentID
            )
            if let baseline = roleIdentities[role.role] {
                if baseline != identity {
                    identityFailureCount += 1
                }
            } else {
                roleIdentities[role.role] = identity
            }
        }
    }
}
