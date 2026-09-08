import Foundation

@MainActor
final class LabMessage {
    enum State: String { case complete, streaming, stopped }
    let id: String
    let author: String
    var markdown: String
    var revision = 0
    var displayedRevision = -1
    var state: State = .complete
    var blocks: [PreparedBlock] = []

    init(id: String = UUID().uuidString, author: String, markdown: String) {
        self.id = id; self.author = author; self.markdown = markdown
    }

    func append(_ text: String) {
        markdown += text
        revision += 1
    }
}

enum LabFixture {
    static let source = """
    阅读材料 · 如何在长文中保持上下文

    阅读是一种持续的定位活动。人们既记得刚刚读到的文字，也记得它在页面上的位置。内容增长时，保持阅读位置比不断追随最新一句话更重要。

    当新的内容出现在上方时，当前句子应继续留在原处。当窗口宽度改变时，同一句话可以重新换行，但不应突然被带到另一段。

    选择、摘录与笔记构成另一个连续过程：先选中有价值的内容，将它带入提问，再把新的理解收录到笔记。会话界面需要支持这个完整过程。

    这份材料是本实验自建的公开合成样本，不来自用户资料库。
    """

    static func history(_ index: Int) -> String {
        let topics = ["阅读位置", "上下文联系", "材料与解释", "问题的边界", "长期回看", "记录与复述", "图表的含义"]
        return """
        ### 第 \(index + 1) 次讨论 · \(topics[index % topics.count])

        我们在编号 \(index + 1) 的材料中看到，**理解需要保留线索**。把一段文字放回它所属的问题，才能知道它回答了什么。这里用不同编号和内容变化的合成段落，观察长历史首次进入与回看时的处理成本。

        - 先记录这次讨论的判断：\(index * 17 + 23)。
        - 再核对来源、上下文以及尚未解释的条件。
        """
    }

    static let rich = #"""
    ## 从一段文字到一份理解

    这是一条完整回答。可以从**这个加粗段落**拖选到后面的段落，按 ⌘C 复制，或用右键把选区带到输入框。来源见 [阅读材料](weibei-lab://source)，笔记见 [[学习笔记]]。

    第二段保留中文、English、数字 2026，以及组合字符 café 和 👩🏽‍💻。选择跨越段落时，复制结果仍按同一条回答组织。

    > [!NOTE]
    > 内容增长时，正在读的句子应留在原处；停止输出也不会重建已经显示的正文。

    ### 公式与推导

    行内公式 $E=mc^2$，以及积分：

    $$\int_0^1 x^2\,dx = \frac{1}{3}$$

    ### 代码与横向阅读

    ```swift
    struct ReadingPosition {
        let messageID: String
        let paragraph: Int
        let character: Int

        func describe() -> String {
            "保留同一处文字，而不是仅记住旧的绝对坐标。窗口变窄以后，这一行应能横向滚动查看完整内容。"
        }
    }
    ```

    ### 表格

    | 场景 | 开始状态 | 内容变化 | 阅读者应该看到什么 | 记录 |
    | --- | --- | --- | --- | --- |
    | 读历史 | 停留在中间 | 后方输出 | 原句保持位置 | 独立核验 |
    | 载入更早记录 | 当前段落可见 | 上方前插 | 不跳走 | 独立核验 |
    | 改宽 | 选择一处文字 | 段落重新换行 | 同一句继续可见 | 独立核验 |
    | 图片到达 | 图片准备中 | 得到真实比例 | 保住当前正文 | 独立核验 |

    ### 图片

    ![自建图片样本：山、水与阅读](lab-image://landscape)

    图片下方的文字用于检查资源到达后的行高与阅读位置。

    ### 摘记卡

    ```genui
    {"title":"把理解写下来","prompt":"这段材料改变了我的哪个判断？"}
    ```

    ### 关系图

    ```mermaid
    graph LR
      A[阅读材料] --> B[选择摘录]
      B --> C[提出问题]
      C --> D[整理笔记]
      D --> A
    ```

    **回答结束。** 这一句用于核验停止与完成后尾部内容完整。
    """#

    static var longAnswer: String {
        (0..<140).map { index in
            history(index) + (index % 28 == 0 ? "\n\n" + rich : "")
        }.joined(separator: "\n\n") + "\n\n【长回答结束：全部 140 节】"
    }

    static let replay = """
    ## 固定重放：阅读与理解

    你刚刚输入的文字已留在会话里。这里播放同一份固定回答，用来排除模型网络变化对渲染比较的干扰。**当前没有接通真实模型。**

    阅读过程中，新的内容只改变当前这条回答。你可以向上读历史，或继续选择这句话；界面不应把你拉回最新位置。

    ### 用一个具体例子说明

    先读材料，再保留疑问，最后把理解写成自己的话。一个已经显示的段落，在后面的段落增长时不需要重新设置正文。

    ```swift
    let text = "中文输入与持续阅读"
    print(text)
    ```

    | 步骤 | 实际行为 |
    | --- | --- |
    | 阅读 | 回到同一句文字 |
    | 摘录 | 将选区送入提问 |
    | 笔记 | 在实验笔记中保留草稿 |

    行内公式 $a^2+b^2=c^2$。

    引用可以在后文给出：[完整材料][material]。

    [material]: weibei-lab://source

    完成：最后的中文、标点与 👩🏽‍💻 都已完整保留。
    """
}
