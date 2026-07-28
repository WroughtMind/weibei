import Foundation

/// 抽象验收轮询中的时间等待，以便单元测试不依赖真实时钟。
public protocol VerificationWaiting: Sendable {
    /// 暂停当前验证线程。
    func wait(seconds: TimeInterval)
}

/// 使用系统线程休眠的生产等待器。
public struct SystemVerificationWaiter: VerificationWaiting {
    /// 创建系统等待器。
    public init() {}

    /// 暂停当前线程指定时长。
    public func wait(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
