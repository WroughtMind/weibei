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

    public init(
        provider: String,
        apiKey: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        accountID: String? = nil
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
    }
}

public struct NativeAgentCredentialStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore() throws -> NativeAgentCredentialStore {
        let directory = try WeiBeiAgentDataPaths.ensurePiAgentDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent("NativeAgent", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
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
    }

    public func posixPermissions() throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let raw = attributes[.posixPermissions] as? NSNumber
        return raw?.intValue ?? 0
    }
}
