import AppKit
import Foundation
import WeiBeiCore

enum NativeOAuthCLI {
    static func runIfRequested(arguments: [String]) async -> Bool {
        guard let index = arguments.firstIndex(of: "--native-oauth") else { return false }
        let action = arguments.dropFirst(index + 1).first ?? "help"
        do {
            switch action {
            case "login":
                print("native-oauth: opening ChatGPT login in the browser…")
                print("Sign in with your own account. Tokens stay in the WeiBei credential file and are not printed.")
                let store = try NativeAgentCredentialStore.defaultStore()
                _ = try await NativeOpenAIOAuth.loginWithBrowser(store: store) { url in
                    NSWorkspace.shared.open(url)
                }
                print("native-oauth login passed: credential stored (no token printed)")
            case "status":
                let store = try NativeAgentCredentialStore.defaultStore()
                let present = try NativeOpenAIOAuth.leftoverCredentialExists(in: store)
                print("native-oauth status: \(present ? "signed-in" : "signed-out")")
            case "refresh":
                let store = try NativeAgentCredentialStore.defaultStore()
                _ = try await NativeOpenAIOAuth.ensureFreshAccessToken(in: store, now: Date().addingTimeInterval(10_000))
                print("native-oauth refresh passed")
            case "logout":
                let store = try NativeAgentCredentialStore.defaultStore()
                try await NativeOpenAIOAuth.logout(from: store)
                let leftover = try NativeOpenAIOAuth.leftoverCredentialExists(in: store)
                guard !leftover else {
                    throw NativeLLMFailure(code: "oauth_logout", message: "credential file still has openai-codex after logout")
                }
                print("native-oauth logout passed: no leftover credential")
            default:
                print("usage: WeiBeiPiCheck --native-oauth login|status|refresh|logout")
            }
        } catch {
            fputs("native-oauth failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        return true
    }
}
