import CoreGraphics
import Foundation

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

    /// Returns only a true append to the same conversation. Initial restore,
    /// session replacement, and deletion must refold to the newest page.
    public static func appendedMessageCount(
        previousMessageIDs: [UUID],
        currentMessageIDs: [UUID]
    ) -> Int? {
        guard !previousMessageIDs.isEmpty,
              currentMessageIDs.count > previousMessageIDs.count,
              currentMessageIDs.starts(with: previousMessageIDs) else { return nil }
        return currentMessageIDs.count - previousMessageIDs.count
    }
}
