import Foundation

/**
 * 自检失败及其稳定的命令行错误说明。
 */
struct SelfCheckFailure: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

/**
 * 自检共享的仓库定位能力。
 */
enum SelfCheckSupport {
    static let repositoryURL = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
}

/**
 * 验证自检条件，失败时输出统一错误并终止进程。
 */
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        let failure = SelfCheckFailure(message: message)
        fputs("self-check failed: \(failure.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
