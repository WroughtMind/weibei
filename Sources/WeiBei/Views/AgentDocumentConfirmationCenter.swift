import Foundation

/// Agent 创建文稿前的写盘确认中心。
/// 工具执行侧通过 `requestConfirmation` 挂起等待，主窗口浮层展示请求，
/// 用户确认或取消后恢复等待方。自包含类型，不进 WorkspaceStore。
@MainActor
final class AgentDocumentConfirmationCenter: ObservableObject {
    static let shared = AgentDocumentConfirmationCenter()

    struct PendingRequest: Identifiable {
        let id = UUID()
        let title: String
        let summary: String
        let continuation: CheckedContinuation<Bool, Never>
    }

    @Published private(set) var pendingRequest: PendingRequest?

    private init() {}

    func requestConfirmation(title: String, summary: String) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // 已有未决请求时先按取消恢复，保证每个 continuation 恰好恢复一次。
        if let stale = pendingRequest {
            stale.continuation.resume(returning: false)
        }
        return await withCheckedContinuation { continuation in
            pendingRequest = PendingRequest(
                title: trimmedTitle.isEmpty
                    ? "未命名文稿"
                    : trimmedTitle,
                summary: summary,
                continuation: continuation
            )
        }
    }

    func confirm() {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        request.continuation.resume(returning: true)
    }

    func cancel() {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        request.continuation.resume(returning: false)
    }
}
