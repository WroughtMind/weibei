# SwiftUI 映射

## 不建立第二套 Theme

仓库已经有 `WeiBeiAppearanceMode`、`WeiBeiTypography`、`WeiBeiTheme`、`WeiBeiNativePalette`、`WeiBeiMetric`、`WeiBeiMotion` 和 `WeiBeiTransition`。`tokens.json` 是文档与跨端交换格式，SwiftUI 运行时仍应以 `Sources/WeiBei/Support/Theme.swift` 为唯一入口。

`DesignTokens.swift` 是候选映射，用于对照或合并，不能和现有 Theme 长期并存，否则数值会再次分叉。

## 颜色

短期保持 `Theme.swift` 的动态颜色实现。中期可把 light / dark / high-contrast 颜色迁入 Asset Catalog，但 AppKit 桥接和 Web 编辑器必须读取同一来源。

`Editor/index.html` 的近似色暂时记录为渲染例外；后续由构建脚本从 token 生成 CSS custom properties：

```css
:root {
  --wb-paper: #F4EAD5;
  --wb-paper-raised: #F9F1DE;
  --wb-link: #305469;
}
```

## 字体

继续由 `WeiBeiResources.swift` 集中注册。英文品牌字使用 `WeiBeiStele-Regular`，英文品牌副标与技术标签使用 `WeiBeiSteleMono-Regular`。组件只请求这两个 PostScript 名，不在各 View 重复注册，也不用近似展示字体静默替代。

两套字体没有中文汉字字形。中文标题、正文和控件继续使用系统 CJK 字体；这不是风格回退，而是字体覆盖范围决定的正确分工。品牌字体加载失败时写入日志并使用系统字体，不能影响正文编辑。

## 布局

pane 宽度和分隔行为继续归 `ContentView.swift` / `NSSplitView` 桥接管理。SwiftUI View 不应在内部再硬编码竞争性的最小宽度。

## 动效

所有组件调用 `WeiBeiMotion` 与 `WeiBeiTransition`。新增动画必须检查 `accessibilityReduceMotion`，并在 `WeiBeiSelfCheck` 增加对应断言。

## 共享组件

按钮、输入、浮层、批注和标题先扩展现有 `WeiBeiIconButtonStyle`、`WeiBeiTextActionButtonStyle`、`weibeiInputSurface`、`weibeiFloatingPanel`、`weibeiAnnotationPanel` 与 `WeiBeiGlassHeaderBackground`，不要按页面复制 modifier。
