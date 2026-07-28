import ArgumentParser

/// 执行项目的 Swift 检查流程。
public struct CheckCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "构建并运行 Swift 测试和产品自检。"
    )

    @OptionGroup public var output: DevToolOutputOptions

    /// 创建检查命令。
    public init() {}

    /// 将检查请求交给核心工作流。
    public mutating func run() async throws {
        try await executeDevToolRequest(.check, format: output.format)
    }
}
