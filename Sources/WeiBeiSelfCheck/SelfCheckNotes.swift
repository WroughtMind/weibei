import Foundation
import WeiBeiCore

/// Local no-Xcode mirrors for note persistence / rename scenes that live in
/// `ImportedIdentitySelfCheck` as WorkspaceStore integration tests.
/// Calls the same `PersistedWorkspace` / `StudyItem` production APIs.
func checkNotePersistenceScenes() throws {
    let itemID = "imported:note-persist"
    let pending = PendingNoteWriteState(baselineContentDigest: "sha256:baseline")
    let snapshot = PersistedWorkspace(
        importedItems: [
            StudyItem(
                id: itemID,
                title: "利率笔记",
                subtitle: "利率笔记.md",
                kind: .markdown,
                urlPath: "/tmp/利率笔记.md",
                importedFileLastKnownPath: "/tmp/利率笔记.md",
                isSample: false,
                isNotebookNote: true,
                customDisplayTitle: "我的速记"
            ),
        ],
        notesByItemID: [itemID: "# 利率笔记\n\n真实正文"],
        pendingNoteWritesByItemID: [itemID: pending],
        noteBackingContentDigestsByItemID: [itemID: "sha256:disk"],
        activeNotebookItemID: itemID
    )
    let restored = try JSONDecoder().decode(
        PersistedWorkspace.self,
        from: try JSONEncoder().encode(snapshot)
    )
    expect(
        restored.notesByItemID[itemID] == "# 利率笔记\n\n真实正文",
        "note drafts persist in notesByItemID"
    )
    expect(
        restored.pendingNoteWritesByItemID?[itemID] == pending,
        "pending note write errors stay attached to the affected note"
    )
    expect(
        restored.noteBackingContentDigestsByItemID?[itemID] == "sha256:disk",
        "last self-written note digest persists"
    )
    expect(
        restored.activeNotebookItemID == itemID,
        "the active notebook item survives a workspace round-trip"
    )

    let note = try JSONDecoder().decode(
        StudyItem.self,
        from: try JSONEncoder().encode(snapshot.importedItems[0])
    )
    expect(
        note.isNotebookNote
            && note.customDisplayTitle == "我的速记"
            && note.editsBackingMarkdownFile
            && !note.canBecomeNotebookNote,
        "a notebook note keeps its rename title and backing-file edit flag"
    )

    let legacyNote = try JSONDecoder().decode(
        StudyItem.self,
        from: Data(
            """
            {
              "id":"file:/tmp/old-note.md",
              "title":"旧笔记",
              "subtitle":"old-note.md",
              "kind":"markdown",
              "urlPath":"/tmp/old-note.md",
              "isSample":false
            }
            """.utf8
        )
    )
    expect(
        legacyNote.isNotebookNote == false
            && legacyNote.importedFileLastKnownPath == "/tmp/old-note.md"
            && legacyNote.canBecomeNotebookNote
            && !legacyNote.editsBackingMarkdownFile,
        "a legacy markdown file does not become a notebook note and keeps lastKnownPath from urlPath"
    )

    let material = StudyItem(
        id: "imported:material",
        title: "文稿",
        subtitle: "文稿.txt",
        kind: .text,
        urlPath: "/tmp/文稿.txt",
        isSample: false
    )
    expect(
        !material.editsBackingMarkdownFile && !material.canBecomeNotebookNote,
        "a non-markdown material cannot be treated as a notebook note"
    )
}
