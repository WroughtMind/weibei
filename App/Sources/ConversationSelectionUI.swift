import UIKit
import WeiBeiCore

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
    private let stack = UIStackView()
    private let separator = UIView()
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
        accessibilityIdentifier = "conversation-selection-actions"
        stack.axis = .horizontal
        stack.alignment = .center
        addSubview(stack)
        for button in [copyButton, quoteButton] {
            button.configuration = .plain()
            button.configurationUpdateHandler = { [weak self] button in self?.style(button) }
            button.isPointerInteractionEnabled = true
            button.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
        }
        copyButton.accessibilityIdentifier = "conversation-selection-copy"
        quoteButton.accessibilityIdentifier = "conversation-selection-quote"
        copyButton.addAction(UIAction { [weak self] _ in self?.copySelectedText?() }, for: .touchUpInside)
        quoteButton.addAction(UIAction { [weak self] _ in self?.quoteSelectedText?() }, for: .touchUpInside)
        stack.addArrangedSubview(copyButton)
        stack.addArrangedSubview(separator)
        stack.addArrangedSubview(quoteButton)
        separator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 14).isActive = true
        layer.borderWidth = 1 / UIScreen.main.scale
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
        backgroundColor = WeiBeiNativePalette.paperRaised(for: appearance)
        layer.borderColor = WeiBeiNativePalette.hairline(for: appearance).cgColor
        layer.shadowColor = WeiBeiNativePalette.ink(for: appearance).cgColor
        separator.backgroundColor = WeiBeiNativePalette.hairline(for: appearance)
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
        configuration.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 12 * textScale, weight: .medium)
        ]))
        configuration.image = UIImage(systemName: isCopy ? (copied ? "checkmark" : "doc.on.doc") : "text.quote",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 11 * textScale))
        configuration.imagePadding = 5
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        configuration.baseForegroundColor = WeiBeiNativePalette.ink(for: appearance)
        configuration.background.backgroundColor = button.isHighlighted || hovered.contains(ObjectIdentifier(button))
            ? WeiBeiNativePalette.paperInset(for: appearance) : .clear
        configuration.background.cornerRadius = 10
        button.configuration = configuration
        button.accessibilityLabel = title
    }
    override var intrinsicContentSize: CGSize {
        let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: size.width + 8, height: size.height + 6)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        stack.frame = bounds.insetBy(dx: 4, dy: 3)
        layer.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
    }
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        guard let button = gesture.view as? UIButton else { return }
        if gesture.state == .began || gesture.state == .changed { hovered.insert(ObjectIdentifier(button)) }
        else { hovered.remove(ObjectIdentifier(button)) }
        button.setNeedsUpdateConfiguration()
    }
}
