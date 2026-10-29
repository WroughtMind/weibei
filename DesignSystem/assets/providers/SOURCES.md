# 新增服务商标志

2026-10-30 核对。仅用于连接设置中的服务商识别；品牌标志归各权利人所有，不属于魏碑自有品牌。

| 服务商 | 官方来源 | 导入方式 |
|---|---|---|
| Ant Ling | [官网](https://www.ant-ling.com) 引用的 [favicon.ico](https://gw.alipayobjects.com/render/p/yuyan/180020010001289651/favicon.ico) | 取原始 256×256 透明图像，保留颜色与轮廓 |
| Cerebras | [官网](https://www.cerebras.ai) 页头内嵌 SVG | 仅取图形标志的前两条路径；橙色弧线和继承文字颜色的中心图形分层，去掉右侧文字，居中到 48×48 画布 |
| Radius | [官方页面](https://radius.earendil.com)，由 [Pi 官网](https://pi.dev) 的 Radius 链接指向 | 取 `radius-logo-mark` 的完整路径和 560×560 画布；单色图形跟随界面墨色 |
| Fireworks | [官网](https://fireworks.ai) 引用的 [icon.svg](https://fireworks.ai/icon.svg?26fd47f5c5eddcac) | 保留完整标志路径和原 85×85 坐标；去掉 favicon 的底板与外层缩放，单色图形跟随界面墨色 |
| Together AI | [官网](https://www.together.ai) 页头 `nav-logo` SVG | 取前三条彩色图形路径，去掉右侧文字，保留官方三色 |

SVG 中的曲线、直线与填充规则保持原样。源文件哈希见 `SHA256.json`。导出资源位于 `Sources/WeiBei/Resources/ProviderMarks.xcassets`：Ant Ling 保持源文件的 256 像素，其余从矢量导出为 512 像素透明 PNG；设置卡片使用 52 点或 34 点尺寸。

`export.swift` 读取同目录源文件，接收一个导出目录作为参数，在其中输出 `ProviderMarks.xcassets/`。该脚本只转换文件格式，不打开应用窗口。Cerebras 中心、Radius 和 Fireworks 使用模板图像，由应用提供墨色；其余图层保留原色。
