import AppKit
import CryptoKit
import Foundation
import WebKit

/**
 * 捕获真实 AppKit 窗口，并把 WKWebView 的进程外内容合成进最终 PNG。
 */
@MainActor
final class WindowSnapshotService {
    static let webViewSnapshotTimeoutSeconds: TimeInterval = 4

    /**
     * 等待窗口中的紧凑 Markdown 预览完成至少两次稳定测量。
     */
    func waitForSingleCaptureReadiness(
        in window: NSWindow,
        remainingAttempts: Int,
        previousReadiness: CompactPreviewReadiness? = nil,
        completion: @escaping (SingleCaptureReadinessResult) -> Void
    ) {
        guard let contentView = window.contentView else {
            completion(.failed("window content view is unavailable while waiting for compact preview readiness"))
            return
        }
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let webViews = visibleWebViews(in: contentView)
        guard !webViews.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                completion(.ready)
            }
            return
        }
        compactPreviewReadiness(in: webViews) { [weak self] readiness in
            guard let self else { return }
            if let previousReadiness, readiness.isStable(comparedTo: previousReadiness) {
                completion(.ready)
                return
            }
            guard remainingAttempts > 0 else {
                completion(
                    .failed(
                        "compact preview readiness timed out "
                            + "(compact: \(readiness.compactCount), "
                            + "pending: \(readiness.pendingCount), "
                            + "evaluation failures: \(readiness.evaluationFailureCount))"
                    )
                )
                return
            }
            let nextPreviousReadiness = readiness.isReady ? readiness : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.waitForSingleCaptureReadiness(
                    in: window,
                    remainingAttempts: remainingAttempts - 1,
                    previousReadiness: nextPreviousReadiness,
                    completion: completion
                )
            }
        }
    }

    /**
     * 捕获窗口到指定路径；若工作区在 WebView 捕获期间变化则拒绝产出证据。
     */
    func capture(
        _ window: NSWindow,
        to capturePath: String,
        completion: @escaping (VerificationCaptureResult?, String?) -> Void = { _, _ in }
    ) {
        let workspaceStateAtStart = verificationWorkspaceState()
        guard !FileManager.default.fileExists(atPath: capturePath) else {
            completion(nil, "capture target already exists")
            return
        }
        guard let contentView = window.contentView else {
            completion(nil, "window content view is unavailable")
            return
        }
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bounds = contentView.bounds
        guard bounds.width >= 600, bounds.height >= 400 else {
            completion(nil, "window content bounds are smaller than the verification minimum")
            return
        }
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            completion(nil, "window content bitmap could not be allocated")
            return
        }
        contentView.cacheDisplay(in: bounds, to: bitmap)
        let baseImage = NSImage(size: bounds.size)
        baseImage.addRepresentation(bitmap)
        let webViews = visibleWebViews(in: contentView)
        captureWebViews(webViews, at: 0, relativeTo: contentView, overlays: []) { overlays, webViewFailure in
            if let webViewFailure {
                completion(nil, webViewFailure)
                return
            }
            let workspaceStateAtEnd = self.verificationWorkspaceState()
            guard workspaceStateAtStart == workspaceStateAtEnd else {
                completion(
                    nil,
                    "workspace state changed during capture: \(workspaceStateAtStart.diagnosticDescription) -> \(workspaceStateAtEnd.diagnosticDescription)"
                )
                return
            }
            let composite = NSImage(size: bounds.size)
            composite.lockFocus()
            baseImage.draw(in: bounds)
            for overlay in overlays {
                overlay.image.draw(in: overlay.rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            composite.unlockFocus()
            guard let tiff = composite.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiff),
                  let png = representation.representation(using: .png, properties: [:]) else {
                completion(nil, "captured window could not be encoded as PNG")
                return
            }
            let captureURL = URL(fileURLWithPath: capturePath).standardizedFileURL.resolvingSymlinksInPath()
            do {
                try png.write(to: captureURL, options: .atomic)
            } catch {
                completion(nil, "captured PNG could not be written: \(error.localizedDescription)")
                return
            }
            guard let writtenData = try? Data(contentsOf: captureURL), !writtenData.isEmpty else {
                completion(nil, "captured PNG could not be verified after write")
                return
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: captureURL.path)
            let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? writtenData.count
            completion(
                VerificationCaptureResult(
                    pngPath: captureURL.path,
                    bytes: bytes,
                    sha256: Self.sha256Hex(for: writtenData),
                    capturedAt: Self.iso8601String(Date()),
                    webViewSnapshotCount: overlays.count,
                    workspaceStateAtStart: workspaceStateAtStart,
                    workspaceStateAtEnd: workspaceStateAtEnd
                ),
                nil
            )
        }
    }

    /**
     * 读取当前 Store 的可见布局快照。
     */
    func verificationWorkspaceState() -> VerificationWorkspaceState {
        let visiblePaneRoles = sharedWorkspaceStore.visibleDocumentPaneOrder
        let frameList = sharedWorkspaceStore.threePaneReorderFrameList(order: visiblePaneRoles, fallback: [])
        let frames: [String: CGRect]
        if frameList.count == visiblePaneRoles.count {
            frames = Dictionary(uniqueKeysWithValues: zip(visiblePaneRoles, frameList).map { role, frame in
                (role.rawValue, frame)
            })
        } else {
            frames = [:]
        }
        return VerificationWorkspaceState(
            layout: sharedWorkspaceStore.layout.rawValue,
            showReader: sharedWorkspaceStore.showReader,
            showAgent: sharedWorkspaceStore.showAgent,
            showNotes: sharedWorkspaceStore.showNotes,
            selectedItemID: sharedWorkspaceStore.selectedItemID,
            visiblePanes: visiblePaneRoles.map(\.rawValue),
            paneFrames: frames
        )
    }

    /**
     * 生成包含小数秒的 ISO 8601 时间。
     */
    static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /**
     * 生成数据的十六进制 SHA-256 摘要。
     */
    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /**
     * 汇总窗口内所有 WebView 的紧凑预览就绪状态。
     */
    private func compactPreviewReadiness(
        in webViews: [WKWebView],
        completion: @escaping (CompactPreviewReadiness) -> Void
    ) {
        compactPreviewReadiness(
            in: webViews,
            at: 0,
            current: CompactPreviewReadiness(
                compactCount: 0,
                pendingCount: 0,
                evaluationFailureCount: 0,
                measuredHeights: []
            ),
            completion: completion
        )
    }

    /**
     * 按顺序测量 WebView，避免并行回调破坏结果顺序。
     */
    private func compactPreviewReadiness(
        in webViews: [WKWebView],
        at index: Int,
        current: CompactPreviewReadiness,
        completion: @escaping (CompactPreviewReadiness) -> Void
    ) {
        guard webViews.indices.contains(index) else {
            completion(current)
            return
        }
        let script = """
        (() => {
          const compact = window.weiBeiMarkdownCompactPreview === true
            || document.documentElement.dataset.weibeiCompactPreview === 'true';
          if (!compact) return { compact: false, ready: true };
          const nodes = [
            document.querySelector('#editor'),
            document.querySelector('.milkdown'),
            document.querySelector('.ProseMirror')
          ].filter(Boolean);
          const nodeHeight = (node) => {
            const rect = node.getBoundingClientRect?.();
            return Math.max(
              0,
              node.scrollHeight || 0,
              node.offsetHeight || 0,
              node.clientHeight || 0,
              rect?.height || 0
            );
          };
          const height = Math.ceil(Math.max(0, ...nodes.map(nodeHeight)));
          const reportedHeight = Number(window.WeiBeiCompactPreviewHeight || 0);
          const measuredAt = Number(window.WeiBeiCompactPreviewMeasuredAt || 0);
          const ready = nodes.length > 0
            && Number.isFinite(height)
            && height > 0
            && Number.isFinite(reportedHeight)
            && reportedHeight > 0
            && Math.abs(reportedHeight - height) <= 1
            && Number.isFinite(measuredAt)
            && measuredAt > 0;
          return { compact: true, ready, height, reportedHeight, measuredAt };
        })();
        """
        webViews[index].evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            var next = current
            if error != nil {
                next.evaluationFailureCount += 1
            } else if let payload = result as? [String: Any], let isCompact = payload["compact"] as? Bool {
                guard isCompact else {
                    self.compactPreviewReadiness(in: webViews, at: index + 1, current: next, completion: completion)
                    return
                }
                next.compactCount += 1
                if payload["ready"] as? Bool == true,
                   let height = payload["height"] as? NSNumber,
                   height.doubleValue.isFinite,
                   height.doubleValue > 0 {
                    next.measuredHeights.append(height.intValue)
                } else {
                    next.pendingCount += 1
                }
            } else {
                next.evaluationFailureCount += 1
            }
            self.compactPreviewReadiness(in: webViews, at: index + 1, current: next, completion: completion)
        }
    }

    private final class WebViewSnapshotState {
        var isCompleted = false
    }

    private struct WebViewSnapshot {
        var rect: NSRect
        var image: NSImage
    }

    /**
     * 在超时边界内捕获单个 WebView 的可见矩形。
     */
    private func captureWebViewSnapshot(
        _ webView: WKWebView,
        rect: NSRect,
        completion: @escaping (NSImage?, String?) -> Void
    ) {
        let state = WebViewSnapshotState()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.webViewSnapshotTimeoutSeconds) {
            self.completeWebViewSnapshotOnce(
                state: state,
                completion: completion,
                image: nil,
                failureReason: "web content snapshot timed out after \(String(format: "%.1f", Self.webViewSnapshotTimeoutSeconds)) seconds"
            )
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.completeWebViewSnapshotOnce(
                        state: state,
                        completion: completion,
                        image: nil,
                        failureReason: "web content snapshot failed: \(error.localizedDescription)"
                    )
                    return
                }
                guard let image else {
                    self.completeWebViewSnapshotOnce(
                        state: state,
                        completion: completion,
                        image: nil,
                        failureReason: "web content snapshot returned no image"
                    )
                    return
                }
                self.completeWebViewSnapshotOnce(state: state, completion: completion, image: image, failureReason: nil)
            }
        }
    }

    /**
     * 保证超时和 WebKit 回调只完成一次捕获。
     */
    private func completeWebViewSnapshotOnce(
        state: WebViewSnapshotState,
        completion: @escaping (NSImage?, String?) -> Void,
        image: NSImage?,
        failureReason: String?
    ) {
        guard !state.isCompleted else { return }
        state.isCompleted = true
        completion(image, failureReason)
    }

    /**
     * 计算 WebView 经所有父视图裁剪后的窗口可见区域。
     */
    private func visibleRect(of webView: WKWebView, relativeTo contentView: NSView) -> NSRect {
        var visibleRect = webView.convert(webView.bounds, to: contentView).intersection(contentView.bounds)
        var ancestor = webView.superview
        while let view = ancestor, view !== contentView, !visibleRect.isNull {
            visibleRect = visibleRect.intersection(view.convert(view.bounds, to: contentView))
            ancestor = view.superview
        }
        return visibleRect
    }

    /**
     * 按视图层级收集当前窗口中的可见 WebView。
     */
    private func visibleWebViews(in view: NSView) -> [WKWebView] {
        view.subviews.flatMap { child -> [WKWebView] in
            var matches = child.isHidden ? [] : visibleWebViews(in: child)
            if let webView = child as? WKWebView, !webView.isHidden, webView.window != nil {
                matches.insert(webView, at: 0)
            }
            return matches
        }
    }

    /**
     * 顺序捕获 WebView 并积累合成所需的覆盖图层。
     */
    private func captureWebViews(
        _ webViews: [WKWebView],
        at index: Int,
        relativeTo contentView: NSView,
        overlays: [WebViewSnapshot],
        completion: @escaping ([WebViewSnapshot], String?) -> Void
    ) {
        guard webViews.indices.contains(index) else {
            completion(overlays, nil)
            return
        }
        let webView = webViews[index]
        let converted = visibleRect(of: webView, relativeTo: contentView)
        let rect = contentView.isFlipped
            ? NSRect(x: converted.minX, y: contentView.bounds.height - converted.maxY, width: converted.width, height: converted.height)
            : converted
        guard !converted.isNull, rect.width > 1, rect.height > 1 else {
            captureWebViews(webViews, at: index + 1, relativeTo: contentView, overlays: overlays, completion: completion)
            return
        }
        let snapshotRect = webView.convert(converted, from: contentView).intersection(webView.bounds)
        guard !snapshotRect.isNull, snapshotRect.width > 1, snapshotRect.height > 1 else {
            captureWebViews(webViews, at: index + 1, relativeTo: contentView, overlays: overlays, completion: completion)
            return
        }
        captureWebViewSnapshot(webView, rect: snapshotRect) { [weak self] image, failureReason in
            guard let self else { return }
            if let failureReason {
                completion(overlays, failureReason)
                return
            }
            guard let image else {
                completion(overlays, "web content snapshot returned no image")
                return
            }
            var nextOverlays = overlays
            nextOverlays.append(WebViewSnapshot(rect: rect, image: image))
            self.captureWebViews(
                webViews,
                at: index + 1,
                relativeTo: contentView,
                overlays: nextOverlays,
                completion: completion
            )
        }
    }
}
