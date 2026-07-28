import CoreGraphics
import Foundation

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

/// 查找指定应用进程可用于验收的主窗口。
public protocol VerificationWindowLocating: Sendable {
    /// 返回匹配 owner、PID、窗口层级和最小尺寸的首个屏幕窗口。
    func findWindow(
        ownerName: String,
        processIdentifier: pid_t,
        minimumSize: CGSize
    ) -> VerificationWindow?
}

/// 通过 CoreGraphics 窗口服务定位验收窗口。
public struct CoreGraphicsVerificationWindowLocator: VerificationWindowLocating {
    /// 创建 CoreGraphics 窗口定位器。
    public init() {}

    /// 精确匹配 PID，避免命中用户已打开的另一个魏碑实例。
    public func findWindow(
        ownerName: String,
        processIdentifier: pid_t,
        minimumSize: CGSize = CGSize(width: 600, height: 400)
    ) -> VerificationWindow? {
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.lazy.compactMap(Self.window(from:)).first {
            $0.ownerName == ownerName
                && $0.processIdentifier == processIdentifier
                && $0.bounds.width >= minimumSize.width
                && $0.bounds.height >= minimumSize.height
        }
    }

    /// Converts a CoreGraphics dictionary into a window only when bounds and PID are usable.
    static func window(from dictionary: [String: Any]) -> VerificationWindow? {
        guard let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
              let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let windowNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
              let layer = dictionary[kCGWindowLayer as String] as? NSNumber,
              layer.intValue == 0,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            return nil
        }
        if let isOnscreen = dictionary[kCGWindowIsOnscreen as String] as? NSNumber,
           !isOnscreen.boolValue {
            return nil
        }
        return VerificationWindow(
            id: CGWindowID(windowNumber.uint32Value),
            processIdentifier: ownerPID.int32Value,
            ownerName: ownerName,
            bounds: bounds
        )
    }
}

/// 轮询窗口服务，直到应用窗口出现或场景超时。
public struct VerificationWindowWaiter: Sendable {
    private let locator: any VerificationWindowLocating
    private let waiter: any VerificationWaiting
    private let pollingIntervalSeconds: TimeInterval

    /// 创建窗口轮询器。
    public init(
        locator: any VerificationWindowLocating = CoreGraphicsVerificationWindowLocator(),
        waiter: any VerificationWaiting = SystemVerificationWaiter(),
        pollingIntervalSeconds: TimeInterval = 0.2
    ) {
        self.locator = locator
        self.waiter = waiter
        self.pollingIntervalSeconds = pollingIntervalSeconds
    }

    /// 等待属于目标 PID 的可见主窗口。
    public func waitForWindow(
        ownerName: String,
        processIdentifier: pid_t,
        timeoutSeconds: TimeInterval,
        minimumSize: CGSize = CGSize(width: 600, height: 400)
    ) throws -> VerificationWindow {
        let attempts = max(1, Int(ceil(timeoutSeconds / pollingIntervalSeconds)))
        for attempt in 0..<attempts {
            if let window = locator.findWindow(
                ownerName: ownerName,
                processIdentifier: processIdentifier,
                minimumSize: minimumSize
            ) {
                return window
            }
            if attempt + 1 < attempts {
                waiter.wait(seconds: pollingIntervalSeconds)
            }
        }
        throw VerificationError(
            code: "window_not_found",
            message: "No visible \(ownerName) window of at least \(Int(minimumSize.width))x\(Int(minimumSize.height)) was found for PID \(processIdentifier)."
        )
    }
}
