import SwiftUI

struct CourseRelationsView: View {
    @Binding var lens: CourseRelationLens
    let search: String
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    @Binding var presentation: CourseDocNotePresentation
    let isCompact: Bool

    var body: some View {
        CourseDocNoteWorkspaceView(
            lens: $lens,
            search: search,
            selectedNoteID: $selectedNoteID,
            selectedMaterialID: $selectedMaterialID,
            presentation: $presentation,
            isCompact: isCompact
        )
    }
}
