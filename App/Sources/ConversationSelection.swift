import UIKit
import Litext

final class ConversationSelection: NSObject, TextLabelViewDelegate, UIContextMenuInteractionDelegate {
    struct Position { let blockID: String; let character: Int }
    private struct AttachmentSelection {
        let blockID: String
        let index: Int
        let range: NSRange
    }
    private final class Binding {
        weak var body: BlockView?
        weak var label: TextLabelView?
        weak var forwardingDelegate: TextLabelViewDelegate?
        let attachmentIndex: Int?
        init(body: BlockView, label: TextLabelView, attachmentIndex: Int?, forwardingDelegate: TextLabelViewDelegate?) {
            self.body = body
            self.label = label
            self.attachmentIndex = attachmentIndex
            self.forwardingDelegate = forwardingDelegate
        }
        var isCurrent: Bool {
            guard let body, let label else { return false }
            if let attachmentIndex {
                let labels = body.attachmentLabels
                return labels.indices.contains(attachmentIndex) && labels[attachmentIndex] === label
            }
            return body.label === label
        }
    }
    private weak var controller: ConversationController?
    private var bindings: [ObjectIdentifier: Binding] = [:]
    private var origin: Position?
    private var end: Position?
    private var attachmentSelection: AttachmentSelection?
    private var pressOrigin: Position?
    private var pressLocation: CGPoint?
    private weak var pressLabel: TextLabelView?
    private var dragging = false
    private var painting = false
    private weak var observedScroller: UIScrollView?
    private var scrollObservation: NSKeyValueObservation?
    private(set) var isInteracting = false
    var changed: (() -> Void)?
    var geometryChanged: (() -> Void)?

    var hasSelection: Bool {
        if let attachmentSelection {
            return attachmentSelection.range.length > 0
                && controller?.messages.flatMap(\.blocks).contains(where: { $0.id == attachmentSelection.blockID }) == true
        }
        guard let selection = orderedSelection() else { return false }
        return selection.start.blockID != selection.end.blockID || selection.start.character != selection.end.character
    }
    var ownsFirstResponder: Bool { bindings.values.contains { $0.isCurrent && $0.label?.isFirstResponder == true } }
    init(controller: ConversationController) { self.controller = controller }

    func bind(_ body: BlockView) {
        bindings = bindings.filter { $0.value.body != nil && $0.value.label != nil }
        bind(body.label, to: body, attachmentIndex: nil)
        for (index, label) in body.attachmentLabels.enumerated() { bind(label, to: body, attachmentIndex: index) }
        paint(body)
    }
    private func bind(_ label: TextLabelView, to body: BlockView, attachmentIndex: Int?) {
        let key = ObjectIdentifier(label)
        let forwarding = label.delegate === self ? bindings[key]?.forwardingDelegate : label.delegate
        bindings[key] = Binding(body: body, label: label, attachmentIndex: attachmentIndex, forwardingDelegate: forwarding)
        if label.delegate !== self {
            label.delegate = self
            for interaction in label.interactions where interaction is UIContextMenuInteraction { label.removeInteraction(interaction) }
            label.addInteraction(UIContextMenuInteraction(delegate: self))
        }
        // Markdown reconfiguration can restore this color even with the same
        // delegate. Only the conversation's projected highlight may be visible.
        if label.selectionBackgroundColor != .clear { label.selectionBackgroundColor = .clear }
        label.isAccessibilityElement = true
        label.accessibilityLabel = label.attributedText.string
    }
    private var bodies: [BlockView] {
        var unique: [ObjectIdentifier: BlockView] = [:]
        for binding in bindings.values {
            if let body = binding.body { unique[ObjectIdentifier(body)] = body }
        }
        return Array(unique.values)
    }
    func clear() {
        origin = nil; end = nil; attachmentSelection = nil
        pressOrigin = nil; pressLocation = nil; pressLabel = nil; dragging = false; isInteracting = false
        scrollObservation = nil; observedScroller = nil
        let wasPainting = painting
        painting = true
        for binding in bindings.values { binding.label?.selectionRange = nil }
        for block in controller?.messages.flatMap(\.blocks) ?? [] { block.attachmentSelections = [] }
        painting = wasPainting
        paintAll()
        changed?()
    }
    func select(from: Position, to: Position) {
        origin = from; end = to; attachmentSelection = nil
        paintAll()
        changed?()
    }
    func reconcileWithMessages() {
        if (origin != nil || attachmentSelection != nil), !hasSelection { clear() }
        else { paintAll(); geometryChanged?() }
    }
    func beginInteraction(at point: CGPoint, hitView: UIView?) {
        clear()
        isInteracting = true
        pressLocation = controller?.collection.convert(point, to: controller?.view)
        var target = hitView
        while let view = target {
            if let binding = bindings[ObjectIdentifier(view)], binding.isCurrent,
               let body = binding.body, let label = binding.label, let id = body.record?.id {
                pressLabel = label
                if binding.attachmentIndex == nil, let controller {
                    let local = controller.collection.convert(point, to: body)
                    let start = Position(blockID: id, character: body.character(at: local))
                    pressOrigin = start
                    origin = start; end = start
                }
                break
            }
            target = view.superview
        }
        changed?()
    }
    func endInteraction() {
        isInteracting = false
        pressOrigin = nil; pressLocation = nil; pressLabel = nil; dragging = false
        // The underlying label still completes touchesEnded (and word-selection
        // callbacks) in this event. Present after that, using the current state.
        DispatchQueue.main.async { [weak self] in self?.changed?() }
    }
    func textLabelView(_ label: TextLabelView, didChangeSelection range: NSRange?) {
        guard !painting, let binding = bindings[ObjectIdentifier(label)], binding.isCurrent,
              let body = binding.body, !body.isRestoringInteractionState, let id = body.record?.id,
              pressLabel === label || label.isFirstResponder else { return }
        // Nil includes zero-length presses and Litext's sibling deduplication.
        // A pressed attachment can collapse its own local range; body dragging
        // instead follows explicit positions, including when Litext emits no drag.
        guard let range else {
            if isInteracting, pressLabel === label, binding.attachmentIndex != nil {
                attachmentSelection = nil
                paintAll()
                changed?()
            }
            return
        }
        if let index = binding.attachmentIndex {
            origin = nil; end = nil
            attachmentSelection = AttachmentSelection(blockID: id, index: index, range: range)
        } else {
            guard !dragging else { return }
            // A double/triple click or keyboard selection owns the entire local
            // range. A drag is replaced below with its actual pressed origin.
            origin = Position(blockID: id, character: range.location)
            end = Position(blockID: id, character: NSMaxRange(range))
            attachmentSelection = nil
        }
        paintAll()
        changed?()
    }
    func textLabelView(_ label: TextLabelView, didDragSelectionAt point: CGPoint) {
        guard let binding = bindings[ObjectIdentifier(label)], binding.isCurrent,
              binding.attachmentIndex != nil else { return }
        geometryChanged?()
    }
    func moveInteraction(at point: CGPoint) {
        guard isInteracting, let controller, let pressOrigin, let pressLocation else { return }
        let viewportPoint = controller.collection.convert(point, to: controller.view)
        // Match the locked Litext renderer's click/drag distinction. Test this
        // before autoscrolling, then keep updating even when a drag returns home.
        guard dragging || hypot(viewportPoint.x - pressLocation.x, viewportPoint.y - pressLocation.y) > 3 else { return }
        dragging = true
        var location = point
        let edge: CGFloat = 20
        let top = controller.collection.contentOffset.y
        let bottom = top + controller.collection.bounds.height
        if location.y < top + edge || location.y > bottom - edge {
            let shift = location.y < top + edge ? location.y - top - edge : location.y - bottom + edge
            controller.selectionScroll(by: shift)
            location = controller.view.convert(viewportPoint, to: controller.collection)
        }
        let candidates = controller.collection.indexPathsForVisibleItems.sorted().compactMap { path -> (CGRect, BlockView)? in
            guard let body = (controller.collection.cellForItem(at: path) as? MessageCell)?.body,
                  case .markdown = body.record?.kind,
                  let frame = controller.collection.layoutAttributesForItem(at: path)?.frame else { return nil }
            return (frame, body)
        }
        guard let target = candidates.min(by: { distance(location.y, to: $0.0) < distance(location.y, to: $1.0) }),
              let id = target.1.record?.id else { return }
        let local = controller.collection.convert(location, to: target.1)
        let next = Position(blockID: id, character: target.1.character(at: local))
        origin = pressOrigin
        end = next
        attachmentSelection = nil
        paintAll()
        changed?()
    }
    private func distance(_ y: CGFloat, to rect: CGRect) -> CGFloat { max(rect.minY - y, y - rect.maxY, 0) }
    func textLabelView(_ label: TextLabelView, didTapHighlightRegion region: TextLabel.HighlightRegion, at point: CGPoint) {
        guard let binding = bindings[ObjectIdentifier(label)], binding.isCurrent else { return }
        binding.forwardingDelegate?.textLabelView(label, didTapHighlightRegion: region, at: point)
    }
    private func orderedSelection() -> (blocks: [PreparedBlock], start: Position, end: Position, forward: Bool)? {
        guard let controller, let origin, let end else { return nil }
        let blocks = controller.messages.flatMap(\.blocks)
        guard let a = blocks.firstIndex(where: { $0.id == origin.blockID }),
              let b = blocks.firstIndex(where: { $0.id == end.blockID }) else { return nil }
        let forward = a < b || (a == b && origin.character <= end.character)
        return (Array(blocks[min(a,b)...max(a,b)]), forward ? origin : end, forward ? end : origin, forward)
    }
    var messageID: UUID? {
        let blockID = attachmentSelection?.blockID ?? orderedSelection()?.start.blockID
        return controller?.messages.flatMap(\.blocks).first(where: { $0.id == blockID })
            .flatMap { UUID(uuidString: $0.messageID) }
    }
    private func range(for body: BlockView) -> NSRange? {
        guard let selection = orderedSelection(), let id = body.record?.id,
              selection.blocks.contains(where: { $0.id == id }) else { return nil }
        let length = body.label.attributedText.length
        let start = id == selection.start.blockID ? min(length, selection.start.character) : 0
        let end = id == selection.end.blockID ? min(length, selection.end.character) : length
        return NSRange(location: start, length: max(0, end - start))
    }
    func paint(_ body: BlockView) {
        if let selection = attachmentSelection, selection.blockID == body.record?.id {
            body.displayAttachmentSelection(at: selection.index, range: selection.range)
            observeAttachmentScroll(in: body, index: selection.index)
        } else { body.displaySelection(range(for: body)) }
    }
    private func paintAll() {
        let wasPainting = painting
        painting = true
        defer { painting = wasPainting }
        for body in bodies { paint(body) }
        if attachmentSelection == nil { scrollObservation = nil; observedScroller = nil }
    }
    private func observeAttachmentScroll(in body: BlockView, index: Int) {
        let labels = body.attachmentLabels
        guard labels.indices.contains(index) else { return }
        var ancestor = labels[index].superview
        while let view = ancestor {
            if let scroller = view as? UIScrollView {
                guard observedScroller !== scroller else { return }
                observedScroller = scroller
                scrollObservation = scroller.observe(\.contentOffset, options: .new) { [weak self] _, _ in
                    DispatchQueue.main.async { [weak self] in self?.geometryChanged?() }
                }
                return
            }
            if view === body { break }
            ancestor = view.superview
        }
    }
    func visibleSelectionRects(in view: UIView) -> [CGRect] {
        guard let controller else { return [] }
        return bodies.filter { $0.isDescendant(of: controller.collection) }.flatMap { body in
            body.displayedSelectionRects.map { body.convert($0, to: view) }
        }
    }
    var prefersFirstRect: Bool { orderedSelection()?.forward == false }
    func text() -> String {
        guard let controller else { return "" }
        let wasPainting = painting
        painting = true
        defer { painting = wasPainting; paintAll() }
        if let selection = attachmentSelection {
            guard let block = controller.messages.flatMap(\.blocks).first(where: { $0.id == selection.blockID }) else { return "" }
            let labels = controller.store.view(for: block, width: controller.bodyWidth).attachmentLabels
            guard labels.indices.contains(selection.index) else { return "" }
            return BlockView.plainText(in: labels[selection.index], range: selection.range)
        }
        guard let selection = orderedSelection(), hasSelection else { return "" }
        return selection.blocks.map { block in
            let body = controller.store.view(for: block, width: controller.bodyWidth)
            return body.copyText(range: range(for: body))
        }.joined(separator: "\n\n")
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let label = interaction.view as? TextLabelView, let body = bindings[ObjectIdentifier(label)]?.body,
              let record = body.record, let controller,
              let message = controller.messages.first(where: { $0.id == record.messageID }) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak controller] _ in
            var actions: [UIAction] = []
            actions.append(UIAction(title: CatalystInterfaceCopy.text("复制整条回答", "Copy the whole answer")) { _ in UIPasteboard.general.string = message.copyableMarkdown })
            if controller?.isFloatingConversation == true {
                actions.append(UIAction(title: CatalystInterfaceCopy.text("引用到输入框", "Quote into the input"), image: UIImage(systemName: "text.quote")) { _ in
                    controller?.quote(message.original?.text ?? message.markdown, messageID: UUID(uuidString: message.id))
                })
            }
            if let sources = message.original?.sources, !sources.isEmpty {
                actions += sources.map { source in UIAction(title: source.label, image: UIImage(systemName: "book")) { _ in controller?.openSource?(source) } }
            } else if message.original == nil {
                actions.append(UIAction(title: CatalystInterfaceCopy.text("查看来源文稿", "View source document")) { _ in controller?.openWorkspace?(0) })
            }
            return UIMenu(children: actions)
        }
    }
}
