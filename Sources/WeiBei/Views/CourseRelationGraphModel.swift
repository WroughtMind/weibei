import Foundation
import SwiftUI
import WeiBeiCore

enum CourseRelationPaperScope: Equatable, Identifiable {
    case course(UUID)
    case all
    case unassigned
    case unlinked

    var id: String {
        switch self {
        case .course(let id):
            return "course-\(id.uuidString)"
        case .all:
            return "all"
        case .unassigned:
            return "unassigned"
        case .unlinked:
            return "unlinked"
        }
    }
}

struct CourseRelationGraphItem: Hashable {
    enum Kind: String, Hashable {
        case material
        case note
    }

    var itemID: String
    var kind: Kind
    var title: String
    var subtitle: String
    var kindLabel: String
    var symbolName: String

    var nodeID: String {
        "\(kind.rawValue):\(itemID)"
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || subtitle.localizedCaseInsensitiveContains(query)
            || kindLabel.localizedCaseInsensitiveContains(query)
            || itemID.localizedCaseInsensitiveContains(query)
    }
}

struct CourseRelationGraphNode: Identifiable, Hashable {
    var item: CourseRelationGraphItem
    var relationCount: Int
    var isSelected: Bool
    var directlyMatchedSearch: Bool

    var id: String {
        item.nodeID
    }

    var itemID: String {
        item.itemID
    }

    var kind: CourseRelationGraphItem.Kind {
        item.kind
    }
}

struct CourseRelationGraphEdge: Identifiable, Hashable {
    var materialID: String
    var noteID: String
    var count: Int

    var id: String {
        "\(materialID)\u{1F}\(noteID)"
    }

    var materialNodeID: String {
        "\(CourseRelationGraphItem.Kind.material.rawValue):\(materialID)"
    }

    var noteNodeID: String {
        "\(CourseRelationGraphItem.Kind.note.rawValue):\(noteID)"
    }

    func touches(_ nodeID: String) -> Bool {
        materialNodeID == nodeID || noteNodeID == nodeID
    }
}

enum CourseRelationGraphProminence: Equatable {
    case focused
    case related
    case normal
    case mist
}

struct CourseRelationPlacedNode: Identifiable {
    var node: CourseRelationGraphNode
    var frame: CGRect

    var id: String {
        node.id
    }
}

struct CourseRelationPlacedEdge: Identifiable {
    var edge: CourseRelationGraphEdge
    var from: CGPoint
    var to: CGPoint

    var id: String {
        edge.id
    }
}

struct CourseRelationGraphLayout {
    var nodes: [CourseRelationPlacedNode]
    var edges: [CourseRelationPlacedEdge]
    var size: CGSize
}

struct CourseRelationGraphModel {
    var materials: [CourseRelationGraphNode]
    var notes: [CourseRelationGraphNode]
    var edges: [CourseRelationGraphEdge]
    var hiddenNodeCount: Int
    var totalNodeCount: Int
    var totalEdgeCount: Int
    var query: String
    var selectedNoteID: String?
    var selectedMaterialID: String?

    var visibleNodes: [CourseRelationGraphNode] {
        materials + notes
    }

    var hasContent: Bool {
        !visibleNodes.isEmpty
    }

    init(
        materials rawMaterials: [CourseRelationGraphItem],
        notes rawNotes: [CourseRelationGraphItem],
        links: [NoteSourceLink],
        query: String,
        selectedNoteID: String?,
        selectedMaterialID: String?,
        showsOnlyUnlinked: Bool,
        maxVisibleNodes: Int
    ) {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = cleanedQuery
        self.selectedNoteID = selectedNoteID
        self.selectedMaterialID = selectedMaterialID

        let materialIDs = Set(rawMaterials.map(\.itemID))
        let noteIDs = Set(rawNotes.map(\.itemID))
        let groupedLinks = Dictionary(
            grouping: links.filter {
                materialIDs.contains($0.sourceItemID)
                    && noteIDs.contains($0.noteItemID)
                    && $0.sourceItemID != $0.noteItemID
            },
            by: { "\($0.sourceItemID)\u{1F}\($0.noteItemID)" }
        )

        let allEdges = groupedLinks.values.compactMap { group -> CourseRelationGraphEdge? in
            guard let first = group.first else { return nil }
            return CourseRelationGraphEdge(
                materialID: first.sourceItemID,
                noteID: first.noteItemID,
                count: max(1, group.count)
            )
        }
        .sorted {
            if $0.materialID == $1.materialID { return $0.noteID < $1.noteID }
            return $0.materialID < $1.materialID
        }

        var materialDegree: [String: Int] = [:]
        var noteDegree: [String: Int] = [:]
        for edge in allEdges {
            materialDegree[edge.materialID, default: 0] += edge.count
            noteDegree[edge.noteID, default: 0] += edge.count
        }

        let matchedMaterialIDs = Set(rawMaterials.filter { $0.matches(cleanedQuery) }.map(\.itemID))
        let matchedNoteIDs = Set(rawNotes.filter { $0.matches(cleanedQuery) }.map(\.itemID))
        var searchNeighborMaterialIDs = matchedMaterialIDs
        var searchNeighborNoteIDs = matchedNoteIDs
        if !cleanedQuery.isEmpty {
            for edge in allEdges {
                if matchedMaterialIDs.contains(edge.materialID) {
                    searchNeighborNoteIDs.insert(edge.noteID)
                }
                if matchedNoteIDs.contains(edge.noteID) {
                    searchNeighborMaterialIDs.insert(edge.materialID)
                }
            }
        }

        var candidateMaterials = rawMaterials.filter { item in
            if showsOnlyUnlinked, materialDegree[item.itemID, default: 0] > 0 { return false }
            guard !cleanedQuery.isEmpty else { return true }
            return searchNeighborMaterialIDs.contains(item.itemID)
        }
        var candidateNotes = rawNotes.filter { item in
            if showsOnlyUnlinked, noteDegree[item.itemID, default: 0] > 0 { return false }
            guard !cleanedQuery.isEmpty else { return true }
            return searchNeighborNoteIDs.contains(item.itemID)
        }

        let allCandidateCount = candidateMaterials.count + candidateNotes.count
        if allCandidateCount > maxVisibleNodes {
            let materialBudget = max(8, Int(Double(maxVisibleNodes) * 0.48))
            let noteBudget = max(8, maxVisibleNodes - materialBudget)
            candidateMaterials = Self.prioritizedItems(
                candidateMaterials,
                relationDegree: materialDegree,
                matchedIDs: matchedMaterialIDs,
                focusID: selectedMaterialID,
                oneHopIDs: Set(allEdges.filter { $0.noteID == selectedNoteID }.map(\.materialID)),
                limit: min(materialBudget, candidateMaterials.count)
            )
            candidateNotes = Self.prioritizedItems(
                candidateNotes,
                relationDegree: noteDegree,
                matchedIDs: matchedNoteIDs,
                focusID: selectedNoteID,
                oneHopIDs: Set(allEdges.filter { $0.materialID == selectedMaterialID }.map(\.noteID)),
                limit: min(noteBudget, candidateNotes.count)
            )
        }

        let visibleMaterialIDs = Set(candidateMaterials.map(\.itemID))
        let visibleNoteIDs = Set(candidateNotes.map(\.itemID))
        let visibleEdges = showsOnlyUnlinked ? [] : allEdges.filter {
            visibleMaterialIDs.contains($0.materialID) && visibleNoteIDs.contains($0.noteID)
        }

        materials = candidateMaterials.map {
            CourseRelationGraphNode(
                item: $0,
                relationCount: materialDegree[$0.itemID, default: 0],
                isSelected: $0.itemID == selectedMaterialID,
                directlyMatchedSearch: matchedMaterialIDs.contains($0.itemID)
            )
        }
        notes = candidateNotes.map {
            CourseRelationGraphNode(
                item: $0,
                relationCount: noteDegree[$0.itemID, default: 0],
                isSelected: $0.itemID == selectedNoteID,
                directlyMatchedSearch: matchedNoteIDs.contains($0.itemID)
            )
        }
        edges = visibleEdges
        hiddenNodeCount = max(0, allCandidateCount - materials.count - notes.count)
        totalNodeCount = allCandidateCount
        totalEdgeCount = allEdges.count
    }

    func focusNodeID(hoveredNodeID: String?) -> String? {
        if let hoveredNodeID, visibleNodes.contains(where: { $0.id == hoveredNodeID }) {
            return hoveredNodeID
        }
        if let selectedMaterialID,
           materials.contains(where: { $0.itemID == selectedMaterialID }) {
            return "\(CourseRelationGraphItem.Kind.material.rawValue):\(selectedMaterialID)"
        }
        if let selectedNoteID,
           notes.contains(where: { $0.itemID == selectedNoteID }) {
            return "\(CourseRelationGraphItem.Kind.note.rawValue):\(selectedNoteID)"
        }
        return nil
    }

    func nodeProminence(_ node: CourseRelationGraphNode, hoveredNodeID: String?) -> CourseRelationGraphProminence {
        guard let focusNodeID = focusNodeID(hoveredNodeID: hoveredNodeID) else {
            return node.isSelected ? .focused : .normal
        }
        if node.id == focusNodeID { return .focused }
        if edges.contains(where: { $0.touches(focusNodeID) && $0.touches(node.id) }) {
            return .related
        }
        return .mist
    }

    func edgeProminence(_ edge: CourseRelationGraphEdge, hoveredNodeID: String?) -> CourseRelationGraphProminence {
        guard let focusNodeID = focusNodeID(hoveredNodeID: hoveredNodeID) else {
            return .normal
        }
        return edge.touches(focusNodeID) ? .focused : .mist
    }

    func paperSize(forWidth width: CGFloat, compact: Bool) -> CGSize {
        if compact {
            let rows = max(materials.count + notes.count, 5)
            return CGSize(width: max(width, 360), height: max(520, CGFloat(rows) * 74 + 180))
        }
        let sideCount = max(materials.count, notes.count, 4)
        return CGSize(width: max(width, 860), height: max(620, CGFloat(sideCount) * 92 + 180))
    }

    func layout(in size: CGSize) -> CourseRelationGraphLayout {
        let nodeSize = CGSize(width: min(230, max(190, size.width * 0.22)), height: 74)
        let top: CGFloat = 92
        let bottom: CGFloat = 86
        let usableHeight = max(1, size.height - top - bottom)
        let materialStep = materials.count <= 1 ? 0 : usableHeight / CGFloat(materials.count - 1)
        let noteStep = notes.count <= 1 ? 0 : usableHeight / CGFloat(notes.count - 1)
        let materialX = min(max(150, size.width * 0.28), size.width * 0.42)
        let noteX = max(min(size.width - 150, size.width * 0.72), size.width * 0.58)

        let materialNodes = materials.enumerated().map { index, node in
            let wave = CGFloat((index % 3) - 1) * 16
            let y = top + (materials.count <= 1 ? usableHeight * 0.42 : CGFloat(index) * materialStep)
            return CourseRelationPlacedNode(
                node: node,
                frame: CGRect(
                    x: materialX - nodeSize.width / 2 + wave,
                    y: y - nodeSize.height / 2,
                    width: nodeSize.width,
                    height: nodeSize.height
                )
            )
        }
        let noteNodes = notes.enumerated().map { index, node in
            let wave = CGFloat((index % 3) - 1) * -16
            let y = top + (notes.count <= 1 ? usableHeight * 0.56 : CGFloat(index) * noteStep)
            return CourseRelationPlacedNode(
                node: node,
                frame: CGRect(
                    x: noteX - nodeSize.width / 2 + wave,
                    y: y - nodeSize.height / 2,
                    width: nodeSize.width,
                    height: nodeSize.height
                )
            )
        }
        let placedNodes = materialNodes + noteNodes
        let framesByID = Dictionary(uniqueKeysWithValues: placedNodes.map { ($0.id, $0.frame) })
        let materialFanOffsets = Self.fanOffsets(
            groupedEdges: Dictionary(grouping: edges, by: { $0.materialID }),
            oppositeNodeID: { $0.noteNodeID },
            framesByID: framesByID
        )
        let noteFanOffsets = Self.fanOffsets(
            groupedEdges: Dictionary(grouping: edges, by: { $0.noteID }),
            oppositeNodeID: { $0.materialNodeID },
            framesByID: framesByID
        )
        let placedEdges = edges.compactMap { edge -> CourseRelationPlacedEdge? in
            guard let materialFrame = framesByID[edge.materialNodeID],
                  let noteFrame = framesByID[edge.noteNodeID]
            else { return nil }
            return CourseRelationPlacedEdge(
                edge: edge,
                from: CGPoint(
                    x: materialFrame.maxX - 2,
                    y: materialFrame.midY + materialFanOffsets[edge.id, default: 0]
                ),
                to: CGPoint(
                    x: noteFrame.minX + 2,
                    y: noteFrame.midY + noteFanOffsets[edge.id, default: 0]
                )
            )
        }
        return CourseRelationGraphLayout(nodes: placedNodes, edges: placedEdges, size: size)
    }

    private static func fanOffsets(
        groupedEdges: [String: [CourseRelationGraphEdge]],
        oppositeNodeID: (CourseRelationGraphEdge) -> String,
        framesByID: [String: CGRect]
    ) -> [String: CGFloat] {
        var offsets: [String: CGFloat] = [:]
        for groupedEdge in groupedEdges.values {
            let sortedEdges = groupedEdge.sorted { lhs, rhs in
                let lhsY = framesByID[oppositeNodeID(lhs)]?.midY ?? 0
                let rhsY = framesByID[oppositeNodeID(rhs)]?.midY ?? 0
                if lhsY == rhsY { return lhs.id < rhs.id }
                return lhsY < rhsY
            }
            guard sortedEdges.count > 1 else {
                if let edge = sortedEdges.first { offsets[edge.id] = 0 }
                continue
            }
            let maximumSpan: CGFloat = 40
            let step = min(11, maximumSpan / CGFloat(sortedEdges.count - 1))
            let firstOffset = -step * CGFloat(sortedEdges.count - 1) / 2
            for (index, edge) in sortedEdges.enumerated() {
                offsets[edge.id] = firstOffset + CGFloat(index) * step
            }
        }
        return offsets
    }

    private static func prioritizedItems(
        _ items: [CourseRelationGraphItem],
        relationDegree: [String: Int],
        matchedIDs: Set<String>,
        focusID: String?,
        oneHopIDs: Set<String>,
        limit: Int
    ) -> [CourseRelationGraphItem] {
        Array(items.sorted { lhs, rhs in
            let lhsScore = priority(
                lhs,
                relationDegree: relationDegree,
                matchedIDs: matchedIDs,
                focusID: focusID,
                oneHopIDs: oneHopIDs
            )
            let rhsScore = priority(
                rhs,
                relationDegree: relationDegree,
                matchedIDs: matchedIDs,
                focusID: focusID,
                oneHopIDs: oneHopIDs
            )
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }.prefix(limit))
    }

    private static func priority(
        _ item: CourseRelationGraphItem,
        relationDegree: [String: Int],
        matchedIDs: Set<String>,
        focusID: String?,
        oneHopIDs: Set<String>
    ) -> Int {
        var score = relationDegree[item.itemID, default: 0] * 12
        if item.itemID == focusID { score += 10_000 }
        if oneHopIDs.contains(item.itemID) { score += 5_000 }
        if matchedIDs.contains(item.itemID) { score += 2_500 }
        return score
    }
}
