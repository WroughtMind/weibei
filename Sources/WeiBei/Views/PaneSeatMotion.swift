import CoreGraphics
import Foundation
import WeiBeiCore

/// Each document pane enters and leaves from its own seat:
/// 文稿 from the left edge, 对话 from the column mid-line, 笔记 from the right edge.
enum PaneSeatMotion {
    static func openingFrame(for role: WorkspacePaneRole, target: CGRect) -> CGRect {
        collapsed(for: role, in: target)
    }

    static func closingFrame(
        for role: WorkspacePaneRole,
        current: CGRect?,
        container: CGRect
    ) -> CGRect {
        let source: CGRect
        if let current, current.width > 0.5, current.height > 0.5 {
            source = current
        } else {
            source = container
        }
        return collapsed(for: role, in: source)
    }

    static func collapsed(for role: WorkspacePaneRole, in rect: CGRect) -> CGRect {
        switch role {
        case .reader:
            return CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height)
        case .agent:
            return CGRect(x: rect.midX, y: rect.minY, width: 0, height: rect.height)
        case .notes:
            return CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height)
        }
    }
}
