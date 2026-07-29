import CoreGraphics
import Foundation
import WeiBeiCore

/// 验收所需的最小窗口信息。
public struct VerificationWindow: Equatable, Sendable {
    public let id: CGWindowID
    public let processIdentifier: pid_t
    public let ownerName: String
    public let bounds: CGRect

    /// 创建匹配应用 PID 的窗口描述。
    public init(id: CGWindowID, processIdentifier: pid_t, ownerName: String, bounds: CGRect) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.ownerName = ownerName
        self.bounds = bounds
    }
}

/// 查找 readiness 已声明的真实窗口。
public protocol VerificationWindowLocating: Sendable {
    /// 按窗口号和 PID 复核 layer、可见性和最小尺寸；owner 只保留为诊断信息。
    func findWindow(
        windowID: CGWindowID,
        processIdentifier: pid_t,
        minimumSize: CGSize
    ) -> VerificationWindow?
}

/// 通过 CoreGraphics 窗口服务定位验收窗口。
public struct CoreGraphicsVerificationWindowLocator: VerificationWindowLocating {
    /// 创建 CoreGraphics 窗口定位器。
    public init() {}

    /// 精确匹配 readiness 中的窗口号与 PID。
    public func findWindow(
        windowID: CGWindowID,
        processIdentifier: pid_t,
        minimumSize: CGSize = CGSize(width: 600, height: 400)
    ) -> VerificationWindow? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.lazy.compactMap(Self.window(from:)).first {
            $0.id == windowID
                && $0.processIdentifier == processIdentifier
                && $0.bounds.width >= minimumSize.width
                && $0.bounds.height >= minimumSize.height
        }
    }

    /// 只接受 layer 0、屏幕可见且包含有效 PID、窗口号和 bounds 的窗口。
    static func window(from dictionary: [String: Any]) -> VerificationWindow? {
        guard let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let windowNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
              let layer = dictionary[kCGWindowLayer as String] as? NSNumber,
              layer.intValue == 0,
              let isOnscreen = dictionary[kCGWindowIsOnscreen as String] as? NSNumber,
              isOnscreen.boolValue,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            return nil
        }
        return VerificationWindow(
            id: CGWindowID(windowNumber.uint32Value),
            processIdentifier: ownerPID.int32Value,
            ownerName: dictionary[kCGWindowOwnerName as String] as? String ?? "",
            bounds: bounds
        )
    }
}

/// 等待应用原子发布 readiness，并通过窗口服务独立复核。
public struct VerificationWindowWaiter: Sendable {
    private let locator: any VerificationWindowLocating
    private let waiter: any VerificationWaiting
    private let pollingIntervalSeconds: TimeInterval

    /// 创建窗口协议轮询器。
    public init(
        locator: any VerificationWindowLocating = CoreGraphicsVerificationWindowLocator(),
        waiter: any VerificationWaiting = SystemVerificationWaiter(),
        pollingIntervalSeconds: TimeInterval = 0.2
    ) {
        self.locator = locator
        self.waiter = waiter
        self.pollingIntervalSeconds = pollingIntervalSeconds
    }

    /// 最多等待 15 秒取得属于当前 PID 的稳定 readiness 快照。
    package func waitForReadiness(
        at readinessURL: URL,
        artifactRoot: URL,
        app: any VerificationRunningApp,
        timeoutSeconds: TimeInterval = 15
    ) throws -> VerificationWindowReadyEnvelope {
        let attempts = max(1, Int(ceil(timeoutSeconds / pollingIntervalSeconds)))
        for attempt in 0..<attempts {
            guard app.isRunning else {
                throw VerificationError(code: "app_exited_early", message: "Verification app exited before publishing window readiness.")
            }
            if FileManager.default.fileExists(atPath: readinessURL.path),
               let readiness = try? VerificationContractIO.decode(
                   VerificationWindowReadyEnvelope.self,
                   from: readinessURL,
                   within: artifactRoot
               ) {
                do {
                    try readiness.validate()
                    guard readiness.processIdentifier == app.processIdentifier else {
                        throw VerificationError(
                            code: "window_ready_timeout",
                            message: "Window readiness PID \(readiness.processIdentifier) does not match launched PID \(app.processIdentifier)."
                        )
                    }
                    return readiness
                } catch let error as VerificationError {
                    throw error
                } catch {
                    throw VerificationError(code: "window_ready_timeout", message: error.localizedDescription)
                }
            }
            if attempt + 1 < attempts {
                waiter.wait(seconds: pollingIntervalSeconds)
            }
        }
        throw VerificationError(
            code: "window_ready_timeout",
            message: "Verification app did not publish valid window readiness within \(Int(timeoutSeconds)) seconds."
        )
    }

    /// 使用 readiness 的 PID 与窗口号复核真实可见窗口。
    package func waitForWindow(
        readiness: VerificationWindowReadyEnvelope,
        app: any VerificationRunningApp,
        timeoutSeconds: TimeInterval = 15,
        minimumSize: CGSize = CGSize(width: 600, height: 400)
    ) throws -> VerificationWindow {
        guard readiness.bounds.width >= minimumSize.width,
              readiness.bounds.height >= minimumSize.height else {
            throw VerificationError(
                code: "window_visibility_timeout",
                message: "Readiness bounds are smaller than \(Int(minimumSize.width))x\(Int(minimumSize.height))."
            )
        }
        let attempts = max(1, Int(ceil(timeoutSeconds / pollingIntervalSeconds)))
        for attempt in 0..<attempts {
            guard app.isRunning else {
                throw VerificationError(code: "app_exited_early", message: "Verification app exited before its window became visible.")
            }
            if let window = locator.findWindow(
                windowID: CGWindowID(readiness.windowNumber),
                processIdentifier: app.processIdentifier,
                minimumSize: minimumSize
            ) {
                return window
            }
            if attempt + 1 < attempts {
                waiter.wait(seconds: pollingIntervalSeconds)
            }
        }
        throw VerificationError(
            code: "window_visibility_timeout",
            message: "Window \(readiness.windowNumber) for PID \(app.processIdentifier) was not visible within \(Int(timeoutSeconds)) seconds."
        )
    }
}
