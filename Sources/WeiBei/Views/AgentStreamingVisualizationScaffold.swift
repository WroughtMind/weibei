import SwiftUI

/// 无内容骨架占位:流式期间 viz 块(表格/图表等)只宣示"这里将有内容",
/// 不抢排版。定稿翻转时由真实的逐块布局一次性替换。
///
/// 背景:带 viz 块的回答曾经在中途 blocks 落库的一刻从"单一整篇表面"
/// 切换成"逐块多表面",每个文本块新挂载一个 WebView 从头渲染,整篇重排
/// ——即流式过程中肉眼可见的"刷新一下"。骨架把结构切换推迟到定稿时刻,
/// 与高度收敛一起发生,流式全程保持同一排版结构。
struct AgentStreamingVisualizationScaffold: View {
    var count: Int

    var body: some View {
        ForEach(0..<max(count, 0), id: \.self) { _ in
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WeiBeiTheme.paperInset.opacity(0.42))
                .frame(height: 96)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(WeiBeiTheme.hairline.opacity(0.38), lineWidth: 1)
                }
                .accessibilityLabel("正在生成的图表位置")
        }
    }
}
