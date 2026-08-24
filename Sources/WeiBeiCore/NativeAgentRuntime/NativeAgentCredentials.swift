import Foundation

/// WeiBei-owned credential file (not the system keychain).
/// Permissions 0600, atomic replace, corrupt file rotated to `.bak`.
public struct NativeAgentCredentialRecord: Codable, Equatable, Sendable {
    public var provider: String
    public var apiKey: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var expiresAt: Date?
    public var accountID: String?
    public var boundEndpoint: String?

    public init(
        provider: String,
        apiKey: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        accountID: String? = nil,
        boundEndpoint: String? = nil
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
        self.boundEndpoint = boundEndpoint
    }
}

public struct NativeAgentCredentialStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore() throws -> NativeAgentCredentialStore {
        let directory = try WeiBeiAgentDataPaths.ensureNativeAgentDirectory()
        return NativeAgentCredentialStore(
            fileURL: directory.appendingPathComponent("credentials.json")
        )
    }

    public func load() throws -> [String: NativeAgentCredentialRecord] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([String: NativeAgentCredentialRecord].self, from: data)
        } catch {
            let backup = fileURL.appendingPathExtension("bak")
            if manager.fileExists(atPath: backup.path) {
                let data = try Data(contentsOf: backup)
                return try JSONDecoder().decode([String: NativeAgentCredentialRecord].self, from: data)
            }
            throw error
        }
    }

    public func save(_ records: [String: NativeAgentCredentialRecord]) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if manager.fileExists(atPath: fileURL.path) {
            let backup = fileURL.appendingPathExtension("bak")
            try? manager.removeItem(at: backup)
            try manager.copyItem(at: fileURL, to: backup)
        }
        let data = try JSONEncoder().encode(records)
        let temp = fileURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if manager.fileExists(atPath: fileURL.path) {
            try manager.removeItem(at: fileURL)
        }
        try manager.moveItem(at: temp, to: fileURL)
        try manager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func upsert(_ record: NativeAgentCredentialRecord) throws {
        var records = try load()
        records[record.provider] = record
        try save(records)
    }

    public func remove(provider: String) throws {
        var records = try load()
        records.removeValue(forKey: provider)
        try save(records)
        try scrubBackup(provider: provider)
    }

    public func scrubBackup(provider: String) throws {
        let backup = fileURL.appendingPathExtension("bak")
        let manager = FileManager.default
        guard manager.fileExists(atPath: backup.path) else { return }
        let records: [String: NativeAgentCredentialRecord]
        do {
            records = try JSONDecoder().decode(
                [String: NativeAgentCredentialRecord].self,
                from: Data(contentsOf: backup)
            )
        } catch {
            try manager.removeItem(at: backup)
            return
        }
        var next = records
        next.removeValue(forKey: provider)
        if next.isEmpty {
            try manager.removeItem(at: backup)
            return
        }
        if next == records { return }
        let data = try JSONEncoder().encode(next)
        try data.write(to: backup, options: .atomic)
        try manager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: backup.path
        )
    }

    public static func apiKey(forProviderID id: String) throws -> String? {
        let key = try defaultStore().load()[id]?.apiKey
        return key?.isEmpty == false ? key : nil
    }

    public func posixPermissions() throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let raw = attributes[.posixPermissions] as? NSNumber
        return raw?.intValue ?? 0
    }
}
