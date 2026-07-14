import Foundation
import WeiBeiCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("relation check failed: \(message)\n", stderr)
        exit(1)
    }
}

let legacy = Data(#"{"importedItems":[],"notesByItemID":{}}"#.utf8)
let workspace = try JSONDecoder().decode(PersistedWorkspace.self, from: legacy)
expect(workspace.schemaVersion == 1, "legacy workspaces keep schema version 1")
expect(workspace.noteSourceLinks == [], "legacy workspaces decode with no source relations")

let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
var relations = NoteSourceRelations()
expect(relations.link(noteID: "note-1", sourceID: "source-pdf", origin: .manual, createdAt: fixedDate), "first source link is inserted")
expect(relations.link(noteID: "note-1", sourceID: "source-html", origin: .noteCreation, createdAt: fixedDate), "one note can link a second source type")
expect(!relations.link(noteID: "note-1", sourceID: "source-pdf", origin: .manual, createdAt: fixedDate), "duplicate source link is ignored")
expect(relations.sourceIDs(for: "note-1").sorted() == ["source-html", "source-pdf"], "one note keeps both linked sources")

let persisted = PersistedWorkspace(noteSourceLinks: relations.links)
let restored = try JSONDecoder().decode(PersistedWorkspace.self, from: JSONEncoder().encode(persisted))
expect(restored.schemaVersion == 2, "new workspaces encode schema version 2")
expect(restored.noteSourceLinks.count == 2, "source relations survive a workspace round trip")

var openSelection = WorkspaceOpenSelection(materialID: "source-a", noteID: "note-1")
openSelection.openMaterial("source-b")
expect(openSelection.materialID == "source-b", "opening another material updates only the reader")
expect(openSelection.noteID == "note-1", "opening another material preserves the active note")
openSelection.activateNote("note-2")
expect(openSelection.materialID == "source-b", "activating another note preserves the open material")
expect(openSelection.noteID == "note-2", "activating another note updates only the editor")

let discoveryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-relation-check-\(UUID().uuidString)", isDirectory: true)
let nestedDirectory = discoveryRoot.appendingPathComponent("课程乙", isDirectory: true)
try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
try Data("PDF".utf8).write(to: discoveryRoot.appendingPathComponent("课程甲.pdf"))
try Data("HTML".utf8).write(to: nestedDirectory.appendingPathComponent("讲义.html"))
try Data("MARKDOWN".utf8).write(to: nestedDirectory.appendingPathComponent("课堂笔记.md"))
try Data("IMAGE".utf8).write(to: nestedDirectory.appendingPathComponent("封面.png"))
try Data("HIDDEN".utf8).write(to: nestedDirectory.appendingPathComponent(".隐藏.txt"))
defer { try? FileManager.default.removeItem(at: discoveryRoot) }
let discoveredURLs = StudyMaterialDiscovery.urls(from: [discoveryRoot])
expect(Set(discoveredURLs.map(\.lastPathComponent)) == Set(["课程甲.pdf", "课堂笔记.md", "讲义.html"]), "folder import discovers supported files recursively")
expect(discoveredURLs.map(\.path) == discoveredURLs.map(\.path).sorted(), "folder import returns a deterministic snapshot order")

let availableAgentSources = [
    StudyAgentSource(id: "source-a", title: "课程甲 PDF", kind: .pdf, text: "AAAAAA"),
    StudyAgentSource(id: "source-b", title: "课程乙 HTML", kind: .html, text: "BBBBBB"),
    StudyAgentSource(id: "source-c", title: "课堂讲义", kind: .markdown, text: "CCCCCC")
]
let scopedAgentSources = StudyAgentSourceContextBuilder.scopedSources(
    availableAgentSources,
    selectedIDs: ["source-a", "source-c"],
    totalCharacterLimit: 10,
    perSourceLimit: 8
)
expect(scopedAgentSources.map(\.id) == ["source-a", "source-c"], "agent context contains only explicitly selected linked sources")
expect(scopedAgentSources.map(\.text).joined().count <= 10, "linked source context stays inside the shared character budget")
expect(!scopedAgentSources.map(\.text).joined().contains("B"), "unselected source text never leaks into the agent context")

let railMaterials = [
    StudyItem(id: "source-a", title: "课程甲", subtitle: "课程甲.pdf", kind: .pdf, urlPath: "/tmp/甲/课程甲.pdf", isSample: false),
    StudyItem(id: "source-b", title: "课程乙", subtitle: "课程乙.html", kind: .html, urlPath: "/tmp/乙/课程乙.html", isSample: false),
    StudyItem(id: "source-c", title: "课堂讲义", subtitle: "课堂讲义.md", kind: .markdown, urlPath: "/tmp/乙/课堂讲义.md", isSample: false)
]
let unlinkedCurrentRail = LinkedSourceRailModel.entries(
    materials: railMaterials,
    linkedSourceIDs: ["source-a", "source-c", "missing-source"],
    currentMaterialID: "source-b"
)
expect(unlinkedCurrentRail.map(\.sourceID) == ["source-b", "source-a", "source-c"], "rail shows the unlinked current material before linked sources")
expect(unlinkedCurrentRail.map(\.state) == [.currentUnlinked, .linked, .linked], "rail distinguishes current unlinked material from durable links")
let linkedCurrentRail = LinkedSourceRailModel.entries(
    materials: railMaterials,
    linkedSourceIDs: ["source-a", "source-c"],
    currentMaterialID: "source-a"
)
expect(linkedCurrentRail.map(\.state) == [.currentLinked, .linked], "rail marks the open linked source without duplicating it")

print("WeiBei relation check passed")
