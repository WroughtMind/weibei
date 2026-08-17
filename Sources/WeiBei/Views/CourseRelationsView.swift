import SwiftUI

struct CourseRelationsView: View {
    @Binding var lens: CourseRelationLens
    let search: String
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    var showsGraph = false
    let isCompact: Bool
    var onEditLinks: (() -> Void)? = nil
    var createNote: (() -> Void)? = nil

    var body: some View {
        CourseDocNoteWorkspaceView(
            lens: $lens,
            search: search,
            selectedNoteID: $selectedNoteID,
            selectedMaterialID: $selectedMaterialID,
            showsGraph: showsGraph,
            isCompact: isCompact,
            onEditLinks: onEditLinks,
            createNote: createNote
        )
    }
}
