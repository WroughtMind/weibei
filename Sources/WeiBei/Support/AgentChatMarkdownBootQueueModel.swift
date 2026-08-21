import Combine
import Foundation
import WeiBeiCore

/// SwiftUI observation shim over the shared Chat markdown boot queue.
/// WeiBeiCore stays Combine-free; this adapter republishes admissions so
/// pending rows re-render the moment their slot is granted.
@MainActor
final class AgentChatMarkdownBootQueueModel: ObservableObject {
    static let shared = AgentChatMarkdownBootQueueModel()

    let queue: AgentChatMarkdownBootQueue
    @Published private(set) var admittedIDs: Set<UUID>

    init(queue: AgentChatMarkdownBootQueue = .shared) {
        self.queue = queue
        self.admittedIDs = queue.admittedIDs
        queue.setAdmissionObserver { [weak self] ids in
            self?.admittedIDs = ids
        }
    }
}
