import Combine

/// Editing state can outlive a recycled message row; saving still uses WorkspaceStore.
@MainActor
final class AgentReplyActionDraft: ObservableObject {
    @Published var title: String
    @Published var bodyText: String
    @Published var isWorking = false
    init(title: String, bodyText: String) {
        self.title = title
        self.bodyText = bodyText
    }
}
