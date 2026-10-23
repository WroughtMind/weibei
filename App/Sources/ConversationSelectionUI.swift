import UIKit
import SwiftUI
import WeiBeiCore

/// Reports the complete SwiftUI floating panel, including its header and composer.
/// Reading these native bounds also accounts for the panel's placement transform.
struct ConversationSelectionPanelProbe: UIViewRepresentable {
    let position: CGPoint?
    func makeUIView(context: Context) -> PanelView { PanelView() }
    func updateUIView(_ view: PanelView, context: Context) {
        view.setNeedsLayout()
        view.reportGeometry()
    }
    final class PanelView: UIView {
        static let geometryDidChange = Notification.Name("WeiBeiConversationSelectionPanelGeometryChanged")
        private static let panels = NSHashTable<PanelView>.weakObjects()
        private weak var reportedWindow: UIWindow?
        private var reportedFrame = CGRect.null
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportedWindow = nil
            reportedFrame = .null
            if window != nil {
                Self.panels.add(self)
                reportGeometry()
            } else {
                Self.panels.remove(self)
                let name = Self.geometryDidChange
                // Removal must still be reported if SwiftUI releases this probe
                // before the next main-queue turn.
                DispatchQueue.main.async { NotificationCenter.default.post(name: name, object: nil) }
            }
        }
        override func layoutSubviews() { super.layoutSubviews(); reportGeometry() }
        func reportGeometry() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let frame = window.map { self.convert(self.bounds, to: $0) } ?? .null
                guard reportedWindow !== window || reportedFrame != frame else { return }
                reportedWindow = window
                reportedFrame = frame
                NotificationCenter.default.post(name: Self.geometryDidChange, object: self)
            }
        }
        static func rectangles(in view: UIView) -> [CGRect] {
            guard let window = view.window else { return [] }
            return panels.allObjects.compactMap { panel in
                guard panel.window === window else { return nil }
                var ancestor: UIView? = panel
                while let current = ancestor {
                    if current.isHidden || current.alpha == 0 { return nil }
                    ancestor = current.superview
                }
                let frame = panel.convert(panel.bounds, to: view)
                return frame.isEmpty || frame.isNull ? nil : frame
            }
        }
    }
}

/// Observes primary presses without claiming the gesture or cancelling delivery
/// to the text, links, scroll views, or interactive attachments underneath.
final class ConversationSelectionPressObserver: UIGestureRecognizer {
    var pressed: ((CGPoint, UIView?) -> Void)?
    var moved: ((CGPoint) -> Void)?
    var released: (() -> Void)?
    private var didMove = false

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func shouldReceive(_ event: UIEvent) -> Bool {
        event.type == .touches && event.buttonMask.contains(.primary)
            && !event.modifierFlags.contains(.control)
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        didMove = false
        pressed?(touch.location(in: view), touch.view)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        didMove = true
        moved?(touch.location(in: view))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if didMove, let touch = touches.first { moved?(touch.location(in: view)) }
        released?()
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        released?()
        state = .failed
    }
}

/// A custom button avoids Catalyst's AppKit alignment decoration around system buttons.
/// The visible shape and the hit surface use the same bounds.
final class ConversationSelectionActionButton: UIButton {
    private let symbol = UIImageView()
    private let label = UILabel()
    private var ink = UIColor.label
    private var pointerInside = false
    override var isHighlighted: Bool { didSet { refreshBackground() } }
    override var alignmentRectInsets: UIEdgeInsets { .zero }

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbol.contentMode = .scaleAspectFit
        symbol.isUserInteractionEnabled = false
        label.isUserInteractionEnabled = false
        addSubview(symbol); addSubview(label)
        isAccessibilityElement = true
        layer.cornerRadius = 6
        isPointerInteractionEnabled = true
        addInteraction(UIToolTipInteraction())
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(title: String, symbol name: String, ink: UIColor, scale: CGFloat) {
        self.ink = ink
        symbol.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12 * scale))
        symbol.tintColor = ink
        label.text = title
        label.font = .systemFont(ofSize: 12 * scale, weight: .medium)
        label.textColor = ink
        accessibilityLabel = title
        interactions.compactMap { $0 as? UIToolTipInteraction }.first?.defaultToolTip = title
        refreshBackground(); setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = bounds.height / 28
        symbol.frame = CGRect(x: 6 * scale, y: 7 * scale, width: 14 * scale, height: 14 * scale)
        label.frame = CGRect(x: 25 * scale, y: 0, width: bounds.width - 30 * scale, height: bounds.height)
    }
    func setHovered(_ value: Bool) {
        pointerInside = value
        refreshBackground()
    }
    private func refreshBackground() {
        backgroundColor = ink.withAlphaComponent(isHighlighted ? 0.18 : pointerInside ? 0.10 : 0)
    }
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        setHovered(gesture.state == .began || gesture.state == .changed)
    }
}

final class ConversationSelectionActions: UIView {
    let copyButton = ConversationSelectionActionButton(frame: .zero)
    let quoteButton = ConversationSelectionActionButton(frame: .zero)
    private let material = UIVisualEffectView()
    private let separator = UIView()
    private var textScale: CGFloat = 1
    var copySelectedText: (() -> Void)?
    var quoteSelectedText: (() -> Void)?
    override var isHidden: Bool {
        didSet {
            if isHidden { copyButton.setHovered(false); quoteButton.setHovered(false) }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isOpaque = false
        accessibilityIdentifier = "conversation-selection-actions"
        material.isUserInteractionEnabled = false
        material.accessibilityElementsHidden = true
        material.clipsToBounds = true
        for child in [material, copyButton, separator, quoteButton] { addSubview(child) }
        copyButton.accessibilityIdentifier = "conversation-selection-copy"
        quoteButton.accessibilityIdentifier = "conversation-selection-quote"
        copyButton.addAction(UIAction { [weak self] _ in self?.copySelectedText?() }, for: .touchUpInside)
        quoteButton.addAction(UIAction { [weak self] _ in self?.quoteSelectedText?() }, for: .touchUpInside)
        material.layer.borderWidth = 1 / UIScreen.main.scale
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        update(appearance: .paper, language: .chinese, textScale: 1)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(appearance: WeiBeiAppearanceMode, language: WeiBeiInterfaceLanguage, textScale: CGFloat) {
        self.textScale = textScale
        if appearance.isGlass {
            let frosted = appearance == .glassMist || appearance == .glassSlate
            let style: UIBlurEffect.Style = frosted
                ? (appearance.isDark ? .systemMaterialDark : .systemMaterialLight)
                : (appearance.isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
            material.effect = UIBlurEffect(style: style)
            material.contentView.backgroundColor = WeiBeiNativePalette.glassBaseTint(for: appearance)
        } else {
            material.effect = nil
            material.contentView.backgroundColor = WeiBeiNativePalette.paperRaised(for: appearance)
        }
        let ink = WeiBeiNativePalette.ink(for: appearance)
        material.layer.borderColor = WeiBeiNativePalette.hairline(for: appearance).cgColor
        layer.shadowColor = ink.cgColor
        separator.backgroundColor = WeiBeiNativePalette.hairline(for: appearance)
        copyButton.update(title: language.text("复制", "Copy"), symbol: "doc.on.doc", ink: ink, scale: textScale)
        quoteButton.update(title: language.text("引用", "Quote"), symbol: "text.quote", ink: ink, scale: textScale)
        invalidateIntrinsicContentSize(); setNeedsLayout()
    }
    private var buttonWidth: CGFloat {
        [copyButton, quoteButton].map { button in
            let title = button.accessibilityLabel ?? ""
            let width = (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12 * textScale, weight: .medium)]).width
            return ceil(width + 31 * textScale)
        }.max() ?? 0
    }
    override var intrinsicContentSize: CGSize {
        CGSize(width: 2 * buttonWidth + 13 * textScale, height: 34 * textScale)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = buttonWidth
        copyButton.frame = CGRect(x: 4 * textScale, y: 3 * textScale, width: width, height: 28 * textScale)
        separator.frame = CGRect(x: width + 6 * textScale, y: 10 * textScale,
                                 width: 1 / UIScreen.main.scale, height: 14 * textScale)
        quoteButton.frame = CGRect(x: width + 9 * textScale, y: 3 * textScale, width: width, height: 28 * textScale)
        material.frame = bounds
        let radius = 9 * textScale
        material.layer.cornerRadius = radius
        layer.cornerRadius = radius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }
    #if WEIBEI_ACCEPTANCE_CHECKS
    var lastHitTestFailure = ""
    #endif
    func buttonsAreReachable() -> Bool {
        guard let window else { return false }
        layoutIfNeeded()
        return [copyButton, quoteButton].allSatisfy { button in
            let bounds = button.bounds.insetBy(dx: 1, dy: 1)
            guard !bounds.isEmpty else { return false }
            let points = [CGPoint(x: bounds.midX, y: bounds.midY),
                          CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                          CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
            return points.allSatisfy { point in
                let location = button.convert(point, to: window)
                let hit = window.hitTest(location, with: nil)
                let reachable = hit === button || hit?.isDescendant(of: button) == true
                #if WEIBEI_ACCEPTANCE_CHECKS
                if !reachable {
                    lastHitTestFailure = "button=\(button.accessibilityIdentifier ?? ""), bounds=\(button.bounds), point=\(location), hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil"), window=\(window.bounds), windowHidden=\(window.isHidden), windowInteractive=\(window.isUserInteractionEnabled)"
                }
                #endif
                return reachable
            }
        }
    }
}
