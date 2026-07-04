import AppKit

enum WeiBeiQuietScrollers {
    static func configure(
        _ scrollView: NSScrollView,
        hasVerticalScroller: Bool? = nil,
        hasHorizontalScroller: Bool? = nil
    ) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        if let hasVerticalScroller {
            scrollView.hasVerticalScroller = hasVerticalScroller
        }
        if let hasHorizontalScroller {
            scrollView.hasHorizontalScroller = hasHorizontalScroller
        }
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScroller?.controlSize = .small
        scrollView.scrollerKnobStyle = .dark
    }

    static func configureRecursively(
        in view: NSView,
        hasVerticalScroller: Bool? = nil,
        hasHorizontalScroller: Bool? = nil
    ) {
        if let scrollView = view as? NSScrollView {
            configure(
                scrollView,
                hasVerticalScroller: hasVerticalScroller,
                hasHorizontalScroller: hasHorizontalScroller
            )
        }
        view.subviews.forEach {
            configureRecursively(
                in: $0,
                hasVerticalScroller: hasVerticalScroller,
                hasHorizontalScroller: hasHorizontalScroller
            )
        }
    }

    static func flashRecursively(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.flashScrollers()
        }
        view.subviews.forEach { flashRecursively(in: $0) }
    }
}
