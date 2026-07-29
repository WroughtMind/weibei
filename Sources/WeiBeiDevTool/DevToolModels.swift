import Foundation

/// 可由开发工具执行的依赖准备目标。
public enum PrepareTarget: String, Codable, Equatable, Sendable {
    case webEditor = "web-editor"
    case richAnswer = "rich-answer"
    case piRuntime = "pi-runtime"
    case all
}

/// 启动魏碑时使用的运行模式。
public enum RunMode: String, Codable, Equatable, Sendable {
    case standard
    case debug
    case logs
    case telemetry
}

/// 验收流程的场景选择与执行策略。
public struct VerificationOptions: Codable, Equatable, Sendable {
    public let scenario: String?
    public let runsAllScenarios: Bool
    public let includesLivePi: Bool
    public let performsVisualChecks: Bool
    public let failsFast: Bool

    /// 创建验收流程配置。
    ///
    /// - Parameters:
    ///   - scenario: 只运行的已注册场景名称；为 `nil` 且未选择全部场景时运行 `offline-learning-flow`
    ///   - runsAllScenarios: 是否选择全部可用场景
    ///   - includesLivePi: 是否允许运行依赖在线 PI 的场景
    ///   - performsVisualChecks: 是否对所选场景执行视觉检查
    ///   - failsFast: 是否在首个场景失败时停止
    public init(
        scenario: String?,
        runsAllScenarios: Bool,
        includesLivePi: Bool,
        performsVisualChecks: Bool,
        failsFast: Bool
    ) {
        self.scenario = scenario
        self.runsAllScenarios = runsAllScenarios
        self.includesLivePi = includesLivePi
        self.performsVisualChecks = performsVisualChecks
        self.failsFast = failsFast
    }
}

/// 命令适配层提交给核心工作流的类型化请求。
public enum DevToolCommandRequest: Equatable, Sendable {
    case prepare(PrepareTarget)
    case check
    case run(RunMode)
    case verify(VerificationOptions)
    case package

    /// 用于日志和结构化输出的稳定命令名称。
    public var commandName: String {
        switch self {
        case let .prepare(target):
            return "prepare \(target.rawValue)"
        case .check:
            return "check"
        case .run:
            return "run"
        case .verify:
            return "verify"
        case .package:
            return "package"
        }
    }
}

/// 核心工作流返回给命令适配层的显示结果。
public struct DevToolWorkflowResult: Equatable, Sendable {
    public let summary: String
    public let details: [String: String]
    public let primaryPath: String?

    /// 创建可供文本和 JSON 输出共用的工作流结果。
    ///
    /// - Parameters:
    ///   - summary: 面向用户的简洁结果摘要
    ///   - details: 可选的稳定键值详情
    ///   - primaryPath: 可供脚本直接消费的主要产物绝对路径
    public init(
        summary: String,
        details: [String: String] = [:],
        primaryPath: String? = nil
    ) {
        self.summary = summary
        self.details = details
        self.primaryPath = primaryPath
    }
}

/// 可被命令适配层转换为稳定错误代码的工作流错误。
public protocol DevToolCodedError: Error {
    /// 自动化可以稳定识别的错误代码。
    var errorCode: String { get }

    /// 面向用户的错误说明。
    var errorMessage: String { get }
}

/// DevTool 自身产生的稳定错误。
public struct DevToolExecutionError: DevToolCodedError, Equatable, Sendable {
    public let errorCode: String
    public let errorMessage: String

    /// 创建带稳定代码的 DevTool 错误。
    ///
    /// - Parameters:
    ///   - errorCode: 自动化使用的稳定字符串代码
    ///   - errorMessage: 面向用户的错误说明
    public init(errorCode: String, errorMessage: String) {
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}
