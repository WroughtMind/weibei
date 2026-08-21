import AppKit
import SwiftUI
import WeiBei
import WeiBeiCore

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("CrashRepro-\(UUID().uuidString)", isDirectory: true)
let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
store.importedItems = (0..<2_000).map { index in
    StudyItem(
        id: "contextual-material-\(index)",
        title: "资料 \(index)",
        subtitle: "material-\(index).txt",
        kind: .text,
        urlPath: nil,
        isSample: false,
        storage: .common(relativePath: "")
    )
}
let host = NSHostingView(
    rootView: ContextualContentPicker(
        kind: .material,
        initialLevelForTesting: .common
    )
    .environmentObject(store)
)
host.frame = NSRect(x: 0, y: 0, width: 480, height: 600)
let window = NSWindow(
    contentRect: host.frame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.contentView = host

struct Pump {}
func pumpMainRunLoop() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
pumpMainRunLoop()
host.layoutSubtreeIfNeeded()
pumpMainRunLoop()
print("SURVIVED")
