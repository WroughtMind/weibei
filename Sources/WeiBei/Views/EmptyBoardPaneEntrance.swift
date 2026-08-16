import CoreGraphics
import Foundation
import WeiBeiCore

/// First pane opened from the empty board should enter from its seat:
/// 文稿 from the left, 对话 from the center, 笔记 from the right.
enum EmptyBoardPaneEntrance {
    static func openingFrame(
        for role: WorkspacePaneRole,
        target: CGRect,
        fromEmptyBoard: Bool
    ) -> CGRect {
        let height = target.height
        guard fromEmptyBoard else {
            return CGRect(x: target.minX, y: target.minY, width: 0, height: height)
        }
        switch role {
        case .reader:
            return CGRect(x: target.minX, y: target.minY, width: 0, height: height)
        case .agent:
            return CGRect(x: target.midX, y: target.minY, width: 0, height: height)
        case .notes:
            return CGRect(x: target.maxX, y: target.minY, width: 0, height: height)
        }
    }
}
