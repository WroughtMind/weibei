import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var librarySearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("资料")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                    Spacer()
                    Button { store.importFilesFromPanel() } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle())
                    .accessibilityLabel(Text("导入资料"))
                    .help("导入资料")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                TextField(
                    "",
                    text: $store.librarySearch,
                    prompt: Text("搜索资料库")
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
                    sidebarSection(title: "样例", items: store.sampleItems)
                    sidebarSection(title: "导入资料", items: importedMaterialItems)
                    sidebarSection(title: "笔记", items: notebookItems)
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
                    Button {
                        withAnimation(WeiBeiMotion.panel) {
                            store.select(itemID: item.id)
                        }
                    } label: {
                        LibraryRow(item: item, selected: store.selectedItemID == item.id)
                    }
                    .buttonStyle(.plain)
                    .transition(WeiBeiTransition.message)
                }
            }
        }
    }
}

private struct LibraryRow: View {
    var item: StudyItem
    var selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.kind == .pdf ? WeiBeiTheme.link : WeiBeiTheme.tertiaryInk)
                .frame(width: 18)
                .scaleEffect(selected || hovering ? 1.08 : 1)
                .opacity(selected || hovering ? 1 : 0.78)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
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
