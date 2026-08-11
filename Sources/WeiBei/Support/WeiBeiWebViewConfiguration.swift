import WebKit

/// Shared WebKit configuration helpers (performance Phase 4).
///
/// Note: `WKProcessPool` is deprecated on modern macOS and no longer isolates
/// processes. We still centralize configuration so secondary surfaces share
/// consistent JS / media defaults without scattering setup code.
enum WeiBeiWebViewConfiguration {
    static func make(
        allowingInlineMedia: Bool = true,
        nonPersistent: Bool = false
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        if nonPersistent {
            configuration.websiteDataStore = .nonPersistent()
        }
        configuration.suppressesIncrementalRendering = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if allowingInlineMedia {
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.preferences.isElementFullscreenEnabled = true
        }
        return configuration
    }
}
