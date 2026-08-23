import Foundation

/// Bundled system prompt and skills shared by the native runtime.
public struct AgentResources: Sendable {
    public static let allRequiredSkillNames = ["visualize", "socratic-questioning"]

    public var rootURL: URL
    public var skillsURL: URL
    public var systemPrompt: String

    public static func bundled() throws -> AgentResources {
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
            throw NativeAgentResourcesError.incomplete(resource: "bundle", cause: "missing")
        }
        let resourceBundle = packagedBundle ?? legacyBundle ?? Bundle.module
        guard let rootURL = resourceBundle.url(forResource: "AgentResources", withExtension: nil) else {
            throw NativeAgentResourcesError.incomplete(resource: "agent_resources", cause: "missing")
        }
        let skillsURL = rootURL.appendingPathComponent("skills", isDirectory: true)
        let systemURL = rootURL.appendingPathComponent("system.md")
        for skillName in allRequiredSkillNames {
            let skillURL = skillsURL
                .appendingPathComponent(skillName, isDirectory: true)
                .appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillURL.path) else {
                throw NativeAgentResourcesError.incomplete(
                    resource: "skill:\(skillName)",
                    cause: "missing"
                )
            }
        }
        let systemPrompt: String
        do {
            systemPrompt = try String(contentsOf: systemURL, encoding: .utf8)
        } catch {
            throw NativeAgentResourcesError.incomplete(
                resource: "system_prompt",
                cause: WeiBeiLog.code(error)
            )
        }
        guard !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativeAgentResourcesError.incomplete(resource: "system_prompt", cause: "empty")
        }
        return AgentResources(
            rootURL: rootURL,
            skillsURL: skillsURL,
            systemPrompt: systemPrompt
        )
    }
}

public enum NativeAgentResourcesError: LocalizedError, Equatable {
    public static let agentComponentsIncompleteMessage = "Agent 组件不完整，无法启动；请修复或重装魏碑"

    case missing(String)

    static func incomplete(resource: String, cause: String) -> NativeAgentResourcesError {
        WeiBeiLog.workspace.error(
            "agent_resource_load_failed code=agent_components_incomplete resource=\(resource, privacy: .public) cause=\(cause, privacy: .public)"
        )
        return .missing(resource)
    }

    public var errorDescription: String? {
        switch self {
        case .missing:
            return Self.agentComponentsIncompleteMessage
        }
    }
}
