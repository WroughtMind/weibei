import AppKit
import Foundation
import ScreenCaptureKit

/// 记录窗口截图的抽样统计。
public struct VisualInspectionMetrics: Equatable, Codable, Sendable {
    public let sampledPixelCount: Int
    public let nonBlackRatio: Double
    public let blackRatio: Double
    public let transparentRatio: Double

    /// 创建截图统计结果。
    public init(
        sampledPixelCount: Int,
        nonBlackRatio: Double,
        blackRatio: Double,
        transparentRatio: Double
    ) {
        self.sampledPixelCount = sampledPixelCount
        self.nonBlackRatio = nonBlackRatio
        self.blackRatio = blackRatio
        self.transparentRatio = transparentRatio
    }
}

/// 对窗口截图执行像素级可见性检查。
public protocol VerificationVisualInspecting: Sendable {
    /// 检查截图是否为空、透明或包含大面积黑色渲染块。
    func inspect(imageAt imageURL: URL) throws -> VisualInspectionMetrics
}

/// 使用 AppKit 解码图片并复现旧验证脚本的抽样阈值。
public struct AppKitVerificationVisualInspector: VerificationVisualInspecting {
    public let minimumNonBlackRatio: Double
    public let maximumBlackRatio: Double
    public let maximumTransparentRatio: Double

    /// 创建视觉检查器。
    public init(
        minimumNonBlackRatio: Double = 0.02,
        maximumBlackRatio: Double = 0.12,
        maximumTransparentRatio: Double = 0.005
    ) {
        self.minimumNonBlackRatio = minimumNonBlackRatio
        self.maximumBlackRatio = maximumBlackRatio
        self.maximumTransparentRatio = maximumTransparentRatio
    }

    /// 在最多约 80×60 个采样点上计算视觉统计。
    public func inspect(imageAt imageURL: URL) throws -> VisualInspectionMetrics {
        guard let image = NSImage(contentsOf: imageURL),
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            throw VerificationError(code: "visual_image_invalid", message: "Unable to decode screenshot: \(imageURL.path)")
        }

        let xStep = max(1, bitmap.pixelsWide / 80)
        let yStep = max(1, bitmap.pixelsHigh / 60)
        var sampled = 0
        var visible = 0
        var black = 0
        var transparent = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) {
                guard let sourceColor = bitmap.colorAt(x: x, y: y),
                      let color = sourceColor.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent > 0.08 || color.greenComponent > 0.08 || color.blueComponent > 0.08 {
                    visible += 1
                }
                if color.redComponent < 0.035 && color.greenComponent < 0.035 && color.blueComponent < 0.035 {
                    black += 1
                }
                if color.alphaComponent < 0.05 {
                    transparent += 1
                }
                sampled += 1
            }
        }
        guard sampled > 0 else {
            throw VerificationError(code: "visual_image_empty", message: "Screenshot contains no readable pixels.")
        }

        let metrics = VisualInspectionMetrics(
            sampledPixelCount: sampled,
            nonBlackRatio: Double(visible) / Double(sampled),
            blackRatio: Double(black) / Double(sampled),
            transparentRatio: Double(transparent) / Double(sampled)
        )
        guard metrics.nonBlackRatio >= minimumNonBlackRatio,
              metrics.blackRatio <= maximumBlackRatio,
              metrics.transparentRatio <= maximumTransparentRatio else {
            throw VerificationError(
                code: "visual_content_invalid",
                message: "Captured window is empty, transparent, or contains black rendering blocks."
            )
        }
        return metrics
    }
}

/// 将指定窗口截图写入场景 artifacts。
public protocol VerificationWindowCapturing: Sendable {
    /// 捕获窗口并写入目标 PNG。
    func capture(window: VerificationWindow, to outputURL: URL) async throws
}

/// 通过 ScreenCaptureKit 捕获单个窗口，不启动额外命令进程。
public struct SystemVerificationWindowCapturer: VerificationWindowCapturing {
    /// 创建系统窗口截图器。
    public init() {}

    /// 将指定窗口的 ScreenCaptureKit 图像编码为 PNG。
    public func capture(window: VerificationWindow, to outputURL: URL) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw VerificationError(code: "window_capture_failed", message: error.localizedDescription)
        }
        guard let captureWindow = content.windows.first(where: { $0.windowID == window.id }) else {
            throw VerificationError(
                code: "window_capture_failed",
                message: "The verified window is no longer available for capture."
            )
        }
        let filter = SCContentFilter(desktopIndependentWindow: captureWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.bounds.width * 2), 1)
        configuration.height = max(Int(window.bounds.height * 2), 1)
        configuration.showsCursor = false
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw VerificationError(
                code: "window_capture_failed",
                message: "Window capture failed. Grant Screen Recording permission and retry. \(error.localizedDescription)"
            )
        }
        guard let data = NSBitmapImageRep(cgImage: image).representation(
            using: .png,
            properties: [:]
        ) else {
            throw VerificationError(
                code: "window_capture_failed",
                message: "Window capture failed. Grant Screen Recording permission and retry."
            )
        }
        do {
            try data.write(to: outputURL, options: .atomic)
        } catch {
            throw VerificationError(code: "window_capture_failed", message: error.localizedDescription)
        }
    }
}

/// 优先使用应用自己写出的截图，缺失时回退到窗口级捕获。
public struct VerificationCaptureResolver: Sendable {
    private let capturer: any VerificationWindowCapturing
    private let waiter: any VerificationWaiting

    /// 创建截图来源解析器。
    public init(
        capturer: any VerificationWindowCapturing = SystemVerificationWindowCapturer(),
        waiter: any VerificationWaiting = SystemVerificationWaiter()
    ) {
        self.capturer = capturer
        self.waiter = waiter
    }

    /// 等待应用截图十秒；未产生有效文件时捕获已经定位的窗口。
    public func resolve(
        appOwnedCaptureURL: URL,
        window: VerificationWindow,
        waitForAppCaptureSeconds: TimeInterval = 10
    ) async throws -> URL {
        let attempts = max(1, Int(ceil(waitForAppCaptureSeconds / 0.2)))
        for attempt in 0..<attempts {
            if hasNonEmptyFile(at: appOwnedCaptureURL) {
                return appOwnedCaptureURL
            }
            if attempt + 1 < attempts {
                waiter.wait(seconds: 0.2)
            }
        }
        try await capturer.capture(window: window, to: appOwnedCaptureURL)
        guard hasNonEmptyFile(at: appOwnedCaptureURL) else {
            throw VerificationError(code: "window_capture_empty", message: "Window capture did not produce a non-empty image.")
        }
        return appOwnedCaptureURL
    }

    /// Reports whether an app-owned or system capture contains image bytes.
    private func hasNonEmptyFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }
}
