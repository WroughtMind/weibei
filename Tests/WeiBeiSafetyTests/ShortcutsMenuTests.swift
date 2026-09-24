import AppKit
import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

@MainActor
final class ShortcutsMenuTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testReservedChordsCoverSystemEditingKeys() {
        for key in ["a", "b", "c", "n", "o", "q", "v", "w", "x", "z"] {
            let chord = AppShortcutChord(key: key, modifiers: .command)
            XCTAssertTrue(AppShortcutCatalog.isReservedTextEditingChord(chord), key)
            XCTAssertNil(AppShortcutCatalog.action(matching: chord, overrides: [:]), key)
        }
    }

    func testRecordingWithoutCommandControlOrOptionIsRejected() {
        XCTAssertFalse(AppShortcutCatalog.acceptsRecording(AppShortcutChord(key: "a", modifiers: [])))
        XCTAssertFalse(AppShortcutCatalog.acceptsRecording(AppShortcutChord(key: "a", modifiers: .shift)))
        XCTAssertNil(chord(keyCode: 0, characters: "a", modifiers: []))
        XCTAssertNil(chord(keyCode: 0, characters: "A", modifiers: .shift))
        XCTAssertTrue(AppShortcutCatalog.acceptsRecording(
            AppShortcutChord(key: "t", modifiers: [.command, .control])
        ))
    }

    func testDefaultAppearanceAndNewChatChordsAreFree() {
        XCTAssertEqual(
            AppShortcutID.toggleAppearance.defaultChord,
            AppShortcutChord(key: "t", modifiers: [.command, .control])
        )
        XCTAssertEqual(
            AppShortcutID.newConversation.defaultChord,
            AppShortcutChord(key: "n", modifiers: [.command, .shift])
        )
        let defaults = AppShortcutID.allCases.map(\.defaultChord)
        let keys = defaults.map { "\($0.key)#\($0.modifiersRaw)" }
        XCTAssertEqual(Set(keys).count, keys.count)
        let saved = AppShortcutChord(key: "t", modifiers: [.command, .option])
        XCTAssertEqual(
            AppShortcutCatalog.chord(for: .toggleAppearance, overrides: [.toggleAppearance: saved]),
            saved
        )
    }

    func testThreePaneLayoutRevealsEveryPane() throws {
        let store = try makeStore()
        store.paneState.setDocumentPanes(reader: true, agent: false, notes: false)
        store.setLayout(.documentAgentNotes)
        XCTAssertTrue(store.showReader)
        XCTAssertTrue(store.showAgent)
        XCTAssertTrue(store.showNotes)

        store.showNotes = false
        store.focus(.notes)
        XCTAssertTrue(store.showNotes)
        XCTAssertEqual(store.focusedPane, .notes)
    }

    private func chord(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> AppShortcutChord? {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters.lowercased(),
            isARepeat: false,
            keyCode: keyCode
        )
        return event.flatMap(AppShortcutChord.from(event:))
    }

    private func makeStore() throws -> WorkspaceStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-shortcuts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return WorkspaceStore(
            workspaceDirectory: root,
            courseRootBookmarkMaker: { _ in nil },
            courseRootBookmarkResolver: { _ in nil }
        )
    }
}
