import Foundation
import WeiBeiCore
import XCTest
@testable import WeiBei

private final class ImportResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedItems: [StudyItem]?
    var result: [StudyItem]? {
        lock.lock()
        defer { lock.unlock() }
        return storedItems
    }
    func fill(_ items: [StudyItem]) {
        lock.lock()
        storedItems = items
        lock.unlock()
    }
}

/// Runs the background import pipeline from tests and waits for the model
/// application on the main actor by pumping the run loop the completion
/// needs, keeping call sites synchronous.
@MainActor
@discardableResult
func importFilesAndWait(
    _ store: WorkspaceStore?,
    _ urls: [URL],
    selectsFirstImportedItem: Bool = true,
    markdownAsNotes: Bool = false,
    markdownOnly: Bool = false,
    markdownNotePaths: Set<String>? = nil,
    reclassifiesExistingMarkdown: Bool = false
) -> [StudyItem] {
    guard let store else { return [] }
    let box = ImportResultBox()
    store.importFiles(
        urls,
        selectsFirstImportedItem: selectsFirstImportedItem,
        markdownAsNotes: markdownAsNotes,
        markdownOnly: markdownOnly,
        markdownNotePaths: markdownNotePaths,
        reclassifiesExistingMarkdown: reclassifiesExistingMarkdown
    ) { box.fill($0) }
    let deadline = Date().addingTimeInterval(120)
    while box.result == nil {
        if Date() > deadline {
            XCTFail("importFilesAndWait timed out waiting for the import pipeline")
            return []
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return box.result ?? []
}
