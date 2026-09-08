import Foundation

/// Synthetic, deterministic inputs. No workspace, Keychain or model access.
public enum LabSamples {
    public static let titles = ["基础富文本", "单条长回答", "长代码和表格", "能力缺口（不计通过）"]
    public static let finalMarker = "LAB_FINAL_尾段🙂"
    public static let codeLine = "    let answer = 42 // 中文🙂"

    public static let rich = #"""
    # 原生正文候选

    这是一份合成内容，不读取魏碑的会话。中文、English、**重点文字**、*斜体*、`inline code` 和 [测试链接](https://example.invalid/lab)。

    - 第一项
    - 第二项
      - 子项

    > 引用段落应与正文保持可辨认的层级。

    行内公式 $x_i^2 + y_i^2$，以及块公式：

    $$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$

    ```swift
        let answer = 42 // 中文🙂

        print(answer)
    ```

    | 项目 | 数值 |
    | :--- | ---: |
    | Alpha | 17 |
    | Beta | 29 |

    LAB_FINAL_尾段🙂
    """#

    public static var longAnswer: String {
        (0..<72).map { index in
            "## 第 \(index + 1) 段\n\n" +
            String(repeating: "段落 \(index)：可见文字应当完整，改宽后可以继续阅读，往返不应重新解析。", count: 3 + index % 5)
        }.joined(separator: "\n\n") + "\n\n" + finalMarker
    }

    public static var codeAndTable: String {
        let code = (0..<260).map { "    let item\($0) = \($0 * 7) // 保留缩进与编号" }.joined(separator: "\n")
        let rows = (0..<60).map { "| Row \($0) | \($0 * 11) | 第 \($0) 行的中文说明 |" }.joined(separator: "\n")
        return "## 长代码\n\n```swift\n\(code)\n```\n\n## 表格\n\n| Name | Value | Note |\n| :--- | ---: | :--- |\n\(rows)\n\n\(finalMarker)"
    }

    // Deliberately not included in the basic-qualification pass predicate.
    public static let gaps = #"""
    # 以下能力仍需魏碑适配，不是已通过的项目

    图片：![说明图](https://example.invalid/lab-image.png)

    [[魏碑笔记|笔记别名]] 与 [来源](weibei-source:lab-source)。

    > [!note]- 折叠提示块
    > 原有折叠与复制行为需要单独接线。

    ```mermaid
    flowchart LR
      A[输入] --> B[输出]
    ```

    本查看器不会把链接形式的图片、源码形式的流程图当作完整能力。
    """#

    public static func source(_ index: Int) -> String {
        switch index {
        case 1: return longAnswer
        case 2: return codeAndTable
        case 3: return gaps
        default: return rich
        }
    }
}
