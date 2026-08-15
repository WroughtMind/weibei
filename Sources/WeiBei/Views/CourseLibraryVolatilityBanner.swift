import SwiftUI
import WeiBeiCore

struct CourseLibraryVolatilityBanner: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.ui(
                    "当前资料库位于临时位置，系统可能清理",
                    "The current library is in a temporary location and the system may delete it"
                ))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
                if let path = store.courseLibraryRootPath {
                    Text(path)
                        .font(.system(size: 11))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(
                store.ui("迁移/更换魏碑资料库", "Move / Change WeiBei Library"),
                action: store.presentCourseLibraryMigrationPicker
            )
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            .accessibilityHint(Text(store.ui(
                "即使当前资料库仍可访问，也可以更换到更持久的位置",
                "You can change the library even while the current folder is still reachable"
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

struct MissingImportedItemBanner: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.badge.ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.ui("源文件缺失", "Source file missing"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.ui(
                    "“\(store.missingImportedSourceDisplayTitle)” 的原文件当前无法打开。重新选择文件只会更新这一条记录。",
                    "“\(store.missingImportedSourceDisplayTitle)” cannot be opened. Choosing a file again updates this item only."
                ))
                .font(.system(size: 11))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(
                store.ui("重新选择文件", "Choose File Again"),
                action: store.presentRebindPanelForSelectedMissingImportedItem
            )
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
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
        .accessibilityLabel(Text(store.ui("源文件缺失", "Source file missing")))
    }
}
