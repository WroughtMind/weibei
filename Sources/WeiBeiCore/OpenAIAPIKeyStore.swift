import Foundation

/// Local credential store for WeiBei Agent API keys.
///
/// Credentials live inside WeiBei Application Support as owner-readable files.
/// The app does not read from or write to the macOS login keychain.
public struct WeiBeiCredentialStore {
    public let service: String
    public let account: String
    private let directory: URL

    /**
     * 创建仅使用本地文件的凭据存储。
     *
     * @param service - 用于隔离不同凭据命名空间的服务标识
     * @param account - 当前服务中的凭据账户标识
     * @param directory - 凭据目录；生产环境默认使用魏碑 Application Support
     */
    public init(
        service: String,
        account: String,
        directory: URL = WeiBeiAgentDataPaths.secretsDirectory
    ) {
        self.service = service
        self.account = account
        self.directory = directory
    }

    public static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func load() -> String {
        readLocalFile() ?? ""
    }

    public func save(_ value: String) throws {
        let key = Self.cleaned(value)
        guard !key.isEmpty else {
            try delete()
            return
        }

        try writeLocalFile(key)
    }

    public func delete() throws {
        try? FileManager.default.removeItem(at: localFileURL)
    }

    private var localFileURL: URL {
        directory.appendingPathComponent(Self.fileName(service: service, account: account))
    }

    private func readLocalFile() -> String? {
        guard let data = try? Data(contentsOf: localFileURL) else { return nil }
        let value = Self.cleaned(String(data: data, encoding: .utf8) ?? "")
        return value.isEmpty ? nil : value
    }

    private func writeLocalFile(_ value: String) throws {
        let url = localFileURL
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        try Data(value.utf8).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func fileName(service: String, account: String) -> String {
        let raw = "\(service)__\(account)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scaled = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scaled) + ".secret"
    }

}

public enum OpenAIAPIKeyStore {
    public static let service = "com.changfenhuang.weibei.openai"
    /// Legacy single-account name kept for backward compatibility with openai keys.
    public static let account = "OPENAI_API_KEY"

    private static func store(forAccount account: String) -> WeiBeiCredentialStore {
        WeiBeiCredentialStore(service: service, account: account)
    }

    public static func accountName(forProvider provider: String) -> String {
        let cleaned = cleaned(provider).lowercased()
        if cleaned.isEmpty || cleaned == "openai" {
            return account
        }
        return "PROVIDER_KEY_\(cleaned)"
    }

    public static func cleaned(_ value: String) -> String {
        WeiBeiCredentialStore.cleaned(value)
    }

    public static func load(provider: String = "openai") -> String {
        let named = store(forAccount: accountName(forProvider: provider)).load()
        if !named.isEmpty { return named }
        if provider == "openai" || provider.isEmpty {
            return store(forAccount: account).load()
        }
        return ""
    }

    public static func save(_ value: String, provider: String = "openai") throws {
        try store(forAccount: accountName(forProvider: provider)).save(value)
    }

    public static func delete(provider: String = "openai") throws {
        try store(forAccount: accountName(forProvider: provider)).delete()
    }
}
