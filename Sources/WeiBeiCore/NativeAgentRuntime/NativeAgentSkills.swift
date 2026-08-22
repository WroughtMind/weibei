import CryptoKit
import Foundation

public struct NativeSkillManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String
    public var modelInvocable: Bool
    public var userInvocable: Bool
    public var tools: [String]
    public var jscHook: String?

    public init(
        id: String,
        name: String,
        version: String,
        description: String,
        modelInvocable: Bool = true,
        userInvocable: Bool = true,
        tools: [String] = [],
        jscHook: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.modelInvocable = modelInvocable
        self.userInvocable = userInvocable
        self.tools = tools
        self.jscHook = jscHook
    }
}

public struct NativeSkillPack: Equatable, Sendable {
    public var manifest: NativeSkillManifest
    public var body: String
    public var relativePath: String
    public var sha256: String

    public var id: String { manifest.id }
    public var byteCount: Int { body.utf8.count }

    public func asLoadedSkill(contextRevision: String) -> StudyAgentLoadedSkill {
        StudyAgentLoadedSkill(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            sha256: sha256,
            byteCount: byteCount,
            relativePath: relativePath,
            loadedAtContextRevision: contextRevision
        )
    }
}

public struct NativeSkillRegistry: Sendable {
    public var packs: [NativeSkillPack]

    public init(packs: [NativeSkillPack] = []) {
        self.packs = packs
    }

    public static func load(from root: URL) throws -> NativeSkillRegistry {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return NativeSkillRegistry() }
        let children = try manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var packs: [NativeSkillPack] = []
        for directory in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if let pack = try? loadPack(at: directory, root: root) {
                packs.append(pack)
            }
        }
        return NativeSkillRegistry(packs: packs)
    }

    public func catalogSummary() -> String {
        guard !packs.isEmpty else { return "" }
        let lines = packs.map { pack in
            "- \(pack.manifest.id): \(pack.manifest.description)"
        }
        return """
        技能目录（只注入摘要；需要正文时调用 load_skill。加载是纯指令注入，不改变工具注册）：
        \(lines.joined(separator: "\n"))
        """
    }

    public func pack(named raw: String) -> NativeSkillPack? {
        let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = packs.first(where: { $0.id == needle || $0.relativePath == needle }) {
            return exact
        }
        if needle.hasPrefix("skill://") {
            let id = String(needle.dropFirst("skill://".count))
            return packs.first { $0.id == id }
        }
        return packs.first { needle.contains("/skills/\($0.id)/SKILL.md") }
    }

    public static func isSignedBuiltin(_ id: String) -> Bool {
        ["visualize", "socratic-questioning"].contains(id)
    }

    private static func loadPack(at directory: URL, root: URL) throws -> NativeSkillPack {
        let skillURL = directory.appendingPathComponent("SKILL.md")
        let body = try String(contentsOf: skillURL, encoding: .utf8)
        let digest = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
        let relative = "skills/\(directory.lastPathComponent)/SKILL.md"
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let manifest: NativeSkillManifest
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            manifest = try JSONDecoder().decode(NativeSkillManifest.self, from: Data(contentsOf: manifestURL))
        } else {
            manifest = NativeSkillManifest(
                id: directory.lastPathComponent,
                name: directory.lastPathComponent,
                version: "1.0.0",
                description: frontmatterDescription(in: body) ?? directory.lastPathComponent
            )
        }
        _ = root
        return NativeSkillPack(manifest: manifest, body: body, relativePath: relative, sha256: digest)
    }

    private static func frontmatterDescription(in body: String) -> String? {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---" else { return nil }
        for line in lines.dropFirst() {
            if line == "---" { break }
            if line.hasPrefix("description:") {
                return line.replacingOccurrences(of: "description:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }
}
