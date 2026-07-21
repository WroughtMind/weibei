import SwiftUI
import WeiBeiCore

struct LinkedSourcesControl: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        Button {
            store.linkedSourcesPresented.toggle()
        } label: {
            Label(
                store.ui("资料 \(store.linkedSourceCount)", "Sources \(store.linkedSourceCount)"),
                systemImage: "link"
            )
        }
        .buttonStyle(WeiBeiTextActionButtonStyle(active: store.linkedSourcesPresented))
        .disabled(store.activeNotebookItemID == nil)
        .popover(isPresented: $store.linkedSourcesPresented, arrowEdge: .bottom) {
            LinkedSourcesPopover(dismiss: { store.linkedSourcesPresented = false })
                .environmentObject(store)
        }
        .accessibilityLabel(Text(store.ui(
            "管理这份笔记的资料，当前 \(store.linkedSourceCount) 份",
            "Manage sources for this note, \(store.linkedSourceCount) selected"
        )))
        .help(store.ui("为当前笔记选择长期关联的资料", "Choose durable source links for this note"))
    }
}

struct LinkedSourcesPopover: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var query = ""
    @State private var draftIDs = Set<String>()
    @State private var noteItemID: String?
    let dismiss: () -> Void

    private var materials: [StudyItem] {
        store.allItems.filter { item in
            guard !item.isNotebookNote else { return false }
            let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty
                || store.displayTitle(for: item).localizedCaseInsensitiveContains(cleaned)
                || store.displaySubtitle(for: item).localizedCaseInsensitiveContains(cleaned)
        }
    }

    private var groupedMaterials: [(String, [StudyItem])] {
        let groups = Dictionary(grouping: materials.filter { $0.id != store.selectedMaterialItem?.id }) { item in
            item.url?.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                ?? store.ui("内置资料", "Built-in")
        }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.ui("这份笔记的资料", "Sources for this note"))
                            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 16, weight: .semibold))
                        Text(store.ui("选中的资料会一直跟随这份笔记", "Selected sources stay with this note"))
                            .font(.caption)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                    }
                    Spacer()
                    Text("\(draftIDs.count)")
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    TextField(store.ui("搜索标题、文件名", "Search title or file name"), text: $query)
                        .textFieldStyle(.plain)
                }
                .font(.system(size: 13))
                .weibeiInputSurface(height: 32)

                if let current = store.selectedMaterialItem {
                    sourceButton(current, showsCurrentLabel: true)
                }
            }
            .padding(16)

            Divider().overlay(WeiBeiTheme.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedMaterials, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.0)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                .padding(.horizontal, 7)
                            ForEach(group.1) { item in
                                sourceButton(item)
                            }
                        }
                    }
                    if materials.isEmpty {
                        Text(store.ui("没有匹配的资料", "No matching sources"))
                            .font(.caption)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    }
                }
                .padding(12)
            }
            .frame(height: 290)

            Divider().overlay(WeiBeiTheme.hairline)

            HStack {
                Button {
                    store.importAndLinkSourcesFromPanel()
                    dismiss()
                } label: {
                    Label(store.ui("导入资料", "Import sources"), systemImage: "plus")
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())

                Button {
                    store.presentCourseWorkspace(.notes, selecting: noteItemID)
                    dismiss()
                } label: {
                    Label(store.ui("资料关系台", "Course Relations"), systemImage: "books.vertical")
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())

                Spacer()

                Button(store.ui("取消", "Cancel"), action: dismiss)
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                Button(store.ui("保存关联", "Save links")) {
                    if let noteItemID {
                        store.setLinkedSourceIDs(draftIDs, for: noteItemID)
                    }
                    dismiss()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            }
            .padding(12)
        }
        .frame(width: 440)
        .background(WeiBeiTheme.paperRaised)
        .onAppear {
            noteItemID = store.activeNotebookItemID
            if let noteItemID {
                draftIDs = Set(store.linkedSourceIDs(for: noteItemID))
            }
        }
    }

    private func sourceButton(_ item: StudyItem, showsCurrentLabel: Bool = false) -> some View {
        Button { toggle(item.id) } label: {
            HStack(spacing: 9) {
                Image(systemName: draftIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(draftIDs.contains(item.id) ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk)
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayTitle(for: item)).lineLimit(1)
                    if !showsCurrentLabel {
                        Text(item.url?.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? store.displaySubtitle(for: item))
                            .font(.caption2)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(showsCurrentLabel ? store.ui("当前", "Open") : item.kind.label(language: store.interfaceLanguage))
                    .font(.caption2)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .frame(height: showsCurrentLabel ? 36 : 42)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(draftIDs.contains(item.id) ? store.ui("已关联", "Linked") : store.ui("未关联", "Not linked")))
    }

    private func toggle(_ sourceID: String) {
        if draftIDs.contains(sourceID) {
            draftIDs.remove(sourceID)
        } else {
            draftIDs.insert(sourceID)
        }
    }
}
