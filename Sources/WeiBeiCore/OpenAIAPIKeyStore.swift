import Foundation
import Security

public struct KeychainPasswordStore {
    public let service: String
    public let account: String
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
        var result: CFTypeRef?
        // Never show a keychain prompt UI — if the item needs auth we migrate/re-save
        // with an open ACL on next successful save, or return empty.
        var query = readQuery
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return Self.cleaned(String(data: data, encoding: .utf8) ?? "")
        }
        // Fallback without the auth UI flag (older macOS / temporary keychain tests).
        result = nil
        let fallback = SecItemCopyMatching(readQuery as CFDictionary, &result)
        guard fallback == errSecSuccess, let data = result as? Data else { return "" }
        let value = Self.cleaned(String(data: data, encoding: .utf8) ?? "")
        // Rewrite with open ACL so the next launch of a re-signed ad-hoc binary
        // does not re-prompt for the login keychain password.
        if !value.isEmpty {
            try? save(value)
        }
        return value
    }

    public func save(_ value: String) throws {
        let key = Self.cleaned(value)
        guard !key.isEmpty else {
            try delete()
            return
        }

        let data = Data(key.utf8)
        // Always delete + re-add so ACL/access is fresh. Update alone keeps the old
        // creator-code ACL, which re-prompts every time an ad-hoc signature changes.
        _ = SecItemDelete(matchQuery as CFDictionary)

        var attributes = addAttributes
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if let access = Self.openAccess() {
            attributes[kSecAttrAccess as String] = access
        }
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Self.keychainError(addStatus) }
    }

    public func delete() throws {
        let status = SecItemDelete(matchQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.keychainError(status)
        }
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

    /// Access list that does not bind the secret to one ad-hoc code signature.
    /// Local-dev rebuilds re-sign every time; a tight ACL causes login-keychain
    /// password prompts on every launch. Trade-off: any process that knows the
    /// service/account can read the item (acceptable for personal API keys).
    private static func openAccess() -> SecAccess? {
        var trusted: SecTrustedApplication?
        // NULL path = "any application" trusted entry.
        let status = SecTrustedApplicationCreateFromPath(nil, &trusted)
        guard status == errSecSuccess, let trusted else { return nil }
        var access: SecAccess?
        let list = [trusted] as CFArray
        let create = SecAccessCreate("WeiBei local credential" as CFString, list, &access)
        guard create == errSecSuccess else { return nil }
        return access
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return NSError(
            domain: "WeiBei.Keychain",
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

public enum OpenAIAPIKeyStore {
    public static let service = "com.changfenhuang.weibei.openai"
    /// Legacy single-account name kept for backward compatibility with openai keys.
    public static let account = "OPENAI_API_KEY"

    private static func store(forAccount account: String) -> KeychainPasswordStore {
        KeychainPasswordStore(service: service, account: account)
    }

    public static func accountName(forProvider provider: String) -> String {
        let cleaned = cleaned(provider).lowercased()
        if cleaned.isEmpty || cleaned == "openai" {
            return account
        }
        return "PROVIDER_KEY_\(cleaned)"
    }

    public static func cleaned(_ value: String) -> String {
        KeychainPasswordStore.cleaned(value)
    }

    public static func load(provider: String = "openai") -> String {
        let named = store(forAccount: accountName(forProvider: provider)).load()
        if !named.isEmpty { return named }
        // Fallback to legacy openai account for the default provider.
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
