import Foundation

/**
 * 自检失败及其稳定的命令行错误说明。
 */
struct SelfCheckFailure: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

/**
 * 自检共享的仓库定位与源码读取能力。
 */
enum SelfCheckSupport {
    static let repositoryURL = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )

    /**
     * 读取仓库内的 UTF-8 文本文件；文件不可读时返回空字符串并由具体断言报告失败。
     */
    static func source(_ relativePath: String, repositoryURL: URL) -> String {
        let url = repositoryURL.appendingPathComponent(relativePath)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /**
     * 递归读取目录内指定扩展名的源码，并按路径稳定拼接。
     */
    static func joinedSources(in relativeDirectory: String, pathExtension: String, repositoryURL: URL) -> String {
        let directoryURL = repositoryURL.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return "" }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == pathExtension }
            .sorted { $0.path < $1.path }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
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
