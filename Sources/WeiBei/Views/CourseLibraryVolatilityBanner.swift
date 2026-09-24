import SwiftUI
import WeiBeiCore

struct CourseLibraryVolatilityBanner: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .weiBeiText(13, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.ui(
                    "当前资料库位于临时位置，系统可能清理",
                    "The current library is in a temporary location and the system may delete it"
                ))
                .weiBeiText(12, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
                if let path = store.courseLibraryRootPath {
                    Text(path)
                        .weiBeiText(11)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(
                store.ui("更换资料库…", "Change Library…"),
                action: store.presentCourseLibraryMigrationPicker
            )
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            .accessibilityHint(Text(store.ui(
                "换用别的文件夹；课程文件不会被移动",
                "Switch to another folder; course files are not moved"
            )))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.cinnabarSoft.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WeiBeiTheme.cinnabar.opacity(0.28))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(store.ui(
            "资料库位于临时位置",
            "Library is in a temporary location"
        )))
    }
}
