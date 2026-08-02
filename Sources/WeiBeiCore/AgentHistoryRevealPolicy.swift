import CoreGraphics

public enum AgentHistoryRevealPolicy {
    public static let pageSize = 30
    public static let topRevealThreshold: CGFloat = 10

    public static func shouldRevealEarlierPage(
        distanceFromTop: CGFloat,
        isUserScrolling: Bool,
        isScrollingTowardTop: Bool,
        hiddenMessageCount: Int,
        revealInFlight: Bool
    ) -> Bool {
        isUserScrolling
            && isScrollingTowardTop
            && distanceFromTop < topRevealThreshold
            && hiddenMessageCount > 0
            && !revealInFlight
    }

    public static func shouldReleaseRevealLock(isUserScrolling: Bool) -> Bool {
        !isUserScrolling
    }

    public static func expandedVisibleLimit(currentLimit: Int, totalMessageCount: Int) -> Int {
        min(max(currentLimit, 0) + pageSize, max(totalMessageCount, 0))
    }
}
