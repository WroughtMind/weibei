# 魏碑资产来源说明

## 品牌资产

魏碑 Logo、App 图标、纸纹、宣传图和社交分享图来自项目设计系统
`WeiBei-Design-System-v0.1.1.zip`；`WeiBeiStele` 与 `WeiBeiSteleMono`
字形也来自该设计交付，并由公开字体工程重新生成带 OFL 元数据的 TTF。
原始压缩包 SHA-256 为：

```text
f89819658e5845dac0e393b3cacf80c3ecd4f7d05068194876947be080955e2f
```

设计系统保留来源记录、文件哈希和构建方式。项目源代码采用 MIT License；
`WeiBeiStele` 与 `WeiBeiSteleMono` 字体采用 SIL Open Font License 1.1。
Logo、App 图标、纸纹、宣传图和社交分享图仍是保留权利的品牌资产；
再分发与改标边界以仓库根目录的 `LICENSING.md` 和 `TRADEMARKS.md` 为准。

## 应用内容资产

- 空工作台中的古典原文、公式与《兰亭集序》书法透明图，来源和权利依据见应用资源包中的 `Inspiration/SOURCES.md`。

## 笔记排版字体

笔记默认使用 M PLUS 1p（Light / Regular），Copyright 2016 The M+ Project Authors，
采用 SIL Open Font License 1.1；完整许可随应用资源包中的 `Mplus1p-OFL.txt` 分发。
字体取自 Typora 官方主题库收录的 [Onigiri](https://theme.typora.io/theme/Onigiri/)，
用于匹配该主题的笔记排版。应用使用保留全部字形、映射、度量和微调指令的 WOFF2 压缩格式，
原始 TTF 保存在设计资产目录；开发时可用 `python3 script/convert_editor_fonts.py --check`
（fontTools 4.62.1，含 WOFF2 支持）重现并逐字形核对。中文缺字由系统无衬线字体补齐。
