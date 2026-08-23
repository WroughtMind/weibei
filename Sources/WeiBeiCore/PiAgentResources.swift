import Foundation

/// Bundled agent resources shared by the native runtime.
/// The name predates the Pi retirement (2026-08) and is kept so existing
/// call sites stay untouched; it loads resources, never a Pi process.
public struct PiAgentResources: Sendable {
    public static let allRequiredSkillNames = ["visualize"]

    public var rootURL: URL
    public var skillsURL: URL
    public var systemPrompt: String

    public static func bundled() throws -> PiAgentResources {
        let bundleName = "WeiBei_WeiBeiCore.bundle"
        let packagedBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent(bundleName) }
            .flatMap(Bundle.init(url:))
        let legacyBundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent(bundleName))
        // Inside an assembled .app, touching Bundle.module when both packaged
        // candidates missed hits the Swift 6.2 accessor's fatalError ("could
        // not load resource bundle"). Degrade to the thrown error instead.
        // Bare dev executables keep the accessor — its compiled-in .build
        // fallback path is valid there by construction.
        if packagedBundle == nil, legacyBundle == nil, Bundle.main.bundleURL.pathExtension == "app" {
            throw NativeAgentResourcesError.missing(bundleName)
        }
        let resourceBundle = packagedBundle ?? legacyBundle ?? Bundle.module
        guard let rootURL = resourceBundle.url(forResource: "AgentResources", withExtension: nil) else {
            throw NativeAgentResourcesError.missing("AgentResources")
        }
        let skillsURL = rootURL.appendingPathComponent("skills", isDirectory: true)
        let systemURL = rootURL.appendingPathComponent("system.md")
        let hasRequiredSkills = allRequiredSkillNames.allSatisfy { skillName in
            FileManager.default.fileExists(
                atPath: skillsURL
                    .appendingPathComponent(skillName, isDirectory: true)
                    .appendingPathComponent("SKILL.md")
                    .path
            )
        }
        guard hasRequiredSkills,
              let systemPrompt = try? String(contentsOf: systemURL, encoding: .utf8),
              !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativeAgentResourcesError.missing(rootURL.path)
        }
        return PiAgentResources(
            rootURL: rootURL,
            skillsURL: skillsURL,
            systemPrompt: systemPrompt
        )
    }
}

public enum NativeAgentResourcesError: LocalizedError, Equatable {
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case let .missing(path):
            return "魏碑的 Agent 资源不完整：\(path)"
        }
    }
}
