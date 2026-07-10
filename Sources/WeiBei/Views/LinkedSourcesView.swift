import SwiftUI
import WeiBeiCore

struct LinkedSourcesControl: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        Button {
            store.linkedSourcesPresented.toggle()
        } label: {
            Label(
                store.ui("关联资料 \(store.linkedSourceCount)", "Sources \(store.linkedSourceCount)"),
                systemImage: "link"
            )
        }
        .buttonStyle(WeiBeiTextActionButtonStyle(active: store.linkedSourcesPresented || store.linkedSourceCount > 0))
        .disabled(store.activeNotebookItemID == nil)
        .popover(isPresented: $store.linkedSourcesPresented, arrowEdge: .bottom) {
            LinkedSourcesPopover(dismiss: { store.linkedSourcesPresented = false })
                .environmentObject(store)
        }
        .accessibilityLabel(Text(store.ui("管理笔记关联资料，当前 \(store.linkedSourceCount) 份", "Manage linked sources, \(store.linkedSourceCount) selected")))
        .help(store.ui("为当前笔记选择多份长期关联资料", "Choose durable source links for this note"))
    }
}

private struct LinkedSourcesPopover: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var query = ""
    @State private var draftIDs = Set<String>()
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
        let groups = Dictionary(grouping: materials) { item in
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
                        Text(store.ui("关联资料", "Linked Sources"))
                            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 16, weight: .semibold))
                        Text(store.ui("一份笔记可以连接多种、多个资料", "One note can connect to many source types"))
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
                    Button {
                        toggle(current.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: draftIDs.contains(current.id) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(draftIDs.contains(current.id) ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk)
                            Text(store.ui("当前打开：\(store.displayTitle(for: current))", "Open now: \(store.displayTitle(for: current))"))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(WeiBeiTheme.cinnabarSoft.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityValue(Text(draftIDs.contains(current.id) ? store.ui("已关联", "Linked") : store.ui("未关联", "Not linked")))
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
                                sourceRow(item)
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
                    Label(store.ui("导入并关联", "Import and link"), systemImage: "plus")
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())

                Spacer()

                Button(store.ui("取消", "Cancel"), action: dismiss)
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                Button(store.ui("应用", "Apply")) {
                    store.setLinkedSourceIDsForActiveNote(draftIDs)
                    dismiss()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            }
            .padding(12)
        }
        .frame(width: 470)
        .background(WeiBeiTheme.paperRaised)
        .onAppear { draftIDs = Set(store.linkedSourceIDsForActiveNote) }
    }

    private func sourceRow(_ item: StudyItem) -> some View {
        Button { toggle(item.id) } label: {
            HStack(spacing: 9) {
                Image(systemName: draftIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(draftIDs.contains(item.id) ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk)
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayTitle(for: item)).lineLimit(1)
                    Text(item.url?.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? store.displaySubtitle(for: item))
                        .font(.caption2)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.kind.label(language: store.interfaceLanguage))
                    .font(.caption2)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 7)
            .frame(height: 42)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(draftIDs.contains(item.id) ? store.ui("已关联", "Linked") : store.ui("未关联", "Not linked")))
    }

    private func toggle(_ sourceID: String) {
        if draftIDs.contains(sourceID) { draftIDs.remove(sourceID) }
        else { draftIDs.insert(sourceID) }
    }
}

struct AgentLinkedSourcesScopeControl: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        if store.hasSelectedMaterial || !store.agentSelectableLinkedSources.isEmpty {
            Menu {
                if let current = store.selectedMaterialItem {
                    Button {
                        store.includeCurrentMaterialInAgentScope.toggle()
                    } label: {
                        Label(
                            store.ui("当前打开：\(store.displayTitle(for: current))", "Open now: \(store.displayTitle(for: current))"),
                            systemImage: store.includeCurrentMaterialInAgentScope ? "checkmark" : "circle"
                        )
                    }
                    Divider()
                }
                Button(store.ui("全部使用", "Use all")) { store.selectAllLinkedAgentSources() }
                Button(store.ui("本次都不使用", "Use none")) { store.selectedAgentSourceIDs = [] }
                Divider()
                ForEach(store.agentSelectableLinkedSources) { item in
                    Button {
                        store.setAgentSourceSelected(item.id, selected: !store.selectedAgentSourceIDs.contains(item.id))
                    } label: {
                        Label(store.displayTitle(for: item), systemImage: store.selectedAgentSourceIDs.contains(item.id) ? "checkmark" : "circle")
                    }
                }
            } label: {
                Label(
                    store.ui("本次范围 \(store.selectedAgentLinkedSourceCount)/\(store.agentSelectableLinkedSourceCount)", "Scope \(store.selectedAgentLinkedSourceCount)/\(store.agentSelectableLinkedSourceCount)"),
                    systemImage: "checklist"
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .accessibilityLabel(Text(store.ui("选择本次提问使用的关联资料", "Choose linked sources for this question")))
            .accessibilityValue(Text(store.ui("已选择 \(store.selectedAgentLinkedSourceCount) 份关联资料", "\(store.selectedAgentLinkedSourceCount) linked sources selected")))
        }
    }
}
