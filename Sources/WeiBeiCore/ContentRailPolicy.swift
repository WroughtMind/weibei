import Foundation

public enum ContentRailPresentation: Equatable, Sendable {
    case railOnly
    case content
}

public enum ContentRailPolicy {
    /// The rail is the pane's entire dormant surface, not an additional sidebar.
    public static let dormantWidth: CGFloat = 40
    /// At 190pt the 40pt rail plus a compact 140pt text preview and insets fit without overlap.
    public static let railOnlyThreshold: CGFloat = 190
    public static let snapThreshold: CGFloat = 190
    public static let readableWidth: CGFloat = 240
    public static let defaultReadableWidth: CGFloat = 420
    public static let previewMinimumWidth: CGFloat = 140
    public static let previewMaximumWidth: CGFloat = 360
    public static let previewImageMinimumWidth: CGFloat = 240

    public static func presentation(
        availableWidth: CGFloat,
        allowsRailOnly: Bool
    ) -> ContentRailPresentation {
        // Deliberately expose two stable states. Intermediate widths are drag-time geometry,
        // never a third persistent presentation callers need to understand.
        allowsRailOnly && availableWidth < railOnlyThreshold ? .railOnly : .content
    }

    public static func previewWidth(
        totalWidth: CGFloat,
        previewLeadingX: CGFloat,
        trailingInset: CGFloat = 8
    ) -> CGFloat? {
        let available = totalWidth - previewLeadingX - trailingInset
        guard available >= previewMinimumWidth else { return nil }
        return min(previewMaximumWidth, available)
    }
}
