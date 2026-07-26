import AppKit
import SwiftUI
import WeiBeiCore

enum RichAnswerVerificationMarker {
    static func update(
        mode: RichAnswerPresentationMode,
        sceneIDs: [String],
        readySceneIDs: Set<String>
    ) {
        guard isVerificationRichAnswerRun else { return }
        guard mode == .rich,
              !sceneIDs.isEmpty,
              readySceneIDs.isSuperset(of: Set(sceneIDs)) else {
            holdPrematureVerificationMarkerIfNeeded()
            return
        }
        writeRendererReadyMarkerIfPossible(mode: mode, sceneIDs: sceneIDs)
    }

    private static var isVerificationRichAnswerRun: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1" else { return false }
        if environment["WEIBEI_VERIFY_RICH_ANSWER_REPLAY"]?.isEmpty == false { return true }
        guard let scenario = environment["WEIBEI_VERIFY_SCENARIO"] else { return false }
        return RichAnswerVerificationFixture.supports(scenario)
    }

    private static func writeRendererReadyMarkerIfPossible(
        mode: RichAnswerPresentationMode,
        sceneIDs: [String]
    ) {
        guard let workspaceDirectory = ProcessInfo.processInfo.environment["WEIBEI_WORKSPACE_DIR"],
              !workspaceDirectory.isEmpty else { return }
        let baseURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
        restoreDeferredVerificationMarkerIfNeeded(in: baseURL)
        let markerURL = baseURL.appendingPathComponent("rich-answer-renderer-ready.txt")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }
        let summary = [
            "ready=renderer",
            "mode=\(mode.rawValue)",
            "scenes=\(sceneIDs.count)",
            "ids=\(sceneIDs.joined(separator: ","))",
        ].joined(separator: "\n") + "\n"
        try? summary.write(
            to: markerURL,
            atomically: true,
            encoding: .utf8
        )
        let stateURL = baseURL.appendingPathComponent("verification-state.txt")
        let previous = (try? String(contentsOf: stateURL, encoding: .utf8)) ?? ""
        try? "\(previous)rich-answer-renderer-ready\n".write(to: stateURL, atomically: true, encoding: .utf8)
    }

    private static func holdPrematureVerificationMarkerIfNeeded() {
        guard let workspaceDirectory = ProcessInfo.processInfo.environment["WEIBEI_WORKSPACE_DIR"],
              !workspaceDirectory.isEmpty else { return }
        let baseURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
        let markerURL = verificationMarkerURL(in: baseURL)
        guard FileManager.default.fileExists(atPath: markerURL.path),
              !FileManager.default.fileExists(atPath: baseURL.appendingPathComponent("rich-answer-renderer-ready.txt").path) else { return }
        let pendingURL = deferredVerificationMarkerURL(in: baseURL)
        if !FileManager.default.fileExists(atPath: pendingURL.path),
           let marker = try? Data(contentsOf: markerURL) {
            try? marker.write(to: pendingURL, options: .atomic)
        }
        try? FileManager.default.removeItem(at: markerURL)
    }

    private static func restoreDeferredVerificationMarkerIfNeeded(in baseURL: URL) {
        let markerURL = verificationMarkerURL(in: baseURL)
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }
        let pendingURL = deferredVerificationMarkerURL(in: baseURL)
        guard let marker = try? Data(contentsOf: pendingURL) else { return }
        try? marker.write(to: markerURL, options: .atomic)
        try? FileManager.default.removeItem(at: pendingURL)
    }

    private static func verificationMarkerURL(in baseURL: URL) -> URL {
        let environment = ProcessInfo.processInfo.environment
        let isReplay = environment["WEIBEI_VERIFY_RICH_ANSWER_REPLAY"]?.isEmpty == false
        return baseURL.appendingPathComponent(isReplay ? "rich-answer-replay-verified.txt" : "rich-answer-verified.txt")
    }

    private static func deferredVerificationMarkerURL(in baseURL: URL) -> URL {
        baseURL.appendingPathComponent("rich-answer-deferred-verified.txt")
    }
}

