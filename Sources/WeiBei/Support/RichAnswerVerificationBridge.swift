import Foundation
import SwiftUI

extension Notification.Name {
    static let weiBeiRichAnswerVerificationStage = Notification.Name("weiBeiRichAnswerVerificationStage")
}

enum RichAnswerVerificationStage: String {
    case overview
    case before
    case after
}

enum RichAnswerVerificationBridge {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1"
    }

    static func stage(from notification: Notification) -> RichAnswerVerificationStage? {
        guard isEnabled,
              let rawStage = notification.userInfo?["stage"] as? String else { return nil }
        return RichAnswerVerificationStage(rawValue: rawStage)
    }

    static func nextVerificationValue(
        current: Double,
        minimum: Double,
        maximum: Double,
        step: Double
    ) -> Double {
        guard minimum < maximum else { return current }
        let span = maximum - minimum
        let safeStep = step > 0 ? step : span / 8
        let target = current + max(safeStep, span * 0.28)
        if target <= maximum {
            return target
        }
        return minimum + span * 0.35
    }
}

private struct RichAnswerVerificationStageModifier: ViewModifier {
    var handler: (RichAnswerVerificationStage) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default
                .publisher(for: .weiBeiRichAnswerVerificationStage)
                .compactMap(RichAnswerVerificationBridge.stage(from:))
        ) { stage in
            handler(stage)
        }
    }
}

extension View {
    func onRichAnswerVerificationStage(
        _ handler: @escaping (RichAnswerVerificationStage) -> Void
    ) -> some View {
        modifier(RichAnswerVerificationStageModifier(handler: handler))
    }
}
