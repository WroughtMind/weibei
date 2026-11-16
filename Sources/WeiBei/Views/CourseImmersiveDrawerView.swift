import SwiftUI

struct CourseImmersiveDrawerView: View {
    static let width: CGFloat = WeiBeiMetric.courseDrawerWidth

    let store: WorkspaceStore
    let model: CourseSidebarModel
    let dismiss: () -> Void

    var body: some View {
        SidebarView(store: store, model: model)
            .frame(width: Self.width)
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                EscapeKeyBridge(onEscape: handleEscape)
            }
            .accessibilityAction(.escape, handleEscape)
    }

    private func handleEscape() {
        model.handleEscape(dismiss: dismiss)
    }
}
