import AppKit
import Foundation
import WeiBeiCore

/// Subscription providers that Pi authenticates via OAuth (`/login`).
/// Tokens are stored in **WeiBei’s** PiAgent directory (not terminal `~/.pi`).
/// In-app browser OAuth is implemented for openai-codex + anthropic; Copilot surfaces terminal guidance.
enum PiSubscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case openaiCodex = "openai-codex"
    case anthropic = "anthropic"
    case githubCopilot = "github-copilot"

    var id: String { rawValue }

    var piProviderFlag: String { rawValue }

    var supportsInAppOAuth: Bool {
        switch self {
        case .openaiCodex, .anthropic: return true
        case .githubCopilot: return false
        }
    }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        agentProviderID.label(language: language)
    }

    func detail(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .openaiCodex:
            return language.text(
                "浏览器 OAuth 连接 ChatGPT 订阅；凭证保存在魏碑应用数据中。",
                "Browser OAuth for ChatGPT subscription; credentials stay in WeiBei app data."
            )
        case .anthropic:
            return language.text(
                "浏览器 OAuth 连接 Claude 订阅；凭证保存在魏碑应用数据中。",
                "Browser OAuth for Claude subscription; credentials stay in WeiBei app data."
            )
        case .githubCopilot:
            return language.text(
                "暂需在终端完成 Copilot 登录后，将 token 配到魏碑（不与终端 Pi 自动共用）。",
                "Complete Copilot login in a terminal if needed, then configure WeiBei separately (not shared with CLI Pi)."
            )
        }
    }

    var defaultModel: String { agentProviderID.defaultModelHint }

    var agentProviderID: AgentProviderID {
        AgentProviderID(rawValue: rawValue) ?? .openai
    }
}

@MainActor
final class PiOAuthService: ObservableObject {
    static let shared = PiOAuthService()

    @Published private(set) var isLoggingIn = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?
    @Published private(set) var linkedProviders: [String] = []

    private var process: Process?
    private var stdoutPipe: Pipe?

    /// WeiBei-owned auth.json — never terminal `~/.pi/agent/auth.json`.
    var weibeiAuthURL: URL {
        WeiBeiAgentDataPaths.piAuthJSON
    }

    func refreshLinkedStatus() {
        WeiBeiAgentDataPaths.migrateHomePiAuthIfNeeded()
        linkedProviders = Self.readLinkedOAuthProviders(from: weibeiAuthURL)
    }

    static func readLinkedOAuthProviders(from url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return object.compactMap { key, value in
            guard let dict = value as? [String: Any],
                  (dict["type"] as? String) == "oauth",
                  dict["access"] != nil || dict["refresh"] != nil else { return nil }
            return key
        }.sorted()
    }

    func isLinked(_ provider: PiSubscriptionProvider) -> Bool {
        linkedProviders.contains(provider.rawValue)
    }

    func startLogin(_ provider: PiSubscriptionProvider) {
        guard !isLoggingIn else { return }
        lastError = nil
        statusMessage = nil
        isLoggingIn = true

        guard let node = Self.resolveNodeExecutable() else {
            isLoggingIn = false
            lastError = "Node.js is required for OAuth login (install Node 18+)."
            return
        }
        guard let script = Self.resolveOAuthScriptURL() else {
            isLoggingIn = false
            lastError = "OAuth helper script missing from app resources."
            return
        }

        _ = try? WeiBeiAgentDataPaths.ensurePiAgentDirectory()
        WeiBeiAgentDataPaths.migrateHomePiAuthIfNeeded()

        let process = Process()
        process.executableURL = node
        process.arguments = [
            script.path,
            "--provider", provider.piProviderFlag,
            "--auth-path", weibeiAuthURL.path,
        ]
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        stdoutPipe = pipe
        self.process = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.handleStdout(text, provider: provider)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.isLoggingIn = false
                self?.process = nil
                self?.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self?.refreshLinkedStatus()
                if proc.terminationStatus != 0, self?.lastError == nil {
                    self?.lastError = "OAuth process exited with code \(proc.terminationStatus)"
                }
            }
        }

        do {
            try process.run()
            statusMessage = "Starting OAuth…"
        } catch {
            isLoggingIn = false
            lastError = error.localizedDescription
        }
    }

    func cancelLogin() {
        process?.terminate()
        process = nil
        isLoggingIn = false
        statusMessage = "Login cancelled"
    }

    private func handleStdout(_ chunk: String, provider: PiSubscriptionProvider) {
        for line in chunk.split(whereSeparator: \.isNewline) {
            let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty,
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            switch type {
            case "auth_url":
                if let urlString = obj["url"] as? String, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                    statusMessage = "Browser opened — complete sign-in, then return here."
                }
            case "progress":
                statusMessage = obj["message"] as? String ?? statusMessage
            case "success":
                statusMessage = "Subscription linked for \(provider.label(language: .english))."
                lastError = nil
                refreshLinkedStatus()
                NotificationCenter.default.post(
                    name: .weiBeiPiOAuthDidSucceed,
                    object: nil,
                    userInfo: ["provider": provider.rawValue]
                )
            case "error":
                lastError = obj["message"] as? String ?? "OAuth failed"
                statusMessage = nil
            case "status", "start":
                break
            default:
                break
            }
        }
    }

    private static func resolveNodeExecutable() -> URL? {
        let candidates = [
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".nvm/versions/node").path,
        ]
        for path in candidates {
            if path.contains("nvm") {
                // Prefer first nvm node if present
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: path) {
                    for version in versions.sorted().reversed() {
                        let node = URL(fileURLWithPath: path)
                            .appendingPathComponent(version)
                            .appendingPathComponent("bin/node")
                        if FileManager.default.isExecutableFile(atPath: node.path) {
                            return node
                        }
                    }
                }
            } else if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // PATH lookup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["node"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func resolveOAuthScriptURL() -> URL? {
        if let resource = Bundle.main.url(forResource: "pi-oauth-login", withExtension: "mjs") {
            return resource
        }
        // Dev tree: Sources/WeiBei/Resources/pi-oauth-login.mjs
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/Resources/pi-oauth-login.mjs")
        if FileManager.default.fileExists(atPath: dev.path) {
            return dev
        }
        return nil
    }
}

extension Notification.Name {
    static let weiBeiPiOAuthDidSucceed = Notification.Name("weiBeiPiOAuthDidSucceed")
}
