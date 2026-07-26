import CoreGraphics
import Foundation

public enum SelectionSource: String, Codable, Hashable, Sendable {
    case document
    case note
}

public struct SelectionContext: Identifiable, Codable, Hashable {
    public var id: UUID
    public var text: String
    public var source: SelectionSource
    public var ownerTitle: String
    public var isEditable: Bool

    public init(id: UUID = UUID(), text: String, source: SelectionSource, ownerTitle: String, isEditable: Bool = true) {
        self.id = id
        self.text = text
        self.source = source
        self.ownerTitle = ownerTitle
        self.isEditable = isEditable
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch source {
        case .document:
            return language.text("文档选区：\(ownerTitle)", "Document selection: \(ownerTitle)")
        case .note:
            return language.text("笔记选区：\(ownerTitle)", "Note selection: \(ownerTitle)")
        }
    }

    public var isNoteSelection: Bool {
        source == .note
    }

    public var isReplaceableNoteSelection: Bool {
        source == .note && isEditable
    }
}

/// A durable link between a selected text span the user asked about and the chat turns that followed.
/// Used for underline marks in the reader/note and for reopening the floating selection agent.
public struct SelectionAskThread: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var selectionText: String
    public var source: SelectionSource
    public var ownerTitle: String
    /// Material or notebook item id when known.
    public var itemID: String?
    /// Conversation message ids (user + assistant) belonging to this selection thread.
    public var messageIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        selectionText: String,
        source: SelectionSource,
        ownerTitle: String,
        itemID: String? = nil,
        messageIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.selectionText = selectionText
        self.source = source
        self.ownerTitle = ownerTitle
        self.itemID = itemID
        self.messageIDs = messageIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var normalizedText: String {
        SelectionAttachmentMerge.normalized(selectionText)
    }
}

public enum SelectionAttachmentMerge {
    public static func mergedText(existing: String, incoming: String, withinSelectionGesture: Bool) -> String? {
        let existingText = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingText = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExisting = normalized(existingText)
        let normalizedIncoming = normalized(incomingText)
        guard !normalizedExisting.isEmpty, !normalizedIncoming.isEmpty else { return nil }
        if normalizedExisting.contains(normalizedIncoming) { return existingText }
        if normalizedIncoming.contains(normalizedExisting) { return incomingText }
        guard withinSelectionGesture else { return nil }
        if let merged = overlappedText(existingText, incomingText) {
            return merged
        }
        guard canStitchAdjacentText(existingText, incomingText) else { return nil }
        return existingText + incomingText
    }

    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined()
    }

    public static func containsSelection(_ container: String, fragment: String) -> Bool {
        let normalizedContainer = normalized(container)
        let normalizedFragment = normalized(fragment)
        guard !normalizedContainer.isEmpty, !normalizedFragment.isEmpty else { return false }
        return normalizedContainer.contains(normalizedFragment)
    }

    private static func overlappedText(_ existing: String, _ incoming: String) -> String? {
        let maxLength = min(existing.count, incoming.count)
        guard maxLength > 0 else { return nil }
        for length in stride(from: maxLength, through: 1, by: -1) {
            let suffix = existing.suffix(length)
            let prefix = incoming.prefix(length)
            if suffix == prefix {
                return existing + incoming.dropFirst(length)
            }
            let incomingSuffix = incoming.suffix(length)
            let existingPrefix = existing.prefix(length)
            if incomingSuffix == existingPrefix {
                return incoming + existing.dropFirst(length)
            }
        }
        return nil
    }

    private static func canStitchAdjacentText(_ existing: String, _ incoming: String) -> Bool {
        let blockedPrefixes = ["#", ">", "-", "*", "|", "```", "$$", "!["]
        guard !blockedPrefixes.contains(where: incoming.hasPrefix) else { return false }
        guard !existing.hasSuffix("\n"), !incoming.hasPrefix("\n") else { return false }
        let terminal = CharacterSet(charactersIn: "。！？!?；;：:")
        guard let last = existing.unicodeScalars.last else { return false }
        return !terminal.contains(last) || incoming.count <= 12
    }
}

public struct FloatingAgentCoordinate: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum SelectionAnchorCoordinate {
    public static func y(_ contentY: Double, contentHeight: Double, contentViewIsFlipped: Bool) -> Double {
        contentViewIsFlipped ? contentY : contentHeight - contentY
    }
}

public enum SelectionFloatingAgentPlacement {
    public static let expandedHalfWidth = 230.0
    public static let compactHalfWidth = 82.0
    /// Approximate half-height used to keep an expanded panel on-canvas.
    public static let expandedHalfHeight = 210.0
    public static let compactHalfHeight = 28.0

    public static func isVisible(
        surface: AgentSurface,
        hasSelection: Bool,
        hasAnchor: Bool,
        pinned: Bool,
        keepOpen: Bool = false
    ) -> Bool {
        guard surface == .selectionFloat else { return false }
        // Pinned or mid-answer floats stay even without a live selection anchor.
        if pinned || keepOpen { return true }
        return hasSelection && hasAnchor
    }

    public static func position(
        anchor: FloatingAgentCoordinate?,
        canvas: FloatingAgentCoordinate,
        topInset: Double = 0,
        surfaceHalfWidth: Double = expandedHalfWidth,
        prefersAnchorCenter: Bool = false
    ) -> FloatingAgentCoordinate {
        let edgePadding = 18.0
        let anchorGap = 12.0
        let verticalGap = prefersAnchorCenter ? 10.0 : 14.0
        let contentCanvas = FloatingAgentCoordinate(x: canvas.x, y: max(1, canvas.y - topInset))
        let isExpanded = surfaceHalfWidth >= expandedHalfWidth - 0.5
        let surfaceHalfHeight = isExpanded ? expandedHalfHeight : compactHalfHeight
        let fallback = FloatingAgentCoordinate(
            x: contentCanvas.x - surfaceHalfWidth - edgePadding,
            y: min(contentCanvas.y - surfaceHalfHeight - edgePadding, contentCanvas.y * 0.42)
        )
        let anchor = anchor.map { FloatingAgentCoordinate(x: $0.x, y: max(0, $0.y - topInset)) } ?? fallback
        let minimumX = surfaceHalfWidth + edgePadding
        let maximumX = contentCanvas.x - surfaceHalfWidth - edgePadding
        let rightSideX = anchor.x + surfaceHalfWidth + anchorGap
        let leftSideX = anchor.x - surfaceHalfWidth - anchorGap
        let preferredX: Double
        if prefersAnchorCenter {
            preferredX = anchor.x
        } else if rightSideX <= maximumX {
            preferredX = rightSideX
        } else if leftSideX >= minimumX {
            preferredX = leftSideX
        } else {
            preferredX = clamp(anchor.x, min: minimumX, max: maximumX)
        }
        let minimumY = surfaceHalfHeight + edgePadding
        let maximumY = contentCanvas.y - surfaceHalfHeight - edgePadding
        // Prefer just below the mark; if that clips, sit above it.
        let belowY = anchor.y + verticalGap + (prefersAnchorCenter ? 0 : surfaceHalfHeight * 0.15)
        let aboveY = anchor.y - verticalGap - (prefersAnchorCenter ? 0 : surfaceHalfHeight * 0.15)
        let preferredY: Double
        if belowY <= maximumY {
            preferredY = belowY
        } else if aboveY >= minimumY {
            preferredY = aboveY
        } else {
            preferredY = clamp(anchor.y, min: minimumY, max: maximumY)
        }
        return FloatingAgentCoordinate(
            x: clamp(preferredX, min: minimumX, max: maximumX),
            y: clamp(preferredY, min: minimumY, max: max(minimumY, maximumY))
        )
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        guard maximum >= minimum else { return (minimum + maximum) / 2 }
        return Swift.max(minimum, Swift.min(value, maximum))
    }
}
