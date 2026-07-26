import AppKit
import Foundation

/**
 * 读取验证环境和捕获通道，协调窗口尺寸、稳定性等待、截图及证据回执。
 */
@MainActor
final class VerificationCaptureCoordinator {
    static let shared = VerificationCaptureCoordinator()

    private var scheduledCapturePaths: Set<String> = []
    private var scheduledChannelIDs: Set<String> = []
    private var processedRequestIDs: Set<String> = []
    private let snapshotService = WindowSnapshotService()

    private init() {}

    /**
     * 根据验证环境配置窗口，并按需启动单次捕获与请求通道轮询。
     */
    func configure(_ window: NSWindow) {
        applyVerificationWindowSize(to: window)
        captureVerificationWindowIfRequested(window)
        listenForVerificationCaptureRequestsIfRequested(window)
    }

    /**
     * 将验证窗口调整为环境指定的稳定尺寸。
     */
    private func applyVerificationWindowSize(to window: NSWindow) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1",
              let rawSize = environment["WEIBEI_VERIFY_WINDOW_SIZE"] else { return }
        let parts = rawSize.lowercased().split(separator: "x", maxSplits: 1)
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width >= 600,
              height >= 400 else { return }

        let target = NSSize(width: width, height: height)
        let current = window.contentLayoutRect.size
        guard abs(current.width - target.width) > 1 || abs(current.height - target.height) > 1 else { return }
        window.setContentSize(target)
        window.center()
    }

    /**
     * 处理旧式环境变量驱动的单次窗口截图。
     */
    private func captureVerificationWindowIfRequested(_ window: NSWindow) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1",
              let capturePath = environment["WEIBEI_VERIFY_CAPTURE_PATH"],
              !capturePath.isEmpty,
              scheduledCapturePaths.insert(capturePath).inserted else { return }

        let scenario = environment["WEIBEI_VERIFY_SCENARIO"] ?? ""
        if [
            "pi-learning-flow",
            "pi-course-memory-flow",
            "pane-toggle-continuity-flow",
            "reader-scroll-persistence-flow",
            "course-workspace-overview-flow",
            "course-workspace-workflow-flow",
        ].contains(scenario),
           let workspaceDirectory = environment["WEIBEI_WORKSPACE_DIR"] {
            let stateURL = URL(fileURLWithPath: workspaceDirectory).appendingPathComponent("verification-state.txt")
            waitForVerificationCompletion(
                in: window,
                capturePath: capturePath,
                stateURL: stateURL,
                remainingAttempts: scenario == "pane-toggle-continuity-flow" ? 1_800 : 600
            )
            return
        }

        snapshotService.waitForSingleCaptureReadiness(in: window, remainingAttempts: 50) { [weak self] result in
            guard let self else { return }
            switch result {
            case .ready:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.snapshotService.capture(window, to: capturePath)
                }
            case .failed(let failureReason):
                fputs("WeiBei verification legacy single capture failed: \(failureReason)\n", stderr)
            }
        }
    }

    /**
     * 验证并启动基于文件通道的连续捕获请求。
     */
    private func listenForVerificationCaptureRequestsIfRequested(_ window: NSWindow) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1",
              let rawChannelPath = environment["WEIBEI_VERIFY_CAPTURE_REQUEST_DIR"],
              !rawChannelPath.isEmpty,
              let rawOutputPath = environment["WEIBEI_VERIFY_CAPTURE_OUTPUT_DIR"],
              !rawOutputPath.isEmpty else { return }

        let channelURL = URL(fileURLWithPath: rawChannelPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let outputURL = URL(fileURLWithPath: rawOutputPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let channelID = "\(channelURL.path)#\(ObjectIdentifier(window).hashValue)"
        guard scheduledChannelIDs.insert(channelID).inserted else { return }
        guard isSafeVerificationOutputRoot(outputURL) else {
            fputs("WeiBei verification capture output root is unsafe: \(outputURL.path)\n", stderr)
            return
        }
        guard isCaptureURL(channelURL, inside: outputURL) else {
            fputs("WeiBei verification capture channel must stay inside output root: \(channelURL.path)\n", stderr)
            return
        }

        try? FileManager.default.createDirectory(at: channelURL, withIntermediateDirectories: true)
        scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
    }

    /**
     * 安排下一次捕获请求轮询。
     */
    private func scheduleVerificationCapturePoll(
        in window: NSWindow,
        channelURL: URL,
        outputURL: URL
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
            guard let self, let window else { return }
            self.pollVerificationCaptureRequests(in: window, channelURL: channelURL, outputURL: outputURL)
        }
    }

    /**
     * 读取并处理捕获通道中的最新请求。
     */
    private func pollVerificationCaptureRequests(
        in window: NSWindow,
        channelURL: URL,
        outputURL: URL
    ) {
        let requestURL = channelURL.appendingPathComponent("request.json")
        guard let data = try? Data(contentsOf: requestURL),
              let request = try? JSONDecoder().decode(VerificationCaptureRequest.self, from: data),
              !request.id.isEmpty else {
            scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
            return
        }

        let requestKey = "\(channelURL.path)::\(request.id)"
        guard processedRequestIDs.insert(requestKey).inserted else {
            scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
            return
        }

        let captureURL = URL(fileURLWithPath: request.capturePath).standardizedFileURL.resolvingSymlinksInPath()
        guard isCaptureURL(captureURL, inside: outputURL), captureURL.pathExtension.lowercased() == "png" else {
            writeVerificationCaptureAcknowledgement(
                request: request,
                status: "failed",
                failureReason: "capture path must be a PNG inside the configured output directory",
                channelURL: channelURL
            )
            scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
            return
        }

        let verificationStage = request.stage?.lowercased()
        if verificationStage == "single" {
            snapshotService.waitForSingleCaptureReadiness(in: window, remainingAttempts: 50) { [weak self] result in
                guard let self else { return }
                switch result {
                case .ready:
                    self.completeVerificationCaptureRequest(
                        request: request,
                        in: window,
                        captureURL: captureURL,
                        channelURL: channelURL,
                        outputURL: outputURL,
                        delay: 0.25
                    )
                case .failed(let failureReason):
                    self.writeVerificationCaptureAcknowledgement(
                        request: request,
                        status: "failed",
                        failureReason: failureReason,
                        channelURL: channelURL
                    )
                    self.scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
                }
            }
            return
        }

        let stageDelay: TimeInterval
        if let verificationStage, ["overview", "before", "after"].contains(verificationStage) {
            NotificationCenter.default.post(
                name: .weiBeiRichAnswerVerificationStage,
                object: nil,
                userInfo: ["stage": verificationStage]
            )
            stageDelay = verificationStage == "after" ? 1.1 : 0.8
        } else {
            stageDelay = 0
        }
        completeVerificationCaptureRequest(
            request: request,
            in: window,
            captureURL: captureURL,
            channelURL: channelURL,
            outputURL: outputURL,
            delay: stageDelay
        )
    }

    /**
     * 延迟捕获窗口并写入请求回执。
     */
    private func completeVerificationCaptureRequest(
        request: VerificationCaptureRequest,
        in window: NSWindow,
        captureURL: URL,
        channelURL: URL,
        outputURL: URL,
        delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.snapshotService.capture(window, to: captureURL.path) { captureResult, failureReason in
                self.writeVerificationCaptureAcknowledgement(
                    request: request,
                    status: failureReason == nil ? "succeeded" : "failed",
                    failureReason: failureReason,
                    captureResult: captureResult,
                    channelURL: channelURL
                )
                self.scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
            }
        }
    }

    /**
     * 等待长流程写入 completed 标记后再截图。
     */
    private func waitForVerificationCompletion(
        in window: NSWindow,
        capturePath: String,
        stateURL: URL,
        remainingAttempts: Int
    ) {
        let stages = (try? String(contentsOf: stateURL, encoding: .utf8)) ?? ""
        if stages.split(separator: "\n").contains("completed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.snapshotService.capture(window, to: capturePath)
            }
            return
        }
        guard remainingAttempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForVerificationCompletion(
                in: window,
                capturePath: capturePath,
                stateURL: stateURL,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    /**
     * 限制截图输出到临时目录中的魏碑验证证据根目录。
     */
    private func isSafeVerificationOutputRoot(_ outputURL: URL) -> Bool {
        let resolvedURL = outputURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        let allowedRoots = [
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
            FileManager.default.temporaryDirectory,
        ].map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        return allowedRoots.contains { rootPath in
            let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
            let prefix = normalizedRoot + "/"
            guard resolvedURL.path.hasPrefix(prefix) else { return false }
            let relativePath = resolvedURL.path.dropFirst(prefix.count)
            guard let evidenceRoot = relativePath.split(separator: "/").first else { return false }
            return evidenceRoot.hasPrefix("weibei-rich-answer-")
        }
    }

    /**
     * 判断截图目标的父目录是否位于配置的输出根目录内。
     */
    private func isCaptureURL(_ captureURL: URL, inside outputURL: URL) -> Bool {
        let rootPath = outputURL.standardizedFileURL.resolvingSymlinksInPath().path
        let captureParentPath = captureURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        let prefix = normalizedRoot + "/"
        return captureParentPath == normalizedRoot || captureParentPath.hasPrefix(prefix)
    }

    /**
     * 将截图文件、哈希、渲染就绪状态和工作区状态写入原子回执。
     */
    private func writeVerificationCaptureAcknowledgement(
        request: VerificationCaptureRequest,
        status: String,
        failureReason: String?,
        captureResult: VerificationCaptureResult? = nil,
        channelURL: URL
    ) {
        let acknowledgementURL = channelURL.appendingPathComponent("ack.json")
        var payload: [String: Any] = [
            "id": request.id,
            "requestID": request.id,
            "requestCapturePath": request.capturePath,
            "stage": request.stage ?? NSNull(),
            "capturePath": captureResult?.pngPath ?? request.capturePath,
            "status": status,
            "failureReason": failureReason ?? NSNull(),
            "acknowledgedAt": WindowSnapshotService.iso8601String(Date()),
            "renderReady": renderReadyEvidencePayload(),
            "webViewSnapshotTimeoutSeconds": WindowSnapshotService.webViewSnapshotTimeoutSeconds,
            "workspaceState": snapshotService.verificationWorkspaceState().payload,
        ]
        if let captureResult {
            payload["actualPNG"] = [
                "path": captureResult.pngPath,
                "bytes": captureResult.bytes,
                "sha256": captureResult.sha256,
                "hash": "sha256:\(captureResult.sha256)",
                "capturedAt": captureResult.capturedAt,
            ]
            payload["actualPNGPath"] = captureResult.pngPath
            payload["pngBytes"] = captureResult.bytes
            payload["pngSHA256"] = captureResult.sha256
            payload["pngHash"] = "sha256:\(captureResult.sha256)"
            payload["webViewSnapshotCount"] = captureResult.webViewSnapshotCount
            payload["captureWorkspaceState"] = [
                "start": captureResult.workspaceStateAtStart.payload,
                "end": captureResult.workspaceStateAtEnd.payload,
                "stable": captureResult.workspaceStateAtStart == captureResult.workspaceStateAtEnd,
            ]
        } else {
            payload["actualPNG"] = NSNull()
            payload["actualPNGPath"] = NSNull()
            payload["pngBytes"] = NSNull()
            payload["pngSHA256"] = NSNull()
            payload["pngHash"] = NSNull()
            payload["webViewSnapshotCount"] = NSNull()
            payload["captureWorkspaceState"] = NSNull()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        do {
            try data.write(to: acknowledgementURL, options: .atomic)
        } catch {
            fputs("WeiBei verification capture acknowledgement failed: \(error.localizedDescription)\n", stderr)
        }
    }

    /**
     * 读取 Rich Answer renderer-ready 标记并生成证据载荷。
     */
    private func renderReadyEvidencePayload() -> [String: Any] {
        let observedAt = WindowSnapshotService.iso8601String(Date())
        guard let workspaceDirectory = ProcessInfo.processInfo.environment["WEIBEI_WORKSPACE_DIR"],
              !workspaceDirectory.isEmpty else {
            return [
                "seen": false,
                "observedAt": observedAt,
                "failureReason": "WEIBEI_WORKSPACE_DIR is unavailable",
            ]
        }
        let markerURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .appendingPathComponent("rich-answer-renderer-ready.txt")
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return [
                "seen": false,
                "path": markerURL.path,
                "observedAt": observedAt,
                "failureReason": "renderer-ready marker is absent",
            ]
        }
        guard let markerData = try? Data(contentsOf: markerURL), !markerData.isEmpty else {
            return [
                "seen": false,
                "path": markerURL.path,
                "observedAt": observedAt,
                "failureReason": "renderer-ready marker is empty or unreadable",
            ]
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: markerURL.path)
        let modifiedAt = (attributes?[.modificationDate] as? Date).map(WindowSnapshotService.iso8601String)
        let sha256 = WindowSnapshotService.sha256Hex(for: markerData)
        return [
            "seen": true,
            "path": markerURL.path,
            "bytes": markerData.count,
            "sha256": sha256,
            "signature": "sha256:\(sha256)",
            "readyAt": modifiedAt ?? observedAt,
            "observedAt": observedAt,
            "modifiedAt": modifiedAt ?? NSNull(),
        ]
    }
}
