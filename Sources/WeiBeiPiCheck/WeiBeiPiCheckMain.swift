import Darwin
import Foundation
import WeiBeiCore

@main
struct WeiBeiPiCheckMain {
    static func main() async {
        let environment = ProcessInfo.processInfo.environment

        
        if await NativeEngineSmoke.runIfRequested(arguments: CommandLine.arguments) {
            return
        }

        if await NativeCapabilityDemo.runIfRequested(arguments: CommandLine.arguments) {
            return
        }

        if await NativeEvalCLI.runIfRequested(arguments: CommandLine.arguments) {
            return
        }

        if await NativeScenarioPair.runIfRequested(arguments: CommandLine.arguments) {
            return
        }

        if await NativeOAuthCLI.runIfRequested(arguments: CommandLine.arguments) {
            return
        }

        
        if CommandLine.arguments.contains("--authentication-status") {
            var status = AgentAuthenticationStatus()
            status.recordFailure(
                .offline,
                provider: .openaiCodex,
                authMethod: .subscription
            )
            status.recordFailure(
                .unauthorized,
                provider: .openaiCodex,
                authMethod: .apiKey
            )
            guard !status.requiresLogin(for: .openaiCodex) else {
                fputs("authentication-status-check failed: 非 OAuth 失效被误判为需要登录\n", stderr)
                exit(1)
            }
            status.recordFailure(
                .unauthorized,
                provider: .openaiCodex,
                authMethod: .subscription
            )
            guard status.requiresLogin(for: .openaiCodex) else {
                fputs("authentication-status-check failed: OAuth 认证失败后仍显示已连接\n", stderr)
                exit(1)
            }
            guard !status.requiresLogin(for: .anthropic) else {
                fputs("authentication-status-check failed: 一个服务失效误伤其他服务\n", stderr)
                exit(1)
            }
            status.recordSuccess(provider: .openaiCodex, authMethod: .subscription)
            guard !status.requiresLogin(for: .openaiCodex) else {
                fputs("authentication-status-check failed: 重新登录成功后仍要求登录\n", stderr)
                exit(1)
            }
            print("authentication-status-check passed")
            return
        }
        fputs("pi-check: no subcommand matched; pi runtime was retired 2026-08\n", stderr)
    }
}
