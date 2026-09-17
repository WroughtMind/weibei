import Foundation

public enum ContentRailPresentation: Equatable, Sendable {
    case railOnly
    case content
}

public enum ContentRailPolicy {
    /// The rail is the pane's entire dormant surface, not an additional sidebar.
    public static let dormantWidth: CGFloat = 28
    /// A short end-stop makes the dormant state discoverable without hijacking useful narrow widths.
    public static let magneticSnapDistance: CGFloat = 10
    public static let railOnlyThreshold: CGFloat = dormantWidth + magneticSnapDistance
    public static let snapThreshold: CGFloat = railOnlyThreshold
    public static let readableWidth: CGFloat = 240
    public static let defaultReadableWidth: CGFloat = 420
    public static let expansionMinimumWidth: CGFloat = 300
    public static let expansionPreferredWidth: CGFloat = 340
    public static let expansionMaximumWidth: CGFloat = 380
    public static let previewMinimumWidth: CGFloat = 140
    public static let previewMaximumWidth: CGFloat = 360
    public static let dormantPreviewWidth: CGFloat = 280
    public static let previewImageMinimumWidth: CGFloat = 240

    /// Only the two panes touching the dragged divider participate.
    public static func dividerWidths(
        _ widths: [CGFloat], divider: Int, equalize: Bool = false, skipSnap: Bool = false
    ) -> [CGFloat] {
        guard !skipSnap, widths.indices.contains(divider),
              widths.indices.contains(divider + 1) else { return widths }
        let left = widths[divider], right = widths[divider + 1]
        let total = left + right
        guard left.isFinite, right.isFinite, left >= 0, right >= 0, total > 0 else { return widths }
        let target: CGFloat
        if equalize {
            target = total / 2
        } else if left <= snapThreshold {
            target = min(dormantWidth, left)
        } else if right <= snapThreshold {
            target = total - min(dormantWidth, right)
        } else {
            let candidates: [CGFloat] = [0.25, 0.5, 0.75]
            guard let nearest = candidates.map({ total * $0 })
                .filter({ $0 >= readableWidth && total - $0 >= readableWidth })
                .min(by: { abs($0 - left) < abs($1 - left) }),
                abs(nearest - left) <= magneticSnapDistance else { return widths }
            target = nearest
        }
        var result = widths
        result[divider] = target
        result[divider + 1] = total - target
        return result
    }

    public static func presentation(
        availableWidth: CGFloat,
        allowsRailOnly: Bool
    ) -> ContentRailPresentation {
        allowsRailOnly && availableWidth <= railOnlyThreshold ? .railOnly : .content
    }

    public static func expansionWidth(recentWidth: CGFloat?) -> CGFloat {
        min(
            expansionMaximumWidth,
            max(expansionMinimumWidth, recentWidth ?? expansionPreferredWidth)
        )
    }

    public static func previewWidth(
        totalWidth: CGFloat,
        previewLeadingX: CGFloat,
        trailingInset: CGFloat = 8,
        isRailOnly: Bool = false
    ) -> CGFloat? {
        if isRailOnly {
            return dormantPreviewWidth
        }
        let available = totalWidth - previewLeadingX - trailingInset
        guard available >= previewMinimumWidth else { return nil }
        return min(previewMaximumWidth, available)
    }
}
