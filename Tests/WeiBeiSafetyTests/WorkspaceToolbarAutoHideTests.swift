import AppKit
import XCTest
@testable import WeiBei

final class WorkspaceToolbarAutoHideTests: XCTestCase {
    @MainActor
    private final class ToolbarItems: NSObject, NSToolbarDelegate {
        let identifiers = ["weibei.navigation", "panes", "settings"].map { NSToolbarItem.Identifier($0) }
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            let item = NSToolbarItem(itemIdentifier: identifier)
            let button = NSButton(title: identifier.rawValue, target: nil, action: nil)
            button.frame = NSRect(x: 0, y: 0, width: 90, height: 28)
            // Keep the fixture's size fixed before AppKit's deferred toolbar
            // layout; text fitting is independent of the visibility behavior.
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 90),
                button.heightAnchor.constraint(equalToConstant: 28)
            ])
            item.view = button
            return item
        }
    }

    @MainActor
    private func makeWindow(_ delegate: ToolbarItems) -> (NSWindow, NSToolbar, WorkspaceToolbarAutoHide) {
        _ = NSApplication.shared
        // Build native chrome without ordering a window onto the user's desktop.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: UUID().uuidString)
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        window.toolbarStyle = .unifiedCompact
        window.toolbar = toolbar
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        let controller = WorkspaceToolbarAutoHide(toolbar: toolbar)
        controller.refresh(in: window)
        return (window, toolbar, controller)
    }

    @MainActor
    private func opacity(_ view: NSView) -> CGFloat {
        var result: CGFloat = 1
        var current: NSView? = view
        while let value = current { result *= value.alphaValue; current = value.superview }
        return result
    }

    @MainActor
    private func animations(in view: NSView) -> [CABasicAnimation] {
        guard let layer = view.layer else { return [] }
        return (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) as? CABasicAnimation }
    }

    @MainActor
    func testAllControlsHideTogetherWithoutMovingReadingArea() async throws {
        let items = ToolbarItems()
        let (window, toolbar, controller) = makeWindow(items)
        defer { controller.detach(); window.close() }
        let views = toolbar.items.compactMap(\.view)
        XCTAssertEqual(views.count, 3)
        let windowButtons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        XCTAssertEqual(windowButtons.count, 3)
        let controls = views + windowButtons
        XCTAssertNotNil(controller.hoverRegion.superview)
        let readingRect = window.contentLayoutRect
        let frames = views.map { $0.convert($0.bounds, to: nil) }
        XCTAssertTrue(controls.allSatisfy { opacity($0) < 0.01 })

        controller.setPointerInside(true)
        let navigation = try XCTUnwrap(views.first)
        XCTAssertTrue(animations(in: navigation).contains { $0.keyPath == "transform.translation.x" })
        XCTAssertTrue(windowButtons.allSatisfy { opacity($0) < 0.01 }, "Traffic lights wait for the navigation to clear")
        XCTAssertTrue(windowButtons.allSatisfy { $0.layer != nil }, "The first reveal needs a drawable layer before any light becomes visible")
        XCTAssertEqual(views.map { $0.convert($0.bounds, to: nil) }, frames)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(controls.allSatisfy { opacity($0) > 0.99 })
        XCTAssertEqual(window.contentLayoutRect, readingRect)
        XCTAssertEqual(views.map { $0.convert($0.bounds, to: nil) }, frames)

        controller.setPointerInside(false)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(controls.allSatisfy { opacity($0) < 0.01 }, "Settings and window controls must follow the same hide rule")
        XCTAssertTrue(toolbar.isVisible, "Hiding the native toolbar would change the safe area")
        XCTAssertEqual(window.contentLayoutRect, readingRect)
        XCTAssertEqual(views.map { $0.convert($0.bounds, to: nil) }, frames)
    }

    @MainActor
    func testReducingMotionDuringRevealFadesNativeButtonsInPlace() throws {
        let items = ToolbarItems()
        let (window, toolbar, controller) = makeWindow(items)
        defer { controller.detach(); window.close() }
        let navigation = try XCTUnwrap(toolbar.items.first?.view)
        let close = try XCTUnwrap(window.standardWindowButton(.closeButton))

        controller.setPointerInside(true)
        controller.reduceMotion = true

        XCTAssertFalse(animations(in: navigation).contains { $0.keyPath == "transform.translation.x" })
        let fade = try XCTUnwrap(animations(in: close).first { $0.keyPath == "opacity" })
        XCTAssertEqual(fade.fromValue as? Float, 0)
        XCTAssertEqual(fade.toValue as? Float, 1)
        XCTAssertGreaterThan(opacity(close), 0.99, "The native hit target is ready during its fade")
    }

    @MainActor
    func testReentryCancelsPendingHideAndDetachRestoresChrome() async throws {
        let items = ToolbarItems()
        let (window, toolbar, controller) = makeWindow(items)
        defer { controller.detach(); window.close() }
        controller.setPointerInside(true)
        controller.setPointerInside(false)
        controller.setPointerInside(true)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(controller.controlsVisible)
        XCTAssertTrue(toolbar.items.compactMap(\.view).allSatisfy { opacity($0) > 0.99 })
        controller.setPointerInside(false)
        controller.detach()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(controller.hoverRegion.superview)
        XCTAssertTrue(toolbar.items.compactMap(\.view).allSatisfy { opacity($0) > 0.99 })
    }

    @MainActor
    func testHoverRegionPassesClicksAndKeepsWindowDragArea() {
        let region = WorkspaceToolbarHoverRegion(frame: NSRect(x: 0, y: 0, width: 700, height: 40))
        XCTAssertNil(region.hitTest(NSPoint(x: 20, y: 20)))
        XCTAssertNil(region.hitTest(NSPoint(x: 350, y: 20)))
        XCTAssertNil(region.hitTest(NSPoint(x: 680, y: 20)))
    }
}
