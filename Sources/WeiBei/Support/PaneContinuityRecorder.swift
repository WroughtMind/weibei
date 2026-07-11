#if DEBUG
import AppKit
import Foundation

struct PaneContinuityRoleSample: Codable {
    let role: String
    let hostID: String
    let parentID: String
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
    let containerBounds: CGRect
    let roles: [PaneContinuityRoleSample]
}

@MainActor
final class PaneContinuityRecorder {
    private let directory: URL
    private let recorderID = UUID().uuidString
    private var transitionIndex = 0

    static func configuredFromEnvironment() -> PaneContinuityRecorder? {
        let path = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_PANE_TRACE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        return PaneContinuityRecorder(directory: URL(fileURLWithPath: path, isDirectory: true))
    }

    private init(directory: URL) {
        self.directory = directory
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
}
#endif
