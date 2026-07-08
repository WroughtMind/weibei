import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var librarySearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.ui("课程目录", "Course Index"))
                            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 22, weight: .semibold))
                        Text(store.interfaceLanguage == .chinese ? "WEIBEI STUDY" : "WEIBEI")
                            .font(WeiBeiTypography.englishBrandFont(size: 8.5, weight: .semibold))
                            .tracking(0.9)
                            .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.74))
                    }
                    Spacer()
                    Button { store.importFilesFromPanel() } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle())
                    .accessibilityLabel(Text(store.ui("导入资料", "Import material")))
                    .help(store.ui("导入资料", "Import material"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                TextField(
                    "",
                    text: $store.librarySearch,
                    prompt: Text(store.ui("搜索当前课程", "Search current course"))
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                    .textFieldStyle(.plain)
                    .focused($librarySearchFocused)
                    .foregroundColor(WeiBeiTheme.ink)
                .font(.system(size: 13))
                .weibeiInputSurface(active: librarySearchFocused)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.70, materialOpacity: 0.10))
            .overlay(alignment: .bottom) {
                WeiBeiHeaderHandoffFade(height: 16, opacity: 0.72)
                    .offset(y: 16)
            }
            .zIndex(1)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    sidebarSection(title: store.ui("课程样例", "Course Samples"), items: store.sampleItems)
                    sidebarSection(title: store.ui("我的资料", "My Materials"), items: importedMaterialItems)
                    sidebarSection(title: store.ui("我的笔记", "My Notes"), items: notebookItems)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .background {
                ZStack {
                    WeiBeiTheme.paperRaised.opacity(0.64)
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.035)
                }
            }
        }
        .weibeiPanel()
        .onChange(of: store.focusRequest) { _, _ in
            librarySearchFocused = store.focusedPane == .library
        }
        .onAppear {
            librarySearchFocused = store.focusedPane == .library
        }
    }

    private var importedMaterialItems: [StudyItem] {
        store.filteredItems.filter { !$0.isSample && !$0.isNotebookNote }
    }

    private var notebookItems: [StudyItem] {
        store.filteredItems.filter(\.isNotebookNote)
    }

    @ViewBuilder
    private func sidebarSection(title: String, items: [StudyItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .padding(.horizontal, 8)

                ForEach(items) { item in
                    if store.notebookRenameDraft?.itemID == item.id {
                        NotebookRenameRow(item: item, selected: item.isNotebookNote ? store.activeNotebookItemID == item.id : store.selectedItemID == item.id)
                            .transition(WeiBeiTransition.message)
                    } else {
                        Button {
                            withAnimation(WeiBeiMotion.panel) {
                                store.select(itemID: item.id)
                            }
                        } label: {
                            LibraryRow(item: item, selected: item.isNotebookNote ? store.activeNotebookItemID == item.id : store.selectedItemID == item.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if item.isNotebookNote {
                                Button(store.ui("重命名笔记", "Rename Note")) {
                                    store.promptRenameNotebookNote(itemID: item.id)
                                }
                            }
                        }
                        .transition(WeiBeiTransition.message)
                    }
                }
            }
        }
    }
}

private struct NotebookRenameRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    var item: StudyItem
    var selected: Bool
    @FocusState private var focused: Bool

    private var title: Binding<String> {
        Binding(
            get: { store.notebookRenameDraft?.title ?? "" },
            set: { store.notebookRenameDraft?.title = $0 }
        )
    }

    private var canRename: Bool {
        !title.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                .frame(width: 18)

            TextField(
                "",
                text: title,
                prompt: Text(store.ui("笔记名", "Note title"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(WeiBeiTheme.ink)
            .onSubmit {
                if canRename {
                    store.confirmRenameNotebookNote()
                }
            }

            Button {
                store.cancelRenameNotebookNote()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 20))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(store.ui("取消", "Cancel")))
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperInset.opacity(selected ? 0.74 : 0.44))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(WeiBeiTheme.cinnabar.opacity(canRename ? 0.72 : 0.34))
                .frame(width: 3, height: 24)
                .padding(.leading, 2)
        }
        .onAppear {
            focused = true
        }
    }
}

private struct LibraryRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    var item: StudyItem
    var selected: Bool
    @State private var hovering = false

    private var tags: [String] {
        store.displayTags(for: item)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.kind == .pdf ? WeiBeiTheme.link : WeiBeiTheme.tertiaryInk)
                .frame(width: 18)
                .scaleEffect(selected || hovering ? 1.08 : 1)
                .opacity(selected || hovering ? 1 : 0.78)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayTitle(for: item))
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.displaySubtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
                if !tags.isEmpty {
                    Text(tags.joined(separator: " "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.72))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: tags.isEmpty ? 48 : 58)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .offset(x: selected || hovering ? 2 : 0)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(WeiBeiTheme.cinnabar.opacity(0.72))
                    .frame(width: 3, height: 24)
                    .padding(.leading, 2)
                    .transition(.scale(scale: 0.7, anchor: .center).combined(with: .opacity))
            }
        }
        .weibeiHoverLift(active: hovering && !selected, amount: 1)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.micro) {
                self.hovering = hovering
            }
        }
        .animation(WeiBeiMotion.micro, value: selected)
        .animation(WeiBeiMotion.hover, value: hovering)
    }

    private var rowBackground: Color {
        if selected { return WeiBeiTheme.paperInset.opacity(0.70) }
        if hovering { return WeiBeiTheme.paperInset.opacity(0.30) }
        return .clear
    }
}
