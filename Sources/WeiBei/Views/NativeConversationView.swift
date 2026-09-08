import AppKit
import SwiftUI
import WeiBeiCore

/// The workspace receives only navigation changes, never per-message geometry.
@MainActor
final class NativeConversationNavigation: ObservableObject {
    @Published var items: [ContentRailItem] = []
    @Published var activeID: String?
    @Published var showsJumpToLatest = false
    weak var controller: NativeConversationController?

    func jumpToLatest() { controller?.jumpToLatest() }
    func activate(_ item: ContentRailItem) { controller?.navigate(to: item.id) }
}

struct NativeConversationView: NSViewControllerRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weiBeiTextScale) private var textScale
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var navigation: NativeConversationNavigation
    var wide: Bool
    var isVisible: Bool

    func makeNSViewController(context: Context) -> NativeConversationController {
        let controller = NativeConversationController(store: store, navigation: navigation)
        controller.openSettings = { openWindow(id: "weibei-settings") }
        controller.configure(wide: wide, textScale: textScale, isVisible: isVisible)
        return controller
    }

    func updateNSViewController(_ controller: NativeConversationController, context: Context) {
        store.setAgentStreamingReduceMotion(reduceMotion)
        controller.openSettings = { openWindow(id: "weibei-settings") }
        controller.configure(wide: wide, textScale: textScale, isVisible: isVisible)
    }

    static func dismantleNSViewController(_ controller: NativeConversationController, coordinator: ()) {
        controller.disconnect()
    }
}
