import CoreGraphics
import Foundation

public enum WeiBeiInterfaceLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }

    public var settingsLabel: String {
        switch self {
        case .chinese:
            return "中文界面"
        case .english:
            return "English interface"
        }
    }

    public func text(_ chinese: String, _ english: String) -> String {
        switch self {
        case .chinese:
            return chinese
        case .english:
            return english
        }
    }
}

public enum StudyItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case html
    case pdf
    case markdown
    case text

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .html:
            return "HTML"
        case .pdf:
            return "PDF"
        case .markdown:
            return "Markdown"
        case .text:
            return language.text("文本", "Text")
        }
    }

    public var systemImage: String {
        switch self {
        case .html: "globe"
        case .pdf: "doc.richtext"
        case .markdown: "note.text"
        case .text: "doc.text"
        }
    }

    public static func detect(from url: URL) -> StudyItemKind {
        switch url.pathExtension.lowercased() {
        case "html", "htm":
            return .html
        case "pdf":
            return .pdf
        case "md", "markdown":
            return .markdown
        default:
            return .text
        }
    }

}

public enum PaneFocus: String, Codable, Hashable {
    case library
    case reader
    case notes
    case agent
}

public enum WorkspacePaneRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case reader
    case agent
    case notes

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .reader:
            return language.text("文档", "Document")
        case .agent:
            return language.text("对话", "Chat")
        case .notes:
            return language.text("笔记", "Notes")
        }
    }

    public func shortLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .reader:
            return language.text("文", "Doc")
        case .agent:
            return language.text("对", "Chat")
        case .notes:
            return language.text("笔", "Notes")
        }
    }

    public var focus: PaneFocus {
        switch self {
        case .reader:
            return .reader
        case .agent:
            return .agent
        case .notes:
            return .notes
        }
    }

    public var systemImage: String {
        switch self {
        case .reader:
            return "doc.text.magnifyingglass"
        case .agent:
            return "bubble.left.and.text.bubble.right"
        case .notes:
            return "square.and.pencil"
        }
    }

    public static var defaultThreePaneOrder: [WorkspacePaneRole] {
        [.reader, .agent, .notes]
    }

    public static func normalized(_ roles: [WorkspacePaneRole]) -> [WorkspacePaneRole] {
        var ordered: [WorkspacePaneRole] = []
        for role in roles where !ordered.contains(role) {
            ordered.append(role)
        }
        for role in WorkspacePaneRole.defaultThreePaneOrder where !ordered.contains(role) {
            ordered.append(role)
        }
        return Array(ordered.prefix(3))
    }
}

public enum ThreePaneReorderTargeting {
    public static func targetIndex(
        order rawOrder: [WorkspacePaneRole],
        frames: [WorkspacePaneRole: CGRect],
        role: WorkspacePaneRole,
        horizontalDelta: CGFloat
    ) -> Int? {
        let order = WorkspacePaneRole.normalized(rawOrder)
        guard let currentIndex = order.firstIndex(of: role),
              let sourceFrame = frames[role] else { return nil }
        let draggedFrame = sourceFrame.offsetBy(dx: horizontalDelta, dy: 0)
        let draggedCenterX = draggedFrame.midX

        let overlapTarget = order.enumerated().compactMap { offset, role -> (offset: Int, overlap: CGFloat, distance: CGFloat)? in
            guard let frame = frames[role] else { return nil }
            let overlap = horizontalOverlap(draggedFrame, frame)
            guard overlap > 0.5 else { return nil }
            return (offset, overlap, abs(frame.midX - draggedCenterX))
        }
        .max { left, right in
            if abs(left.overlap - right.overlap) > 0.5 {
                return left.overlap < right.overlap
            }
            return left.distance > right.distance
        }?.offset

        let targetIndex = overlapTarget ?? order.enumerated().compactMap { offset, role -> (offset: Int, distance: CGFloat)? in
            guard let frame = frames[role] else { return nil }
            return (offset, abs(frame.midX - draggedCenterX))
        }
        .min { $0.distance < $1.distance }?.offset

        return targetIndex == currentIndex ? nil : targetIndex
    }

    private static func horizontalOverlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        Swift.max(0, Swift.min(lhs.maxX, rhs.maxX) - Swift.max(lhs.minX, rhs.minX))
    }
}
