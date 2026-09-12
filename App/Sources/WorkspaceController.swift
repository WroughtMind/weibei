#if WEIBEI_ACCEPTANCE_CHECKS
import UIKit

final class WorkspaceController: UIViewController {
    let conversation = ConversationController(fixtureMode: true)
    private let panel = UIView()
    private let mode = UISegmentedControl(items: ["阅读材料", "实验笔记"])
    private let editor = UITextView()
    private let excerpt = UIButton(type: .system)
    private let divider = UIView()
    private var panelWidth: CGFloat = 244
    private var dragWidth: CGFloat = 244
    private var notes = ""
    private var panelVisible = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addChild(conversation); view.addSubview(conversation.view); conversation.didMove(toParent: self)
        view.addSubview(panel); view.addSubview(divider)
        panel.backgroundColor = .secondarySystemBackground
        for child in [mode, editor, excerpt] { panel.addSubview(child) }
        mode.selectedSegmentIndex = 0
        mode.addTarget(self, action: #selector(changeMode), for: .valueChanged)
        editor.text = LabFixture.source
        editor.isEditable = false
        editor.font = .systemFont(ofSize: 16)
        editor.backgroundColor = .clear
        editor.textContainerInset = UIEdgeInsets(top: 16, left: 6, bottom: 16, right: 6)
        editor.accessibilityLabel = "阅读材料正文"
        excerpt.setTitle("将选中文字带入提问", for: .normal)
        excerpt.addTarget(self, action: #selector(quoteMaterial), for: .touchUpInside)
        divider.backgroundColor = .separator
        divider.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizePanel(_:))))
        conversation.openWorkspace = { [weak self] tab in
            guard let self else { return }
            saveDraft(); panelVisible = true; mode.selectedSegmentIndex = tab; changeMode(); view.setNeedsLayout()
        }
        conversation.toggleWorkspace = { [weak self] in
            guard let self else { return }; saveDraft(); panelVisible.toggle(); view.setNeedsLayout()
        }
        conversation.saveNote = { [weak self] text in
            guard let self else { return }
            saveDraft()
            notes += (notes.isEmpty ? "" : "\n\n") + text
            mode.selectedSegmentIndex = 1; panelVisible = true; changeMode(); view.setNeedsLayout()
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let area = view.bounds.inset(by: view.safeAreaInsets)
        let width = panelVisible ? min(panelWidth, area.width * 0.42) : 0
        panel.isHidden = !panelVisible; divider.isHidden = !panelVisible
        panel.frame = CGRect(x: area.minX, y: area.minY, width: width, height: area.height)
        divider.frame = CGRect(x: width - 2, y: area.minY, width: 4, height: area.height)
        conversation.view.frame = CGRect(x: width, y: area.minY, width: area.width - width, height: area.height)
        mode.frame = CGRect(x: 14, y: 14, width: width - 28, height: 30)
        editor.frame = CGRect(x: 8, y: 52, width: width - 16, height: area.height - 110)
        excerpt.frame = CGRect(x: 12, y: area.height - 46, width: width - 24, height: 32)
    }
    private func saveDraft() { if mode.selectedSegmentIndex == 1 { notes = editor.text } }
    @objc private func changeMode() {
        if mode.selectedSegmentIndex == 1 {
            editor.text = notes; editor.isEditable = true; editor.accessibilityLabel = "实验笔记编辑器"
        } else {
            if editor.isEditable { notes = editor.text }
            editor.text = LabFixture.source; editor.isEditable = false; editor.accessibilityLabel = "阅读材料正文"
        }
    }
    @objc private func quoteMaterial() {
        let range = editor.selectedRange
        guard range.length > 0 else { return }
        conversation.quote((editor.text as NSString).substring(with: range))
    }
    @objc private func resizePanel(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { dragWidth = panelWidth }
        panelWidth = min(420, max(180, dragWidth + gesture.translation(in: view).x))
        view.setNeedsLayout(); view.layoutIfNeeded()
    }
}

#endif
