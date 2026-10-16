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
            accessibilityIdentifier = "conversation-selection-panel-obstacle"
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

final class ConversationSelectionActions: UIView {
    let copyButton = UIButton(type: .system)
    let quoteButton = UIButton(type: .system)
    private let material = UIVisualEffectView()
    private let stack = UIStackView()
    private let separator = UIView()
    private var buttonSizeConstraints: [NSLayoutConstraint] = []
    private var appearance: WeiBeiAppearanceMode = .paper
    private var language: WeiBeiInterfaceLanguage = .chinese
    private var textScale: CGFloat = 1
    private var copied = false
    private var hovered: Set<ObjectIdentifier> = []
    var copySelectedText: (() -> Void)?
    var quoteSelectedText: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isOpaque = false
        accessibilityIdentifier = "conversation-selection-actions"
        material.isUserInteractionEnabled = false
        material.accessibilityElementsHidden = true
        material.clipsToBounds = true
        addSubview(material)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4)
        addSubview(stack)
        for button in [copyButton, quoteButton] {
            button.configuration = .plain()
            button.configurationUpdateHandler = { [weak self] button in self?.style(button) }
            button.isPointerInteractionEnabled = true
            button.addInteraction(UIToolTipInteraction())
            button.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
            buttonSizeConstraints += [button.widthAnchor.constraint(equalToConstant: 28),
                                      button.heightAnchor.constraint(equalToConstant: 28)]
        }
        NSLayoutConstraint.activate(buttonSizeConstraints)
        copyButton.accessibilityIdentifier = "conversation-selection-copy"
        quoteButton.accessibilityIdentifier = "conversation-selection-quote"
        copyButton.addAction(UIAction { [weak self] _ in self?.copySelectedText?() }, for: .touchUpInside)
        quoteButton.addAction(UIAction { [weak self] _ in self?.quoteSelectedText?() }, for: .touchUpInside)
        stack.addArrangedSubview(copyButton)
        stack.addArrangedSubview(separator)
        stack.addArrangedSubview(quoteButton)
        separator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 14).isActive = true
        material.layer.borderWidth = 1 / UIScreen.main.scale
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        update(appearance: .paper, language: .chinese, textScale: 1)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(appearance: WeiBeiAppearanceMode, language: WeiBeiInterfaceLanguage, textScale: CGFloat) {
        self.appearance = appearance
        self.language = language
        self.textScale = textScale
        // Match the app's floating panels: a tint alone is transparent paint,
        // while glass needs a native backdrop underneath it.
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
        material.layer.borderColor = WeiBeiNativePalette.hairline(for: appearance).cgColor
        layer.shadowColor = WeiBeiNativePalette.ink(for: appearance).cgColor
        separator.backgroundColor = WeiBeiNativePalette.hairline(for: appearance)
        for constraint in buttonSizeConstraints { constraint.constant = 28 * textScale }
        for button in [copyButton, quoteButton] { style(button) }
        invalidateIntrinsicContentSize()
    }
    func setCopied(_ value: Bool) {
        copied = value
        style(copyButton)
        invalidateIntrinsicContentSize()
    }
    private func style(_ button: UIButton) {
        let isCopy = button === copyButton
        let title = isCopy
            ? language.text(copied ? "已复制" : "复制", copied ? "Copied" : "Copy")
            : language.text("引用", "Quote")
        var configuration = button.configuration ?? .plain()
        configuration.title = nil
        configuration.attributedTitle = nil
        configuration.image = UIImage(systemName: isCopy ? (copied ? "checkmark" : "doc.on.doc") : "text.quote",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 13 * textScale))?
            .withRenderingMode(.alwaysTemplate)
        configuration.imagePadding = 0
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        let ink = WeiBeiNativePalette.ink(for: appearance)
        button.tintColor = ink
        configuration.baseForegroundColor = ink
        configuration.imageColorTransformer = UIConfigurationColorTransformer { _ in ink }
        configuration.background.backgroundColor = button.isHighlighted ? ink.withAlphaComponent(0.16)
            : hovered.contains(ObjectIdentifier(button)) ? WeiBeiNativePalette.paperInset(for: appearance) : .clear
        configuration.background.cornerRadius = 10
        button.configuration = configuration
        button.accessibilityLabel = title
        button.interactions.compactMap { $0 as? UIToolTipInteraction }.first?.defaultToolTip = title
    }
    override var intrinsicContentSize: CGSize {
        let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the event surface around the native button frames. Insets belong
        // to the stack's content layout, not to its own hit-test bounds.
        stack.frame = bounds
        material.frame = bounds
        material.layer.cornerRadius = bounds.height / 2
        layer.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
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
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        guard let button = gesture.view as? UIButton else { return }
        if gesture.state == .began || gesture.state == .changed { hovered.insert(ObjectIdentifier(button)) }
        else { hovered.remove(ObjectIdentifier(button)) }
        button.setNeedsUpdateConfiguration()
    }
}
