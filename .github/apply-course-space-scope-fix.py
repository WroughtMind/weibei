from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


paper = "Sources/WeiBei/Views/CourseRelationPaperView.swift"
replace_once(
    paper,
    "    let isCompact: Bool\n\n    @State private var scope: CourseRelationPaperScope?",
    "    let isCompact: Bool\n    var allowsWorkspaceScopes: Bool = true\n\n    @State private var scope: CourseRelationPaperScope?",
)
replace_once(
    paper,
    "    private var effectiveScope: CourseRelationPaperScope {\n        let candidate = scope ?? defaultScope",
    "    private var effectiveScope: CourseRelationPaperScope {\n        if !allowsWorkspaceScopes,\n           let courseID = store.courseWorkspaceCourseID,\n           store.courses.contains(where: { $0.id == courseID }) {\n            return .course(courseID)\n        }\n\n        let candidate = scope ?? defaultScope",
)
replace_once(
    paper,
    "                let showCourseRail = !isCompact && proxy.size.width >= 760",
    "                let showCourseRail = allowsWorkspaceScopes\n                    && !isCompact\n                    && proxy.size.width >= 760",
)
replace_once(
    paper,
    "        .onChange(of: store.courseWorkspaceCourseID) { _, newID in\n            // Follow course switches from the title menu unless user picked a non-course filter.",
    "        .onChange(of: store.courseWorkspaceCourseID) { _, newID in\n            if !allowsWorkspaceScopes {\n                if let newID,\n                   store.courses.contains(where: { $0.id == newID }) {\n                    scope = .course(newID)\n                }\n                return\n            }\n\n            // Follow course switches from the title menu unless user picked a non-course filter.",
)
replace_once(
    paper,
    "            if isCompact {\n                scopeMenu",
    "            if isCompact && allowsWorkspaceScopes {\n                scopeMenu",
)

workspace = "Sources/WeiBei/Views/CourseDocNoteWorkspaceView.swift"
replace_once(
    workspace,
    '''        } else {
            CourseRelationPaperView(
                lens: $lens,
                search: search,
                selectedNoteID: $selectedNoteID,
                selectedMaterialID: $selectedMaterialID,
                isCompact: isCompact
            )
        }
''',
    '''        } else if explicitLinkCount == 0 {
            VStack(spacing: 18) {
                CourseEmptyState(
                    title: store.ui(
                        "还没有文档与笔记的明确关联",
                        "No explicit doc–note links yet"
                    ),
                    detail: store.ui(
                        "先回到列表，选择一份文档，再勾选相关笔记。关系图只展示真实保存的关联。",
                        "Return to List, select a doc, and check its related notes. The map only shows saved links."
                    ),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )

                Button(store.ui("返回列表建立关联", "Link in List")) {
                    withAnimation(WeiBeiMotion.panel) {
                        presentation = .list
                    }
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        } else {
            CourseRelationPaperView(
                lens: $lens,
                search: search,
                selectedNoteID: $selectedNoteID,
                selectedMaterialID: $selectedMaterialID,
                isCompact: isCompact,
                allowsWorkspaceScopes: false
            )
        }
''',
)
