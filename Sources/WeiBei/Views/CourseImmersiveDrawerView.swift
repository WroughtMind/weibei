import SwiftUI

struct CourseImmersiveDrawerView: View {
    let dismiss: () -> Void

    var body: some View {
        SidebarView()
            .frame(width: 292)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.58))
                    .frame(width: 1)
            }
            .accessibilityAction(.escape, dismiss)
    }
}
