import CoreGraphics
import Foundation
import WeiBeiCore

/// Offscreen chat WebView unload. Default **on**: missing UserDefaults key
/// enables it; an explicit false keeps the old Eager VStack.
enum AgentChatOffscreenUnloadFlag {
    static let defaultsKey = "weibei.chat.unloadOffscreenWebViews"
    private static var testingOverride: Bool?

    /// Missing key is on. Users who turned it off stay off.
    static var isEnabled: Bool {
        if let testingOverride { return testingOverride }
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func resetForTesting() {
        testingOverride = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    static func setEnabledForTesting(_ enabled: Bool?) {
        testingOverride = enabled
    }
}

enum AgentMessageViewportWindow {
    /// Screens of slack above and below the viewport before a cached row may
    /// drop its WKWebView. Large on purpose: remount must finish before the
    /// row is on screen, unlike LazyVStack recycle at the clip edge.
    static let extraScreens = 3

    /// Indices whose cached rows sit more than `extraScreens` outside the
    /// viewport. `nil` heights are never placeholders — unloading them would
    /// collapse the document.
    static func placeholderIndices(
        heights: [CGFloat?],
        viewportMinY: CGFloat,
        viewportHeight: CGFloat,
        extraScreens: Int = extraScreens,
        spacing: CGFloat = 0
    ) -> Set<Int> {
        guard viewportHeight > 1, extraScreens >= 0, !heights.isEmpty else {
            return []
        }
        let keepMin = viewportMinY - CGFloat(extraScreens) * viewportHeight
        let keepMax = viewportMinY + viewportHeight + CGFloat(extraScreens) * viewportHeight
        var y: CGFloat = 0
        var placeholders = Set<Int>()
        for (index, height) in heights.enumerated() {
            if let height, height > 0 {
                let rowMin = y
                let rowMax = y + height
                if rowMax <= keepMin || rowMin >= keepMax {
                    placeholders.insert(index)
                }
                y = rowMax + spacing
            } else {
                y += spacing
            }
        }
        return placeholders
    }

    static func placeholderIDs(
        enabled: Bool,
        messages: [AgentMessage],
        layoutWidth: CGFloat,
        wideTypography: Bool,
        viewportMinY: CGFloat,
        viewportHeight: CGFloat,
        extraScreens: Int = extraScreens,
        spacing: CGFloat = 0
    ) -> Set<UUID> {
        guard enabled else { return [] }
        let heights = cachedHeights(
            messages: messages,
            layoutWidth: layoutWidth,
            wideTypography: wideTypography
        )
        let indices = placeholderIndices(
            heights: heights,
            viewportMinY: viewportMinY,
            viewportHeight: viewportHeight,
            extraScreens: extraScreens,
            spacing: spacing
        )
        return Set(indices.map { messages[$0].id })
    }

    static func cachedHeights(
        messages: [AgentMessage],
        layoutWidth: CGFloat,
        wideTypography: Bool
    ) -> [CGFloat?] {
        messages.map {
            cachedHeight(message: $0, layoutWidth: layoutWidth, wideTypography: wideTypography)
        }
    }

    static func cachedHeight(
        message: AgentMessage,
        layoutWidth: CGFloat,
        wideTypography: Bool
    ) -> CGFloat? {
        guard canUnload(message) else { return nil }
        let prepared = AgentChatKaTeXMarkdown.prepare(message.text)
        let bucket = AgentFinalizedMarkdownHeightCache.widthBucket(layoutWidth)
        if let height = AgentFinalizedMarkdownHeightCache.height(
            for: AgentFinalizedMarkdownHeightCache.cacheKey(
                messageID: message.id,
                text: prepared,
                widthBucket: bucket,
                wideTypography: wideTypography
            )
        ) {
            return height
        }
        guard prepared != message.text else { return nil }
        return AgentFinalizedMarkdownHeightCache.height(
            for: AgentFinalizedMarkdownHeightCache.cacheKey(
                messageID: message.id,
                text: message.text,
                widthBucket: bucket,
                wideTypography: wideTypography
            )
        )
    }

    /// Only finalized, cacheable assistant markdown rows. User chips, streaming,
    /// failures, citations, and GenUI blocks are not in the height cache as a
    /// full row, so unloading them would collapse or clip.
    static func canUnload(_ message: AgentMessage) -> Bool {
        message.role == .assistant
            && message.completionState == .completed
            && message.failureKind == nil
            && message.sources.isEmpty
            && message.contentBlocks.allSatisfy { block in
                if case .text = block { return true }
                return false
            }
    }
}
