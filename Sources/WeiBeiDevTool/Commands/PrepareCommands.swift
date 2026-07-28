import ArgumentParser

/// 准备应用构建和运行所需的依赖。
public struct PrepareCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "准备并校验开发依赖。",
        subcommands: [
            PrepareWebEditorCommand.self,
            PreparePiRuntimeCommand.self,
            PrepareAllCommand.self
        ]
    )

    /// 创建 prepare 命令。
    public init() {}
}

/// 准备 WebEditor 生成资源。
public struct PrepareWebEditorCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "web-editor",
        abstract: "构建并校验 WebEditor 资源。"
    )

    @OptionGroup public var output: DevToolOutputOptions

    /// 创建 WebEditor 准备命令。
    public init() {}

    /// 将 WebEditor 准备请求交给核心工作流。
    public mutating func run() async throws {
        try await executeDevToolRequest(.prepare(.webEditor), format: output.format)
    }
}

/// 准备 PI runtime。
public struct PreparePiRuntimeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "pi-runtime",
        abstract: "下载或复用并校验 PI runtime。"
    )

    @OptionGroup public var output: DevToolOutputOptions

    /// 创建 PI runtime 准备命令。
    public init() {}

    /// 将 PI runtime 准备请求交给核心工作流。
    public mutating func run() async throws {
        try await executeDevToolRequest(.prepare(.piRuntime), format: output.format)
    }
}

/// 准备当前阶段的全部开发依赖。
public struct PrepareAllCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "all",
        abstract: "准备并校验全部开发依赖。"
    )

    @OptionGroup public var output: DevToolOutputOptions

    /// 创建全部依赖准备命令。
    public init() {}

    /// 将全部依赖准备请求交给核心工作流。
    public mutating func run() async throws {
        try await executeDevToolRequest(.prepare(.all), format: output.format)
    }
}
