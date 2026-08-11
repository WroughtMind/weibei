import Foundation

/// Shared performance budgets used by DEBUG probes and self-checks.
///
/// Post S2 + Phase 2: production encode/write runs on `CourseProjectFileWorker`
/// (actor, off main). `workspaceSaveEncodeMS` still measures pure encode cost
/// for regressions in snapshot size / Codable complexity.
public enum WeiBeiPerfBudgets {
    /// Pure JSON encode for ~200 notes (self-check cost guardrail, not main-thread SLA).
    public static let workspaceSaveEncodeMS: Double = 200

    public static let notePersistMS: Double = 50
    public static let documentSwitchMS: Double = 32
    public static let indexQueryMS: Double = 16

    /// Build a synthetic workspace with `noteCount` notebook notes for encode
    /// benchmarks. Pure value types — no file system.
    public static func syntheticWorkspace(noteCount: Int) -> PersistedWorkspace {
        let notes = (0..<noteCount).map { index -> StudyItem in
            StudyItem(
                id: "perf-note-\(index)",
                title: "性能护栏笔记 \(index)",
                subtitle: "note-\(index).md",
                kind: .markdown,
                urlPath: "/tmp/weibei-perf/note-\(index).md",
                isSample: false,
                isNotebookNote: true
            )
        }
        var notesByItemID: [String: String] = [:]
        for (index, item) in notes.enumerated() {
            notesByItemID[item.id] = """
            # 笔记 \(index)

            这是用于 workspace.save 编码护栏的合成正文。重复段落 \(index)：
            \(String(repeating: "魏碑性能自检段落。", count: 8))
            """
        }
        return PersistedWorkspace(
            importedItems: notes,
            notesByItemID: notesByItemID,
            selectedItemID: notes.first?.id,
            activeNotebookItemID: notes.first?.id
        )
    }

    /// Encode `workspace` and return elapsed milliseconds.
    public static func measureWorkspaceEncodeMilliseconds(
        _ workspace: PersistedWorkspace
    ) throws -> Double {
        let encoder = JSONEncoder()
        let start = DispatchTime.now().uptimeNanoseconds
        _ = try encoder.encode(workspace)
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        return Double(elapsed) / 1_000_000
    }
}
