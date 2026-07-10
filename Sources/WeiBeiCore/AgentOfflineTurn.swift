import Foundation

public enum AgentOfflineTurn {
    public static func messages(
        question: String,
        sourceTitle: String?,
        input: AgentOfflinePreviewInput
    ) -> [AgentMessage] {
        [
            AgentMessage(role: .user, text: question, source: sourceTitle),
            AgentMessage(
                role: .assistant,
                text: AgentOfflinePreview.render(input),
                source: sourceTitle ?? input.language.text("离线模式", "Offline mode"),
                backend: .offline
            )
        ]
    }
}
