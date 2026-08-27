import SwiftUI

/// Height-only stand-in for a chat row whose WKWebView was unmounted because it
/// is more than N screens from the viewport. Deliberately content-free: a
/// native-text preview never matches Milkdown typography, and that mismatch
/// read as a glitch. Remount reuses the row's existing skeleton + fade.
struct AgentMessagePlaceholderRow: View {
    var height: CGFloat

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: max(height, 1))
            .accessibilityHidden(true)
    }
}

/// Keeps Eager VStack identity. Far rows skip `content` so no WKWebView is
/// created; nearby rows mount the real bubble (skeleton + fade on cold start).
struct AgentMessageViewportGatedRow<Content: View>: View {
    var isPlaceholder: Bool
    var placeholderHeight: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isPlaceholder, let placeholderHeight, placeholderHeight > 0 {
            AgentMessagePlaceholderRow(height: placeholderHeight)
        } else {
            content()
        }
    }
}
