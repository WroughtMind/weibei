import Foundation

public enum ContentRailPresentation: Equatable, Sendable {
    case railOnly
    case content
}

public enum ContentRailPolicy {
    /// The rail is the pane's entire dormant surface, not an additional sidebar.
    public static let dormantWidth: CGFloat = 40
    /// A short end-stop makes the dormant state discoverable without hijacking useful narrow widths.
    public static let magneticSnapDistance: CGFloat = 12
    public static let railOnlyThreshold: CGFloat = dormantWidth + magneticSnapDistance
    public static let snapThreshold: CGFloat = railOnlyThreshold
    public static let readableWidth: CGFloat = 240
    public static let defaultReadableWidth: CGFloat = 420
    public static let previewMinimumWidth: CGFloat = 140
    public static let previewMaximumWidth: CGFloat = 360
    public static let dormantPreviewWidth: CGFloat = 280
    public static let previewImageMinimumWidth: CGFloat = 240

    public static func presentation(
        availableWidth: CGFloat,
        allowsRailOnly: Bool
    ) -> ContentRailPresentation {
        allowsRailOnly && availableWidth <= railOnlyThreshold ? .railOnly : .content
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
