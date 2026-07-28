import Foundation

/**
 * 根据环境变量选择并运行完整或专项自检。
 */
enum SelfCheckRunner {
    /**
     * 运行当前环境请求的自检集合。
     */
    @MainActor
    static func run() async throws {
        if ProcessInfo.processInfo.environment["WEIBEI_RICH_ANSWER_SELF_CHECK_ONLY"] == "1" {
            runRichAnswerEmbeddingSelfChecks()
            print("WeiBei rich-answer embedding self-check passed")
            return
        }

        if ProcessInfo.processInfo.environment["WEIBEI_PI_TERMINAL_SELF_CHECK_ONLY"] == "1" {
            try await runPiTerminalRuntimeSelfChecks()
            print("WeiBei PI terminal runtime self-check passed")
            return
        }

        try await runWeiBeiSelfChecks()
    }
}
