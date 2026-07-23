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
    static let actionReceiptFileName = "rich-answer-action-receipt.json"

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
        var target = current + max(safeStep, span * 0.28)
        if target > maximum {
            target = minimum
        }
        guard step > 0 else { return target }
        let snapped = minimum + ((target - minimum) / step).rounded() * step
        let bounded = min(maximum, max(minimum, snapped))
        if abs(bounded - current) > 0.000_001 {
            return bounded
        }
        return current < maximum
            ? min(maximum, current + step)
            : minimum
    }

    static func writeInteractionReceipt(
        sceneID: String,
        sceneTitle: String,
        target: [String: Any],
        kind: String,
        before: Any?,
        after: Any?,
        changed: Bool,
        source: String = "app"
    ) {
        guard isEnabled,
              changed,
              let workspaceDirectory = ProcessInfo.processInfo.environment["WEIBEI_WORKSPACE_DIR"],
              !workspaceDirectory.isEmpty else { return }

        let environment = ProcessInfo.processInfo.environment
        let receipt: [String: Any] = [
            "schemaVersion": 1,
            "source": source,
            "stage": RichAnswerVerificationStage.after.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "case": [
                "id": environment["WEIBEI_VERIFY_CASE_ID"] ?? "",
                "kind": environment["WEIBEI_VERIFY_CASE_KIND"] ?? "",
                "recordPath": environment["WEIBEI_VERIFY_RECORD_PATH"] ?? "",
            ],
            "scene": [
                "id": sceneID,
                "title": sceneTitle,
            ],
            "target": sanitizedJSONValue(target),
            "kind": kind,
            "before": sanitizedJSONValue(before ?? NSNull()),
            "after": sanitizedJSONValue(after ?? NSNull()),
            "changed": changed,
        ]
        guard JSONSerialization.isValidJSONObject(receipt),
              let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]) else { return }

        let baseURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
        let receiptURL = baseURL.appendingPathComponent(actionReceiptFileName)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try? data.write(to: receiptURL, options: [.atomic])
    }

    static func changed(_ before: Any?, _ after: Any?) -> Bool {
        canonicalString(for: sanitizedJSONValue(before ?? NSNull()))
            != canonicalString(for: sanitizedJSONValue(after ?? NSNull()))
    }

    static func sanitizedJSONValue(_ value: Any) -> Any {
        switch value {
        case is NSNull:
            return NSNull()
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number
        case let int as Int:
            return int
        case let double as Double:
            if double.isFinite {
                return double
            }
            return String(describing: double)
        case let float as Float:
            if float.isFinite {
                return float
            }
            return String(describing: float)
        case let dictionary as [String: Any]:
            return Dictionary(
                uniqueKeysWithValues: dictionary.map { key, value in
                    (key, sanitizedJSONValue(value))
                }
            )
        case let array as [Any]:
            return array.map(sanitizedJSONValue)
        case let set as Set<String>:
            return Array(set).sorted()
        default:
            return String(describing: value)
        }
    }

    private static func canonicalString(for value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(["value": value]),
              let data = try? JSONSerialization.data(withJSONObject: ["value": value], options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
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
