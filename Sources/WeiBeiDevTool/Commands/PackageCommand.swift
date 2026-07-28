import ArgumentParser

/// 构建并严格校验本地魏碑 App 产物。
public struct PackageCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "package",
        abstract: "事务化生成 dist/魏碑.app。"
    )

    @OptionGroup public var output: DevToolOutputOptions

    /// 创建打包命令。
    public init() {}

    /// 将本地 App 打包请求交给核心工作流。
    public mutating func run() async throws {
        try await executeDevToolRequest(.package, format: output.format)
    }
}
