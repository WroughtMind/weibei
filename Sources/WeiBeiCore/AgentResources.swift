import Foundation

/// Bundled system prompt and skills shared by the native runtime.
public struct AgentResources: Sendable {
    public static let requiredSkillIDs = [
        "genui", "genui-advanced", "socratic-questioning",
        "web-research", "web-reading", "course-search", "close-reading",
        "source-synthesis", "note-writing", "discussion-recall", "learning-memory", "practice-feedback",
    ]

    public var rootURL: URL
    public var skillsURL: URL
    public var systemPrompt: String

    public static func bundled() throws -> AgentResources {
#if targetEnvironment(macCatalyst)
        let resourceBundle = Bundle.main
#else
        let resourceBundle = Bundle.module
#endif
        guard let rootURL = resourceBundle.url(forResource: "AgentResources", withExtension: nil) else {
            throw NativeAgentResourcesError.incomplete(resource: "agent_resources", cause: "missing")
        }
        let skillsURL = rootURL.appendingPathComponent("skills", isDirectory: true)
        let systemURL = rootURL.appendingPathComponent("system.md")
        for skillName in requiredSkillIDs {
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
