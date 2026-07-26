import Foundation
import LocalAuthentication
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

        let data = Data(key.utf8)
        let status = SecItemUpdate(matchQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }

        if status == errSecItemNotFound {
            var attributes = addAttributes
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Self.keychainError(addStatus) }
            return
        }

        throw Self.keychainError(status)
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
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Background startup reads must never trigger a password prompt loop for stale binary ACLs.
        query[kSecUseAuthenticationContext as String] = authenticationContext
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
