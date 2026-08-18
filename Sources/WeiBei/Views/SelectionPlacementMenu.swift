import SwiftUI

struct SelectionPlacementMenu: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        let placements = store.activeSelectionPlacements()
        if !placements.isEmpty {
            Menu {
                ForEach(placements, id: \.placement.id) { pair in
                    Menu(label(pair.thread.selectionText)) {
                        Button(store.ui("向前移动", "Move earlier")) {
                            store.moveSelectionPlacement(pair.placement.id, offset: -1)
                        }
                        Button(store.ui("向后移动", "Move later")) {
                            store.moveSelectionPlacement(pair.placement.id, offset: 1)
                        }
                        Button(store.ui("解除同步并保留正文", "Detach and keep text")) {
                            store.detachSelectionPlacement(pair.placement.id)
                        }
                        Button(store.ui("只删除此处", "Delete this placement"), role: .destructive) {
                            store.deleteSelectionPlacement(pair.placement.id)
                        }
                    }
                }
            } label: {
                Image(systemName: "quote.opening")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 24))
            .help(store.ui("管理当前笔记中的札记段", "Manage annotations in this note"))
        }
    }

    private func label(_ text: String) -> String {
        let compact = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return compact.count > 28 ? String(compact.prefix(28)) + "…" : compact
    }
}
