import Foundation
import Security

/// Local credential store for WeiBei Agent API keys.
///
/// **Product rule:** credentials live inside WeiBei app data. Opening the app must
/// never show a macOS login-keychain password dialog.
///
/// Production → Application Support files (0600).
/// Self-check may inject an isolated `SecKeychain` for unit tests only.
public struct WeiBeiCredentialStore {
    public let service: String
    public let account: String
    /// When non-nil, operate only on this isolated keychain (self-check).
    private let keychain: SecKeychain?

    public init(service: String, account: String, keychain: SecKeychain? = nil) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    public static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func load() -> String {
        if keychain == nil {
            return readLocalFile() ?? ""
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return Self.cleaned(String(data: data, encoding: .utf8) ?? "")
    }

    public func save(_ value: String) throws {
        let key = Self.cleaned(value)
        guard !key.isEmpty else {
            try delete()
            return
        }

        if keychain == nil {
            try writeLocalFile(key)
            return
        }

        try saveIsolatedKeychainOnly(key)
    }

    public func delete() throws {
        if keychain == nil {
            try? FileManager.default.removeItem(at: localFileURL)
            return
        }
        let status = SecItemDelete(matchQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.credentialError(status)
        }
    }

    // MARK: - Local file (Application Support)

    private var localFileURL: URL {
        WeiBeiAgentDataPaths.secretsDirectory
            .appendingPathComponent(Self.fileName(service: service, account: account))
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

    // MARK: - Isolated keychain (self-check only)

    private func saveIsolatedKeychainOnly(_ key: String) throws {
        let data = Data(key.utf8)
        _ = SecItemDelete(matchQuery as CFDictionary)

        var attributes = addAttributes
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Self.credentialError(addStatus) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private var readQuery: [String: Any] {
        var query = matchQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private var matchQuery: [String: Any] {
        var query = baseQuery
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        return query
    }

    private var addAttributes: [String: Any] {
        var attributes = baseQuery
        if let keychain {
            attributes[kSecUseKeychain as String] = keychain
        }
        return attributes
    }

    private static func credentialError(_ status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Credential error \(status)"
        return NSError(
            domain: "WeiBei.Credential",
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
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
