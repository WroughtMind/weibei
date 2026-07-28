import ArgumentParser

/// 魏碑开发、检查、验收和本地打包的统一命令行入口。
public struct WeiBeiDevTool: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "WeiBeiDevTool",
        abstract: "魏碑仓库开发工具。",
        discussion: "所有命令必须在仓库根目录运行。",
        subcommands: [
            PrepareCommand.self,
            CheckCommand.self,
            RunCommand.self,
            VerifyCommand.self,
            PackageCommand.self
        ]
    )

    /// 创建开发工具根命令。
    public init() {}
}

/// Installs production services before ArgumentParser dispatches a command.
@main
private enum WeiBeiDevToolMain {
    /// Installs the production adapter before handing control to ArgumentParser.
    static func main() async {
        DevToolServices.install(workflow: ProductionWorkflowProvider())
        await WeiBeiDevTool.main()
    }
}
