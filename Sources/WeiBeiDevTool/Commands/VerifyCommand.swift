import ArgumentParser
import WeiBeiDevCore

/// ArgumentParser 对核心场景注册表的轻量适配。
public struct VerificationScenarioArgument: ExpressibleByArgument, Hashable {
    public let rawValue: String

    /// 仅接受核心注册表中存在的验收场景名称。
    ///
    /// - Parameter argument: 命令行中的场景名称
    public init?(argument: String) {
        guard VerificationScenarioID(rawValue: argument) != nil else {
            return nil
        }
        rawValue = argument
    }
}

/// 在真实应用中运行场景验收。
public struct VerifyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "构建临时 App 并运行验收场景。"
    )

    @Option(name: .long, help: "只运行指定的已注册场景。")
    public var scenario: VerificationScenarioArgument?

    @Flag(name: .long, help: "运行全部已注册场景。")
    public var all = false

    @Flag(name: .long, help: "允许运行需要在线 PI 的场景。")
    public var includeLivePi = false

    @Flag(name: .long, help: "为所选场景执行视觉检查。")
    public var visual = false

    @Flag(name: .long, help: "在首个场景失败时停止。")
    public var failFast = false

    @OptionGroup public var output: DevToolOutputOptions

    /// 创建验收命令。
    public init() {}

    /// 拒绝含义冲突的场景选择。
    public mutating func validate() throws {
        if all, scenario != nil {
            throw ValidationError("--all 与 --scenario 不能同时使用。")
        }
    }

    /// 将验收选择和执行策略交给核心工作流。
    public mutating func run() async throws {
        let options = VerificationOptions(
            scenario: scenario?.rawValue,
            runsAllScenarios: all,
            includesLivePi: includeLivePi,
            performsVisualChecks: visual,
            failsFast: failFast
        )
        try await executeDevToolRequest(.verify(options), format: output.format)
    }
}
