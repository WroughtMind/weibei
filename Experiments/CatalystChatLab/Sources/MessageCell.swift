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
    override func prepareForReuse() { super.prepareForReuse(); unbind() }
    private func unbind() {
        body?.saveInteractionState()
        body?.removeFromSuperview()
        body = nil
        auxiliary?.removeFromSuperview(); auxiliary = nil
        title.isHidden = true; actions.isHidden = true
        for view in actions.arrangedSubviews { actions.removeArrangedSubview(view); view.removeFromSuperview() }
    }
    func show(body: BlockView) {
        if self.body !== body { unbind(); self.body = body; contentView.addSubview(body) }
        title.isHidden = true; actions.isHidden = true
        body.restoreInteractionState()
        setNeedsLayout()
    }
    func showAuxiliary(_ view: UIView) {
        if auxiliary !== view { unbind(); auxiliary = view; contentView.addSubview(view) }
        view.frame = bounds
    }
    func showHeader(_ message: LabMessage) {
        unbind()
        title.text = message.original == nil ? message.author : nil
        title.isHidden = false
    }
    func showActions(_ message: LabMessage, copy: @escaping () -> Void, quote: @escaping () -> Void,
                     source: @escaping () -> Void) {
        unbind()
        actions.isHidden = false
        for (name, symbol, action) in [("复制整条回答", "doc.on.doc", copy), ("引用到输入框", "text.quote", quote), ("查看来源材料", "book", source)] {
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
        status.text = message.state == .streaming ? "正在重放…" : (message.state == .stopped ? "已停止 · 正文保留" : "")
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
