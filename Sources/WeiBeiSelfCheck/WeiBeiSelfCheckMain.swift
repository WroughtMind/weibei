import Foundation

/**
 * WeiBei 自检命令的纯入口。
 */
@main
enum WeiBeiSelfCheckMain {
    /**
     * 运行自检并将未处理错误转换为稳定的命令行失败输出。
     */
    @MainActor
    static func main() async {
        do {
            try await SelfCheckRunner.run()
        } catch {
            fputs("self-check failed: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
