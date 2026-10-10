import UIKit

final class MessageCell: UICollectionViewCell {
    private(set) var body: BlockView?
    private var auxiliary: UIView?
    private let title = UILabel()
    private let actions = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .secondaryLabel
        actions.axis = .horizontal
        actions.spacing = 20
        actions.alignment = .center
        contentView.addSubview(title)
        contentView.addSubview(actions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func prepareForReuse() { super.prepareForReuse(); contentView.layer.removeAllAnimations(); contentView.alpha = 1; contentView.transform = .identity; unbind() }
    private func unbind() {
        // A prepared view may already belong to the replacement cell by the
        // time UIKit recycles this one. Only detach views this cell still owns.
        if body?.superview === contentView {
            body?.saveInteractionState()
            body?.removeFromSuperview()
        }
        body = nil
        if auxiliary?.superview === contentView { auxiliary?.removeFromSuperview() }
        auxiliary = nil
        title.isHidden = true; actions.isHidden = true
        for view in actions.arrangedSubviews { actions.removeArrangedSubview(view); view.removeFromSuperview() }
    }
    func show(body: BlockView) {
        if self.body !== body { unbind(); self.body = body }
        if body.superview !== contentView { contentView.addSubview(body) }
        title.isHidden = true; actions.isHidden = true
        body.restoreInteractionState()
        setNeedsLayout()
    }
    func showAuxiliary(_ view: UIView) {
        if auxiliary !== view { unbind(); auxiliary = view }
        if view.superview !== contentView { contentView.addSubview(view) }
        view.frame = bounds
    }
    func showHeader(_ message: LabMessage, showsWorkspaceAuthor: Bool = false, fontSize: CGFloat = 13) {
        unbind()
        title.text = message.original == nil || showsWorkspaceAuthor ? message.author : nil
        title.font = .systemFont(ofSize: fontSize, weight: .medium)
        title.isHidden = false
    }
    func showActions(_ message: LabMessage, copy: @escaping () -> Void, quote: @escaping () -> Void,
                     source: @escaping () -> Void) {
        unbind()
        actions.isHidden = false
        for (name, symbol, action) in [
            (CatalystInterfaceCopy.text("复制整条回答", "Copy the whole answer"), "doc.on.doc", copy),
            (CatalystInterfaceCopy.text("引用到输入框", "Quote into the input"), "text.quote", quote),
            (CatalystInterfaceCopy.text("查看来源文稿", "View source document"), "book", source)
        ] {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.tintColor = .secondaryLabel
            button.accessibilityLabel = name
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            actions.addArrangedSubview(button)
        }
        let status = UILabel()
        status.font = .systemFont(ofSize: 12)
        status.textColor = .tertiaryLabel
        status.text = message.state == .streaming
            ? CatalystInterfaceCopy.text("正在重放…", "Replaying…")
            : (message.state == .stopped ? CatalystInterfaceCopy.text("已停止 · 正文保留", "Stopped · text kept") : "")
        actions.addArrangedSubview(status)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        body?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: body?.record?.height ?? 0)
        auxiliary?.frame = bounds
        title.frame = bounds
        actions.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 34)
    }
}
