import UIKit
import Litext

final class ConversationSelection: NSObject, TextLabelViewDelegate, UIContextMenuInteractionDelegate {
    struct Position { let blockID: String; let character: Int }
    private weak var controller: ConversationController?
    private final class WeakBody { weak var value: BlockView?; init(_ value: BlockView) { self.value = value } }
    private var bodies: [ObjectIdentifier: WeakBody] = [:]
    private var origin: Position?
    private var end: Position?
    private var painting = false
    var hasSelection: Bool { origin != nil && end != nil && (origin!.blockID != end!.blockID || origin!.character != end!.character) }
    var ownsFirstResponder: Bool { bodies.values.contains { $0.value?.label.isFirstResponder == true } }
    init(controller: ConversationController) { self.controller = controller }

    func bind(_ body: BlockView) {
        let label = body.label
        if label.delegate !== self {
            label.delegate = self
            label.selectionBackgroundColor = .clear
            for interaction in label.interactions where interaction is UIContextMenuInteraction { label.removeInteraction(interaction) }
            label.addInteraction(UIContextMenuInteraction(delegate: self))
        }
        bodies = bodies.filter { $0.value.value != nil }
        bodies[ObjectIdentifier(label)] = WeakBody(body)
        label.isAccessibilityElement = true
        label.accessibilityLabel = label.attributedText.string
    }
    func clear() {
        origin = nil; end = nil
        painting = true
        for body in bodies.values { body.value?.label.selectionRange = nil }
        painting = false
        paintAll()
    }
    func select(from: Position, to: Position) { origin = from; end = to; paintAll() }
    func textLabelView(_ label: TextLabelView, didChangeSelection range: NSRange?) {
        guard !painting, let range, let body = bodies[ObjectIdentifier(label)]?.value, let id = body.record?.id else { return }
        if range.length == 0 || origin == nil || origin?.blockID != id || !label.isInteractionInProgress {
            origin = Position(blockID: id, character: range.location)
        }
        let start = origin!.character
        end = Position(blockID: id, character: range.location < start ? range.location : NSMaxRange(range))
        paintAll()
    }
    func textLabelView(_ label: TextLabelView, didDragSelectionAt point: CGPoint) {
        guard let controller, origin != nil else { return }
        var location = label.convert(point, to: controller.collection)
        // The session controller remains the single owner of the outer offset.
        let edge: CGFloat = 20
        let top = controller.collection.contentOffset.y
        let bottom = top + controller.collection.bounds.height
        if location.y < top + edge || location.y > bottom - edge {
            let shift = location.y < top + edge ? location.y - top - edge : location.y - bottom + edge
            controller.selectionScroll(by: shift)
            location = label.convert(point, to: controller.collection)
        }
        let candidates = controller.collection.indexPathsForVisibleItems.sorted().compactMap { path -> (CGRect, BlockView)? in
            guard let body = (controller.collection.cellForItem(at: path) as? MessageCell)?.body,
                  case .markdown = body.record?.kind,
                  let frame = controller.collection.layoutAttributesForItem(at: path)?.frame else { return nil }
            return (frame, body)
        }
        guard let target = candidates.min(by: { distance(location.y, to: $0.0) < distance(location.y, to: $1.0) }),
              let id = target.1.record?.id else { return }
        let position = CGPoint(x: location.x - target.0.minX, y: location.y - target.0.minY)
        end = Position(blockID: id, character: target.1.character(at: position))
        paintAll()
    }
    private func distance(_ y: CGFloat, to rect: CGRect) -> CGFloat { max(rect.minY - y, y - rect.maxY, 0) }
    func textLabelView(_ label: TextLabelView, didTapHighlightRegion region: TextLabel.HighlightRegion, at point: CGPoint) {
        bodies[ObjectIdentifier(label)]?.value?.markdown.textLabelView(label, didTapHighlightRegion: region, at: point)
    }

    private func orderedSelection() -> (blocks: [PreparedBlock], start: Position, end: Position)? {
        guard let controller, let origin, let end else { return nil }
        let blocks = controller.messages.flatMap(\.blocks)
        guard let a = blocks.firstIndex(where: { $0.id == origin.blockID }), let b = blocks.firstIndex(where: { $0.id == end.blockID }) else { return nil }
        let forward = a < b || (a == b && origin.character <= end.character)
        return (Array(blocks[min(a,b)...max(a,b)]), forward ? origin : end, forward ? end : origin)
    }
    private func range(for body: BlockView) -> NSRange? {
        guard let selection = orderedSelection(), let id = body.record?.id,
              selection.blocks.contains(where: { $0.id == id }) else { return nil }
        let length = body.label.attributedText.length
        let start = id == selection.start.blockID ? min(length, selection.start.character) : 0
        let end = id == selection.end.blockID ? min(length, selection.end.character) : length
        return NSRange(location: start, length: max(0, end - start))
    }
    func paint(_ body: BlockView) { body.displaySelection(range(for: body)) }
    private func paintAll() {
        painting = true
        defer { painting = false }
        for item in bodies.values {
            guard let body = item.value else { continue }
            paint(body)
        }
    }
    func text() -> String {
        guard let controller, let selection = orderedSelection() else { return "" }
        painting = true
        defer { painting = false; paintAll() }
        return selection.blocks.map { block in
            let view = controller.store.view(for: block, width: controller.bodyWidth)
            return view.copyText(range: range(for: view))
        }.joined(separator: "\n\n")
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let label = interaction.view as? TextLabelView, let body = bodies[ObjectIdentifier(label)]?.value,
              let record = body.record, let controller,
              let message = controller.messages.first(where: { $0.id == record.messageID }) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self, weak controller] _ in
            var actions: [UIAction] = []
            if self?.hasSelection == true {
                actions.append(UIAction(title: "复制所选文字", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = self?.text() })
                actions.append(UIAction(title: "引用所选文字", image: UIImage(systemName: "text.quote")) { _ in controller?.quote(self?.text() ?? "") })
            }
            actions.append(UIAction(title: "复制整条回答") { _ in UIPasteboard.general.string = message.markdown })
            actions.append(UIAction(title: "查看来源材料") { _ in controller?.openWorkspace?(0) })
            return UIMenu(children: actions)
        }
    }
}
