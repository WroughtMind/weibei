import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

extension AgentPaneView {
    func scrollAgentToBottom(_ proxy: ScrollViewProxy) {
        guard agentFollowsLatest else { return }
        DispatchQueue.main.async {
            withAnimation(WeiBeiMotion.panel) {
                proxy.scrollTo(agentBottomAnchorID, anchor: .bottom)
            }
        }
    }

    func handleRichAnswerVerificationStage(
        _ stage: RichAnswerVerificationStage,
        proxy: ScrollViewProxy
    ) {
        guard stage == .overview || stage == .before || stage == .after,
              let target = latestRichAnswerVerificationTarget else { return }
        agentFollowsLatest = false
        let capturesMessageBottom = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_RICH_ANSWER_CAPTURE_ANCHOR"] == "bottom"
        DispatchQueue.main.async {
            if capturesMessageBottom {
                proxy.scrollTo(target.messageID, anchor: .bottom)
            } else {
                proxy.scrollTo(target.sceneAnchorID, anchor: .top)
            }
        }
    }

    var latestRichAnswerVerificationTarget: (messageID: UUID, sceneAnchorID: String)? {
        for message in store.messages.reversed() {
            guard let richAnswer = message.richAnswer,
                  richAnswer.mode == .rich,
                  !richAnswer.scenes.isEmpty else { continue }
            for (index, part) in richAnswer.resolvedParts.enumerated() {
                guard case .scene = part.kind,
                      let sceneID = part.sceneID else { continue }
                return (
                    message.id,
                    "rich-answer-\(message.id.uuidString)-\(sceneID)-\(index)"
                )
            }
        }
        return nil
    }

}
