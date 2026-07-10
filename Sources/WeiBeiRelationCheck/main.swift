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

let discoveryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("weibei-relation-check-\(UUID().uuidString)", isDirectory: true)
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
let movableURL = discoveryRoot.appendingPathComponent("可移动资料.txt")
try Data("MOVE".utf8).write(to: movableURL)
let originalFileIdentity = StudyMaterialDiscovery.fileIdentity(for: movableURL)
let movedURL = nestedDirectory.appendingPathComponent("已移动资料.txt")
try FileManager.default.moveItem(at: movableURL, to: movedURL)
expect(originalFileIdentity != nil && StudyMaterialDiscovery.fileIdentity(for: movedURL) == originalFileIdentity, "file identity survives a Finder-style move on the same volume")

let availableAgentSources = [
    StudyAgentSource(id: "source-a", title: "课程甲 PDF", kind: .pdf, text: "AAAAAA"),
    StudyAgentSource(id: "source-b", title: "课程乙 HTML", kind: .html, text: "BBBBBB"),
    StudyAgentSource(id: "source-c", title: "课堂讲义", kind: .markdown, text: "CCCCCC")
]
let scopedAgentSources = StudyAgentSourceContextBuilder.scopedSources(availableAgentSources, selectedIDs: ["source-a", "source-c"], totalCharacterLimit: 10, perSourceLimit: 8)
expect(scopedAgentSources.map(\.id) == ["source-a", "source-c"], "agent context contains only explicitly selected linked sources")
expect(scopedAgentSources.map(\.text).joined().count <= 10, "linked source context stays inside the shared character budget")
expect(!scopedAgentSources.map(\.text).joined().contains("B"), "unselected source text never leaks into the agent context")
let linkedPrompt = OpenAIResponsesClient.composePrompt(
    question: "比较甲与丙",
    materialTitle: "",
    materialText: "",
    noteText: "笔记正文",
    selectionText: nil,
    linkedSources: scopedAgentSources,
    recentMessages: []
)
expect(linkedPrompt.input.contains("课程甲 PDF") && linkedPrompt.input.contains("课堂讲义"), "prompt includes selected linked source titles")
expect(!linkedPrompt.input.contains("课程乙 HTML") && !linkedPrompt.input.contains("BBBBBB"), "prompt excludes every unselected linked source")
let offlineLinkedDraft = AgentOfflinePreview.render(AgentOfflinePreviewInput(
    language: .chinese,
    question: "比较资料",
    hasMaterial: false,
    materialTitle: "",
    materialText: "",
    noteTitle: "课堂笔记",
    noteText: "笔记正文",
    selectionTitle: nil,
    selectionText: nil,
    linkedSources: scopedAgentSources
))
expect(offlineLinkedDraft.contains("课程甲 PDF") && offlineLinkedDraft.contains("课堂讲义"), "offline agent uses the explicitly selected linked sources")
expect(!offlineLinkedDraft.contains("课程乙 HTML") && !offlineLinkedDraft.contains("BBBBBB"), "offline agent excludes unselected linked sources")
let budgetPrompt = OpenAIResponsesClient.composePrompt(
    question: "预算检查",
    materialTitle: "当前资料",
    materialText: String(repeating: "A", count: 20_000),
    noteText: "",
    selectionText: nil,
    linkedSources: [StudyAgentSource(id: "source-c", title: "关联资料", kind: .text, text: String(repeating: "C", count: 20_000))],
    recentMessages: []
)
let sourceCharacterCount = budgetPrompt.input.filter { $0 == "A" || $0 == "C" }.count
expect(sourceCharacterCount <= 18_000, "current and linked material share one 18k character budget")

let railMaterials = [
    StudyItem(id: "source-a", title: "课程甲", subtitle: "课程甲.pdf", kind: .pdf, urlPath: "/tmp/甲/课程甲.pdf", isSample: false),
    StudyItem(id: "source-b", title: "课程乙", subtitle: "课程乙.html", kind: .html, urlPath: "/tmp/乙/课程乙.html", isSample: false),
    StudyItem(id: "source-c", title: "课堂讲义", subtitle: "课堂讲义.md", kind: .markdown, urlPath: "/tmp/乙/课堂讲义.md", isSample: false)
]
let unlinkedCurrentRail = LinkedSourceRailModel.entries(materials: railMaterials, linkedSourceIDs: ["source-a", "source-c", "missing-source"], currentMaterialID: "source-b")
expect(unlinkedCurrentRail.map(\.sourceID) == ["source-b", "source-a", "source-c"], "rail shows the unlinked current material before linked sources")
expect(unlinkedCurrentRail.map(\.state) == [.currentUnlinked, .linked, .linked], "rail distinguishes current unlinked material from durable links")
let linkedCurrentRail = LinkedSourceRailModel.entries(materials: railMaterials, linkedSourceIDs: ["source-a", "source-c"], currentMaterialID: "source-a")
expect(linkedCurrentRail.map(\.state) == [.currentLinked, .linked], "rail marks the open linked source without duplicating it")

print("WeiBei relation check passed")
