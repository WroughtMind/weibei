import SwiftUI

struct CourseRelationsView: View {
    @Binding var lens: CourseRelationLens
    let search: String
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    let isCompact: Bool

    var body: some View {
        CourseRelationPaperView(
            lens: $lens,
            search: search,
            selectedNoteID: $selectedNoteID,
            selectedMaterialID: $selectedMaterialID,
            isCompact: isCompact
        )
    }
}
