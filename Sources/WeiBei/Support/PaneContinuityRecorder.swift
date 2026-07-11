import AppKit
import Foundation

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

private struct PaneContinuityRoleIdentity: Codable, Equatable {
    let hostID: String
    let parentID: String
    let contentHostID: String?
    let contentParentID: String?
}

private struct PaneContinuitySummary: Codable {
    let recorderID: String
    let samples: Int
    let transitions: Int
    let ownershipFailures: Int
    let blankVisibleFailures: Int
    let identityFailures: Int
    let roleIdentities: [String: PaneContinuityRoleIdentity]
}

@MainActor
final class PaneContinuityRecorder {
    private let directory: URL
    private let writesIndividualSamples: Bool
    private let recorderID = UUID().uuidString
    private var transitionIndex = 0
    private var sampleCount = 0
    private var ownershipFailureCount = 0
    private var blankVisibleFailureCount = 0
    private var identityFailureCount = 0
    private var roleIdentities: [String: PaneContinuityRoleIdentity] = [:]

    static func configuredFromEnvironment() -> PaneContinuityRecorder? {
        let path = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_PANE_TRACE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        let writesIndividualSamples = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_PANE_TRACE_SAMPLES"] == "1"
        return PaneContinuityRecorder(
            directory: URL(fileURLWithPath: path, isDirectory: true),
            writesIndividualSamples: writesIndividualSamples
        )
    }

    private init(directory: URL, writesIndividualSamples: Bool) {
        self.directory = directory
        self.writesIndividualSamples = writesIndividualSamples
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func recordTransition(view: StableDocumentSplitView?, duration: TimeInterval) {
        guard view != nil else { return }
        transitionIndex += 1
        let transition = transitionIndex
        let interval = 1.0 / 60.0
        let frameCount = max(2, Int(ceil(duration / interval)) + 3)

        for frame in 0..<frameCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(frame)) { [weak self, weak view] in
                guard let self, let view else { return }
                let sample = view.continuitySample(
                    recorderID: self.recorderID,
                    transition: transition,
                    frame: frame
                )
                self.updateSummary(with: sample, writesSnapshot: frame == frameCount - 1)
                guard self.writesIndividualSamples else { return }
                guard let data = try? JSONEncoder().encode(sample) else { return }
                let name = String(
                    format: "container-%@-transition-%02d-frame-%02d.json",
                    self.recorderID,
                    transition,
                    frame
                )
                let destination = self.directory.appendingPathComponent(name)
                DispatchQueue.global(qos: .utility).async {
                    try? data.write(to: destination, options: .atomic)
                }
            }
        }
    }

    private func updateSummary(with sample: PaneContinuitySample, writesSnapshot: Bool) {
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
        guard writesSnapshot else { return }
        let summary = PaneContinuitySummary(
            recorderID: recorderID,
            samples: sampleCount,
            transitions: transitionIndex,
            ownershipFailures: ownershipFailureCount,
            blankVisibleFailures: blankVisibleFailureCount,
            identityFailures: identityFailureCount,
            roleIdentities: roleIdentities
        )
        guard let data = try? JSONEncoder().encode(summary) else { return }
        let destination = directory.appendingPathComponent("summary.json")
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: destination, options: .atomic)
        }
    }
}
