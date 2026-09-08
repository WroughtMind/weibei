import Foundation

/// The final selected line edge in window-content coordinates, including drag direction.
public struct SelectionPopoverAnchor: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var prefersAbove: Bool
    public var textAnchor: SelectionTextAnchor?

    public init(x: CGFloat, y: CGFloat, prefersAbove: Bool = false, textAnchor: SelectionTextAnchor? = nil) {
        self.x = x
        self.y = y
        self.prefersAbove = prefersAbove
        self.textAnchor = textAnchor
    }
}
