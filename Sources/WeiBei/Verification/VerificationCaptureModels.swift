import CoreGraphics
import Foundation

/**
 * 描述验证进程写入捕获通道的截图请求。
 */
struct VerificationCaptureRequest: Decodable {
    var id: String
    var capturePath: String
    var stage: String?
}

/**
 * 描述一次真实窗口截图的文件证据与捕获前后状态。
 */
struct VerificationCaptureResult {
    var pngPath: String
    var bytes: Int
    var sha256: String
    var capturedAt: String
    var webViewSnapshotCount: Int
    var workspaceStateAtStart: VerificationWorkspaceState
    var workspaceStateAtEnd: VerificationWorkspaceState
}

/**
 * 记录截图瞬间工作区的可见 pane 与布局状态，用于拒绝不稳定截图。
 */
struct VerificationWorkspaceState: Equatable {
    var layout: String
    var showReader: Bool
    var showAgent: Bool
    var showNotes: Bool
    var selectedItemID: String?
    var visiblePanes: [String]
    var paneFrames: [String: CGRect]

    var payload: [String: Any] {
        [
            "layout": layout,
            "showReader": showReader,
            "showAgent": showAgent,
            "showNotes": showNotes,
            "selectedItemID": selectedItemID ?? NSNull(),
            "visiblePanes": visiblePanes,
            "paneFrames": paneFrames.mapValues { frame in
                [
                    "x": frame.minX,
                    "y": frame.minY,
                    "width": frame.width,
                    "height": frame.height,
                ]
            },
        ]
    }

    var diagnosticDescription: String {
        "layout=\(layout),reader=\(showReader),agent=\(showAgent),notes=\(showNotes),visible=\(visiblePanes.joined(separator: ",")),selected=\(selectedItemID ?? "none")"
    }
}

enum SingleCaptureReadinessResult {
    case ready
    case failed(String)
}

struct CompactPreviewReadiness {
    var compactCount: Int
    var pendingCount: Int
    var evaluationFailureCount: Int
    var measuredHeights: [Int]

    var isReady: Bool {
        pendingCount == 0 && evaluationFailureCount == 0
    }

    /**
     * 判断连续两次 Web 预览测量是否稳定，避免捕获布局变化中的画面。
     */
    func isStable(comparedTo previous: CompactPreviewReadiness) -> Bool {
        isReady
            && previous.isReady
            && compactCount == previous.compactCount
            && measuredHeights == previous.measuredHeights
    }
}
