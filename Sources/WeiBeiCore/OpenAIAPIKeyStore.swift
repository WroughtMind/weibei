import Foundation
import Security

public struct KeychainPasswordStore {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
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
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }

        if status == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Self.keychainError(addStatus) }
            return
        }

        throw Self.keychainError(status)
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
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
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
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
    public static let account = "OPENAI_API_KEY"

    private static var store: KeychainPasswordStore {
        KeychainPasswordStore(service: service, account: account)
    }

    public static func cleaned(_ value: String) -> String {
        KeychainPasswordStore.cleaned(value)
    }

    public static func load() -> String {
        store.load()
    }

    public static func save(_ value: String) throws {
        try store.save(value)
    }

    public static func delete() throws {
        try store.delete()
    }
}
