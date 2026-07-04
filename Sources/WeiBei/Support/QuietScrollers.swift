import AppKit

enum WeiBeiQuietScrollers {
    static func configure(_ scrollView: NSScrollView, hasHorizontalScroller: Bool? = nil) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScroller?.controlSize = .small
        if let hasHorizontalScroller {
            scrollView.hasHorizontalScroller = hasHorizontalScroller
        }
    }

    static func configureRecursively(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            configure(scrollView)
        }
        view.subviews.forEach(configureRecursively)
    }
}
