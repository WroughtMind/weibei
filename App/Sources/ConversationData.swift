import Foundation
import MarkdownParser
import WeiBeiCore

@MainActor
final class LabMessage {
    enum State: String { case complete, streaming, stopped }
    let id: String
    let author: String
    var markdown: String
    var revision = 0
    var displayedRevision = -1
    var state: State = .complete {
        didSet { if (oldValue == .streaming) != (state == .streaming) { revision += 1 } }
    }
    var blocks: [PreparedBlock] = []
    var original: AgentMessage?
    var parsed: MarkdownParser.ParseResult?
    var parsedRevision = -1
    var preparedTheme = -1
    var auxiliaryHeight: CGFloat = 32
    let markdownMemo = AgentMessageMarkdownMemo()
    var copyableMarkdown: String {
        let raw = original?.text ?? markdown
        guard original?.role != .user else { return raw }
        return AgentCitationMarkup.displayText(from: raw)
    }

    init(id: String = UUID().uuidString, author: String, markdown: String) {
        self.id = id; self.author = author; self.markdown = markdown
    }

    func append(_ text: String) {
        markdown += text
        revision += 1
    }
}

#if WEIBEI_ACCEPTANCE_CHECKS
enum LabFixture {
    private static let landscapeBase64 = ("""
        iVBORw0KGgoAAAANSUhEUgAAA8AAAAHgCAIAAADlh5PTAAASm0lEQVR4nO3WWbJk11XH4TMlBsAYeOCdiByBH3nDYDAYDAYn
        Npbkvm/GQFAlqVr1fakF20yEW5GiVLpVde9Zmefkf++zv4gvQs1T3sy11/pN//vZPQAAYKYp/gkAAKAjAhoAAAoENAAAFAho
        AAAoENAAAFAgoAEAoEBAAwBAgYAGAIACAQ0AAAXTHz+7BwAAzCSgAQCgQEADAEDB9MdP7wEAADMJaAAAKBDQAABQIKABAKBA
        QAMAQIGABgCAAgENAAAF0x8+vQcAAMwkoAEAoEBAAwBAgYAGAIACAQ0AAAXTHz65BwAAzCSgAQCgQEADAECBgAYAgIKLgL4L
        AADMNP3+k7sAAMBMAhoAAAoENAAAFAhoAAAoENAAAFAgoAEAoEBAAwBAgYAGAICC6fcf3wUAAGYS0AAAUDD9z8d3AQCAmQQ0
        AAAUCGgAACgQ0AAAUCCgAQCgQEADAECBgAYAgAIBDQAABQIaAAAKBDQAABRM//3RXQAAYCYBDQAABQIaAAAKBDQAABQIaAAA
        KBDQAABQIKABAKBAQAMAQMFFQN8BAABmEtAAwGL+8y/+tCr+maFq+uyjOwAApziim58U/ytgJgENABxpkW5W0nRHQAMAZSul
        s4ymC9NnH94BAJjpDOn8pYxO/73wJAENAMx15nrW0LRJQAMAs0TqWUPTIAENAFwjmM4ymgYJaADgKvFu1tC0RkADAM8UL2YN
        TYMENADwdPFW1tC0afr0wzsAAJfEK/lq8e+HkQloAOCyeB9raFomoAGAy+JxLKBpmYAGAL4kXsYamsYJaADgC/Em1tC0b/r0
        wR0AgAvxGj6yodPfG6MR0ADA5+IpLKDpgoAGAB6Kd7CGphcCGgB4KB7BAppeCGgAoO961tCc2fTJgzsAwODi+Xu6+HfIOAQ0
        ACCgoUBAA8Do4u2roemLgAaA0cXDV0DTFwENAKOLh6+Api8CGgCGFq9eDU13LgL6NgAwrHjyLh3Q+a+UzRPQADC0ePIKaLoz
        ffLBbQBgWPHkXTig098nIxDQADC0ePIKaLozffzBbQBgWPHkXVb8+2QEAhoAhhZPXgFNdwQ0AAwtnrwCmu4IaAAYWjx5BTTd
        EdAAMLR48gpouiOgAWBo8eQV0HRHQAPA0OLJK6DpjoAGgKHFk1dA0x0BDQBDiyevgKY7AhoAhhZPXgFNd6aP3r8NAAwrnrzL
        in+fjEBAA8DQ4skroOmOgAaA0cWrVz3TFwENAKOLh6+Api8CGgBGFw9fAU1fBDQAsIWGjn+HjENAAwACGgoENAAgoKFAQAMA
        D8ULWD3TCwENADwUj2ABTS+mD9+/DQDwYbcNHf/eGI2ABgA+F09hAU0XBDQA8IV4Datn2jd9+N5tAIBH4k1cqOf0d8WYBDQA
        cFm8jNUzLbsI6FsAAI+Lx/G8gM5/UYxJQAMATxHvY/VMswQ0APB08UpWz7RJQAMAzxRvZfVMgwQ0AHCVeDGrZ1ozPXjvFgDA
        FeLdfBD/HuBAQAMAs0hnOBDQAMBc6hkeCGgAoEQ9g4AGAMqkMyObHrx7CwDgCGulc/rvgqsJaADgVLqZoQhoAGAxupkRCGgA
        ACgQ0AAAUDB98O4tAABgJgENAAAFAhoAAAoENAAAFAhoAAAoENAAAFAgoAEAoEBAAwBAwfTBO7cAAICZBDQAABRM779zCwCA
        Bu3+8isniv8JmySgAQAyTu/jRcS/h+4IaACA1cUrWVgv6CKgXwYAYFnx/F2tqvPfbZyABgBYQDxtJfXZCGgAgCPF47VB8R/l
        DAQ0AEBNPFI7Ev+x1iCgAQCuFy/RbYj/josQ0AAAzxQvzm2L/77HEdAAAJfFy3JM8d99pum9t18GAOBCvCB5XHwenkVAAwBI
        5w7Eh+QRAQ0AjCsehRwnOzYCGgAYUTwBWdCZh0dAAwADiaceZ7D2FAloAGAI8aojZfFZEtAAwMbFA47WnDhRAhoA2Kx4qNGL
        0lwJaABgg+JBRu+umC4BDQBsSjy82LDDjE3vvv0yAMAGxOuKQQhoAKB78aJiKAIaAOhYvKUY0PTuWy8DAHQnXlEMS0ADAJ2J
        9xODE9AAQDfi5QQ7AQ0A9CKeTXAgoAGA1sWDCR4noAGAdsVTCZ4koAGAFsUjCZ5leuetlwEAmhIvJLiCgAYAGhJvI7jWRUC/
        BADQgngYwRwCGgDIiycRzCegAYCkeAxB1fTOmy8BAETESwiOIKABgIB4A8HRBDQAcG7xAIJTCGgA4Hzi6QOnE9AAwJnEuwcW
        Mb395ksAAKuKFw8sSEADAOuK5w4sS0ADAGuJhw6sQUADAKuIVw6sREADAAuL9w2sSkADAEuKxw2sTUADAIuJlw2cgYAGABYQ
        bxo4m+ntN14CADhFPGjgnAQ0AHC8eMrA+U1vvfESAMAR4h0DEQIaADhGPGIgRUADADXxfIEsAQ0AFMTbBeIENAAwVzxcoAUC
        GgC4XjxZoB0CGgC4RrxXoCkCGgC4SjxWoDUCGgB4unimQJsENADwFPFGgWZNb77+IgDA4+KBAi0T0ADAF+JpAu0T0ADA5+Jd
        Al0Q0ADAQ/EogV4IaABAPUOBgAaAocVbBLojoAFgXPEQgR4JaAAYVLxCoFMCGgCGE+8P6JqABoCxxOMDeje98fqLAMAg4uUB
        GzAd/hF/zwDA2uLZAdswPfq3+KsGAFYSDw7Ykunx/3jjtRcBgI2J1wZszPTk/4q/cwBgKfHUgO15SkDvNDQA9C8eGbBVTw/o
        nYYGgJ7FCwM27JkBvdPQANCneF7Atl0V0AfxLQAAzBdvC9i86wN6p6EBoAfxqoBBzAroC6+/9iIA0Kx4UsA45gb0QXw7AABP
        ivcEDKUW0DsNDQCNiccEjKYc0DsNDQBtiGcEjOmYgN5paABIizcEDOvIgD54/dUXAYDziwcEjOykgN5paAA4r3g6AKcG9E5D
        A8C5xLsB2C0S0AfxnQIA2xaPBuBgsYDePWzomwDAGuLFADyyZEBfeO3VmwDAguKtAFyycEAfxHcNAGxDPBSAJ60S0DsNDQAn
        i1cC8FRrBfROQwPAseJ9AFxhxYA+iO8gAOhLPA6Aq60e0DsNDQCzxcsAuNY5AnqnoQHgOvEmAGY6U0AfxHcTALQpHgTAfGcN
        6AuvvXITAHhcvAaAknMH9E5DA8D/i3cAcIRAQB+8+spNABhZPAKA48QCeqehARhYvACAoyUD+iC+wgDgnOKXFzhRPqB3GhqA
        YcRvLnC6JgJ6p6EBGED82gKLaCWgD+KrDQDWEL+wwILaCuidhgZgc+K3FVhWcwF9EF92AHC6+D0F1tBoQO80NACdi19SYCXt
        BvRBfP0BwBHiBxRYT+sBfeGV+zcBoBfxuwmsrYOAPogvRAC4VvxcAmfQTUDvNDQADYtfSeBsegrog/iKBIBL4scROKf+Avog
        visB4BXpDEPqNaB3GhqAtPgpBCI6DuiD+PYEYEDx8wcEdR/QOw0NwHnFDx+QtYWAPnjl/g0AWFX82AEt2E5AH8R3KwBbFb9x
        QCO2FtAX7t+/AaPxTGBV8dMGNGWDAX0Q37Zwovgj8prgIP4GgdZsNqAP4msXrhZ/I54YXCH+xIA2bTygD+7fuwFx8YfgucF8
        8acEtGyIgD6Ir2OGEh/4dsR/C6iKvxqgcQMF9M4hZzXx2e5L/PeCZ4m/DqALYwX0QXxBswHxMd6S+K8J9z1qoGLEgD6IL2v6
        Ep/YQcR/aMYUn3ygL+MG9EF8a9Os+HCy80JZX3zIgR6NHtAH8Q1OI+KjyBXi48HGxEca6JeA/pJ7924wmvjUcYT42NC1+AAD
        vRPQTxFf7qwqPmAsKz5RvfiTP/+z3nn+QCME9DPFrx0Lio8T5xGftIh41zbIEgBWJaCvET+NHC0+PATFx29B8Rjdnvh8Ar0T
        0HPFjyhzxOeEBsXHco54U3IQH1egCwK65t7dG7QmPhV0JD6uF+KNyBHiows0RUAfKX6DBxcfAHp3himNNx9ri48xkCKgTxVP
        yUHEf2g2bJERjcccjYjPM3AGAnoZ8b7cpPjPyoC0MouLTzWwOAG9vHh3di3+88GBYmY98fEGTiSgV3T37g2uFf+Z4JJ4XTGg
        +NgDJQL6HOKR2pT4zwGXxOMJLok/CuBqAvrc4v2qmBlcvI2gKv5qgEsEdFi8bhUzmxevH1hW/E0BArot8fbVymxDPHHgbOLP
        DQYkoFsXT2StTBfiEQONiD9GGIGA7tvdu/+1lPjfAiXxTIH2xd8pbJWABroRzxHoWvwJw2YIaKBd8eCArYq/buiagAbaEg8L
        GE381UN3BDSQFw8I4JH4QoD2CWggI14JwLXiiwLaJKCB84nXAHC0+AKBdghoYF3xqw8sLr5YIEtAA8uLX3fgbOILB85PQAPL
        iF9xIC6+iOA8BDRwvPi1BpoVX1CwHgEN1MSvMtCd+OKCZQlo4Hrx6wtsQ3ybwSIENPB08UMLbFt8y8HRBDTwJfGbCgwovvqg
        READX4nfToBH4isRriWgYVDxGwlwtfiehGcR0DCW+EUEOEJ8ecLjBDRsX/zyASwovlRBQMM2xS8cwNrim5ZhCWjYlPg9A4iI
        r1+GIqChe/G7BdCU+Fpm8wQ0dCl+nwDaF9/VbJWAhp7ErxFAp+ILnC0R0NC6+NUB2Jj4Yqd3AhpaFL8uACOIb3s6JaChIfFb
        AjCs+AmgIwIawuI3A4DHxe8C7RPQkBG/EABcK34saJOAhvOJXwIAjhY/IrRDQMO64hsfgGXFLwtxAhpWEd/vAJxB/NwQIaBh
        MfE9DkBQ/AxxNgIaThLf1wC0Jn6bWJuAhrL4agagF/GbxRoENMwV38IAdC1+yFiKgIarxLctAJsUP3CcQkDDZfGtCsBQ4oeP
        KgEND8W3JwDEryEzCWjGFV+UAPAs8SvJFQQ0Y4kvRACoil9PLhHQbF988QHAUuJXlZ2AZqviCw4A1ha/tsMS0GxHfJEBQEr8
        Cg9FQNO3+MICgNbEr/PmCWj6E19MANCR+OHeHgFNH+LbBwA2IH7Qt0FA06j4igGAbYvf+n4JaBoSXyUAMKx4BnREQJMUXxYA
        wJPihdA4Ac1ZxTcCAFAV74fWCGhWF3/2AMCC4mkRJ6BZXvxhAwBnEw+P8xPQnCr+bgGAdsTL5AwENGXxlwkAdCSeLosT0Fwj
        /uoAgC2Jt83pBDSXxd8VADCUePxUCeihxR8MAMCT4o10tamXD8rp4o8BAOBo8ZR6ZOrlg1ISH3EAgDOIhNY1Ad3UZ+VJ8akF
        AGjQqgF2ZECnPu6Y4iMIALAZp7fZ8gG99ifenvgYAQBw0GJAL/vpGxf/DgEAWFy7AQ0AAA0S0AAAUCCgAQCgQEADAECBgAYA
        gAIBDQAABQIaAAAKBDQAABQIaAAAKBDQAABQIKABAKBAQAMAQIGABgCAAgENAAAFAhoAAAoENAAAFAhoAAAoENAAAFAgoAEA
        oEBAAwBAgYAGAIACAQ0AAAUCGgAACgQ0AAAUCGgAACgQ0AAAUCCgAQCgQEADAECBgAYAgAIBDQAABQIaAAAKBDQAABQIaAAA
        KBDQAABQIKABAKBAQAMAQMH0V8/tAQCAmQQ0AAAUCGgAACiYvvrcHgAAmGn66vN7AABgJgENAAAF018/vwcAAGYS0AAAUCCg
        AQCgYPqbF/YAAMBMAhoAAAoENAAAFAhoAAAomL72wh4AAJhp+tr39wAAwEwCGgAACqa//f4eAACYSUADAECBgAYAgILp736w
        BwAAZhLQAABQIKABAKBAQAMAQMH09R/sAQCAmaav/3APAADMJKABAKBg+vsf7gEAgJkENAAAFAhoAAAomP7hR3sAAGAmAQ0A
        AAUCGgAACgQ0AAAUTN/40R4AAJhp+saP9wAAwEwCGgAACqZ//PEeAACYSUADAECBgAYAgILpn36yBwAAZhLQAABQIKABAKBA
        QAMAQMH0zZ/sAQCAmaZv/nQPAADMJKABAKBg+uef7gEAgJkENAAAFAhoAAAomP7lZ3sAAGAmAQ0AAAUCGgAACgQ0AAAUTN/6
        2R4AAJhp+tbP9wAAwEwCGgAACqZ//fkeAACYSUADAECBgAYAgILp336xBwAAZhLQAABQIKABAKBAQAMAQMH07V/sAQCAmaZv
        /3IPAADMJKABAKBg2v9yDwAAzCSgAQCgQEADAEDB9O+/2gMAADMJaAAAKBDQAABQIKABAKBg+s6v9gAAwEzTd369BwAAZhLQ
        AABQMH3313sAAGAmAQ0AAAUCGgAACqb/+M0eAACYSUADAECBgAYAgAIBDQAABdP3frMHAABmmr732z0AADCTgAYAgILpud/u
        AQCAmQQ0AAAUCGgAACiYnv/dHgAAmElAAwBAgYAGAIACAQ0AAAXTC7/bAwAAM/0frUhkDFqS6SoAAAAASUVORK5CYII=
        """).replacingOccurrences(of: "\n", with: "")
    static let landscapeSource = "data:image/png;base64," + landscapeBase64
    static var landscapePNG: Data? { Data(base64Encoded: landscapeBase64) }

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

    这是一条完整回答。可以从**这个加粗段落**拖选到后面的段落，按 ⌘C 复制，或松手后用选区旁的复制、引用胶囊把选区带到输入框。来源见 [阅读材料](weibei-lab://source)，笔记见 [[学习笔记]]。

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
            "保留同一处文字，而不是仅记住旧的绝对坐标。窗口变窄以后，这一行应能横向滚动查看完整内容。同一行还保留来源编号、条件、执行结果与补充说明；这段内容必须通过横向滚动读完，不应被裁掉、折叠或缩小字号。"
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

    ![自建图片样本：山、水与阅读](\#(landscapeSource))

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
        }.joined(separator: "\n\n") + "\n\n```swift\n" + longCode + "\n```\n\n【长回答结束：全部 140 节】"
    }

    static let longCode = "let readings: [Int] = [\n" + (0..<240).map {
        "    \($0 * 17 + 23), // 第 \($0 + 1) 个观测：保留完整的长代码和原始换行，横向滚动应能读到这一行末尾的内容。这里继续保留来源编号、样本条件、读取结果与补充说明，保证实际内容超过正文宽度。"
    }.joined(separator: "\n") + "\n]\nprint(readings.count)"

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

#endif
