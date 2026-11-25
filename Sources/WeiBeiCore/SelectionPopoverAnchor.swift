import Foundation

/// The final selected line edge in window-content coordinates, including drag direction.
public struct SelectionPopoverAnchor: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var prefersAbove: Bool
    public var textAnchor: SelectionTextAnchor?
    /// Vertical span of the selection, measured in the same space as the endpoint.
    public var selectionHeight: CGFloat?

    public init(x: CGFloat, y: CGFloat, prefersAbove: Bool = false, textAnchor: SelectionTextAnchor? = nil,
                selectionHeight: CGFloat? = nil) {
        self.x = x
        self.y = y
        self.prefersAbove = prefersAbove
        self.textAnchor = textAnchor
        self.selectionHeight = selectionHeight
    }
}
