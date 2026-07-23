# 字体

## 现有字体资产

仓库包含：

- `Resources/Fonts/WeiBeiStele.ttf`，PostScript 名 `WeiBeiStele-Regular`
- `Resources/Fonts/WeiBeiSteleMono.ttf`，PostScript 名 `WeiBeiSteleMono-Regular`

它们由 `Support/WeiBeiResources.swift` 通过 `CTFontManagerRegisterFontsForURL` 注册。本设计包已从项目仓库同步同一份字体到 `assets/fonts/`，所有英文品牌导出必须直接使用这些文件，不允许用相似字体替代。

实际字形检查显示，两套字体覆盖基础 Latin、数字、常用标点和少量符号，不包含中文汉字。因此“使用项目字体”具体指：英文名称、英文品牌副标、顶栏 Latin 标记与技术标签；中文“魏碑”、中文正文和中文界面仍需使用支持 CJK 的系统字体，否则会缺字。

## 使用边界

| 场景 | 字体 |
|---|---|
| 英文品牌字、顶栏、栏目标记 | `WeiBeiStele-Regular`，必须使用 |
| 英文副标、技术标注、短代码式品牌标签 | `WeiBeiSteleMono-Regular`，必须使用 |
| 中文品牌标题 | 系统 serif；项目字体没有汉字字形 |
| SwiftUI 正文和控件 | SF Pro / PingFang SC 系统栈 |
| Markdown 阅读 | `Songti SC` / `STSong` / `ui-serif` |
| 导入 HTML | 尊重原文字体，默认不覆写 |
| 笔记编辑 | 系统正文栈，保证输入和中英文混排 |

“碑感”不能靠全局套字体实现。它来自标题比例、留白、粗细和稳定布局。

## 推荐层级

| 样式 | 字号 / 行高 | 用途 |
|---|---:|---|
| Display | 28 / 36 | 空状态或品牌页唯一主标题 |
| Title | 20 / 28 | 页面与模式标题 |
| Pane title | 13 / 18 | 栏标题、顶栏短标签 |
| Reader body | 16 / 27 | 统一阅读模式 |
| Notes body | 15 / 25 | 笔记编辑 |
| Conversation body | 14 / 22 | 回答与引用 |
| UI body | 13 / 18 | 菜单、按钮、说明 |
| Caption | 11 / 15 | 元数据、页码、索引状态 |

中文正文理想行宽约 38–42 字；英文约 66–74 字符。PDF 和 HTML 原有排版优先，只有用户开启统一阅读模式时才应用这套正文参数。

## 禁止

- 不要求 `WeiBeiStele` 排中文或笔记；它没有中文字形；
- 不用 SF Pro、Helvetica、Times 或相似展示字体替代英文品牌字；
- 不为了“高级”把正文做得过细、过灰、字距过大；
- 不在同一栏里混用三种以上字族；
- 不把所有标签做成全大写宽字距；英文品牌短标除外。
