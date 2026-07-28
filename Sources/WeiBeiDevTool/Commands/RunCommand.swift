import ArgumentParser

/// 构建并启动魏碑应用。
public struct RunCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "构建临时 App 并启动魏碑。"
    )

    @Flag(name: .long, help: "使用 debug 构建并交给 LLDB。")
    public var debug = false

    @Flag(name: .long, help: "启动应用并观察统一日志。")
    public var logs = false

    @Flag(name: .long, help: "启动应用并观察遥测日志。")
    public var telemetry = false

    @OptionGroup public var output: DevToolOutputOptions

    /// 创建运行命令。
    public init() {}

    /// 拒绝同时选择多个互斥运行模式。
    public mutating func validate() throws {
        let selectedModeCount = [debug, logs, telemetry].filter { $0 }.count
        guard selectedModeCount <= 1 else {
            throw ValidationError("--debug、--logs 和 --telemetry 不能同时使用。")
        }
    }

    /// 将选定运行模式交给核心工作流。
    public mutating func run() async throws {
        let mode: RunMode
        if debug {
            mode = .debug
        } else if logs {
            mode = .logs
        } else if telemetry {
            mode = .telemetry
        } else {
            mode = .standard
        }
        try await executeDevToolRequest(.run(mode), format: output.format)
    }
}
