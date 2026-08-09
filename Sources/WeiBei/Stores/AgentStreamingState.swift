import Combine

@MainActor
final class AgentStreamingState: ObservableObject {
    @Published var text = ""
    @Published var activityText: String?
}
