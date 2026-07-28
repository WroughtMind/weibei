import Foundation

/// 将命令请求交给可测试核心实现的统一入口。
public protocol WorkflowProviding: Sendable {
    /// 执行一个类型化开发工作流。
    ///
    /// - Parameter request: 命令适配层已经完成语法校验的请求
    /// - Returns: 供文本或 JSON 渲染的结果
    func execute(_ request: DevToolCommandRequest) async throws -> DevToolWorkflowResult
}

/// 抽象标准输出与标准错误，便于验证 CLI 渲染契约。
public protocol DevToolOutputWriting: Sendable {
    /// 向标准输出写入一行。
    ///
    /// - Parameter line: 不包含尾随换行的文本
    func writeStandardOutput(_ line: String)

    /// 向标准错误写入一行。
    ///
    /// - Parameter line: 不包含尾随换行的文本
    func writeStandardError(_ line: String)
}

/// 保存命令适配层使用的工作流和输出依赖。
///
/// 生产入口与测试都通过此处安装依赖，命令类型本身不创建业务服务。
public enum DevToolServices {
    private static let lock = NSLock()
    private static var workflowProvider: any WorkflowProviding = UnconfiguredWorkflowProvider()
    private static var outputWriter: any DevToolOutputWriting = StandardDevToolOutputWriter()

    /// 安装当前进程使用的工作流和输出实现。
    ///
    /// - Parameters:
    ///   - workflow: 承担实际业务流程的核心适配器
    ///   - output: 文本输出实现；默认写入进程标准流
    public static func install(
        workflow: any WorkflowProviding,
        output: any DevToolOutputWriting = StandardDevToolOutputWriter()
    ) {
        lock.lock()
        defer { lock.unlock() }
        workflowProvider = workflow
        outputWriter = output
    }

    /// 恢复未配置状态，供进程内测试隔离使用。
    public static func reset() {
        install(workflow: UnconfiguredWorkflowProvider())
    }

    /// Reads the workflow and output dependencies as one locked snapshot.
    static func snapshot() -> (workflow: any WorkflowProviding, output: any DevToolOutputWriting) {
        lock.lock()
        defer { lock.unlock() }
        return (workflowProvider, outputWriter)
    }
}

/// 默认写入进程标准流的输出实现。
public struct StandardDevToolOutputWriter: DevToolOutputWriting {
    /// 创建标准流输出器。
    public init() {}

    /// 向 stdout 写入 UTF-8 文本。
    public func writeStandardOutput(_ line: String) {
        FileHandle.standardOutput.write(Data("\(line)\n".utf8))
    }

    /// 向 stderr 写入 UTF-8 文本。
    public func writeStandardError(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }
}

private struct UnconfiguredWorkflowProvider: WorkflowProviding {
    /// Fails deterministically when production or tests forgot dependency installation.
    func execute(_ request: DevToolCommandRequest) async throws -> DevToolWorkflowResult {
        throw DevToolExecutionError(
            errorCode: "workflow_unconfigured",
            errorMessage: "WeiBeiDevTool 核心工作流尚未配置。"
        )
    }
}
