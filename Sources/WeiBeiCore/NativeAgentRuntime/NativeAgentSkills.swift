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
    var directoryURL: URL?

    public var id: String { manifest.id }
    public var byteCount: Int { body.utf8.count }

    /// Only bundled Markdown references inside this skill can be disclosed.
    /// Resource text is read on demand, never added to the catalog or entrypoint.
    public func reference(named path: String) throws -> NativeSkillPack {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let directoryURL,
              components.count >= 2, components.first == "references",
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\\"), !path.contains("\0"), path.hasSuffix(".md") else {
            throw NativeLLMFailure(code: "skill_resource_invalid", message: "只能读取该技能 references 目录内的 Markdown 指引")
        }
        let root = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let url = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(root.appendingPathComponent("references").path + "/") else {
            throw NativeLLMFailure(code: "skill_resource_invalid", message: "参考指引不能越出该技能的 references 目录")
        }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativeLLMFailure(code: "skill_resource_missing", message: "未找到可读取的技能参考指引：\(path)")
        }
        var resourceManifest = manifest
        resourceManifest.id = "\(id)/\(path)"
        let title = text.split(separator: "\n").first(where: { $0.hasPrefix("# ") })
            .map { String($0.dropFirst(2)) } ?? "参考指引"
        resourceManifest.name = "\(manifest.name) · \(title)"
        return NativeSkillPack(
            manifest: resourceManifest, body: text,
            relativePath: "skills/\(id)/\(path)",
            sha256: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

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
        guard manager.fileExists(atPath: root.path) else {
            throw NativeAgentResourcesError.incomplete(resource: "skills", cause: "missing")
        }
        let children: [URL]
        do {
            children = try manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw NativeAgentResourcesError.incomplete(
                resource: "skills",
                cause: WeiBeiLog.code(error)
            )
        }
        var packs: [NativeSkillPack] = []
        for directory in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            do {
                packs.append(try loadPack(at: directory, root: root))
            } catch {
                let resource = "skill:\(directory.lastPathComponent)"
                throw NativeAgentResourcesError.incomplete(
                    resource: resource,
                    cause: WeiBeiLog.code(error)
                )
            }
        }
        let loadedIDs = Set(packs.map(\.id))
        guard let missingID = AgentResources.requiredSkillIDs.first(where: { !loadedIDs.contains($0) }) else {
            return NativeSkillRegistry(packs: packs)
        }
        throw NativeAgentResourcesError.incomplete(resource: "skill:\(missingID)", cause: "missing")
    }

    public func catalogSummary() -> String {
        guard !packs.isEmpty else { return "" }
        let lines = packs.map { pack in
            "- \(pack.manifest.id): \(pack.manifest.description)"
        }
        return """
        技能目录（这里只提供用途摘要。匹配任务先用 load_skill(id) 读取核心流程；流程指向的场景细节再用 load_skill(id, resource: "references/文件名.md") 按需读取。不要一次加载全部技能或参考文件；加载不改变工具权限）：
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
        AgentResources.requiredSkillIDs.contains(id)
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
        return NativeSkillPack(manifest: manifest, body: body, relativePath: relative, sha256: digest, directoryURL: directory)
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
