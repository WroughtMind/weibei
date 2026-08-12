import SwiftUI

struct CourseImmersiveDrawerView: View {
    static let width: CGFloat = CourseDrawerContainerView.panelWidth

    let store: WorkspaceStore
    let model: CourseSidebarModel
    let dismiss: () -> Void

    var body: some View {
        SidebarView(store: store, model: model)
            .frame(width: Self.width)
            .frame(maxHeight: .infinity, alignment: .top)
            // Solid paper only — material blur during slide was expensive.
            .background(WeiBeiTheme.paperRaised)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.58))
                    .frame(width: 1)
            }
            .accessibilityAction(.escape, dismiss)
    }
}
