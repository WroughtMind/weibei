# 发布检查

## 资产

- [ ] `scripts/build-assets.sh` 成功
- [ ] `scripts/verify-assets.sh` 成功
- [ ] `asset-manifest.json` 已更新，没有未知文件
- [ ] SVG、PNG、ICNS 均为本次批准轮廓
- [ ] 透明图无白边、黑边和预乘 Alpha 光晕
- [ ] GitHub Social Preview 为 1280 × 640，文件小于 GitHub 限制

## App Icon

- [ ] 十个 iconset 槽位尺寸正确
- [ ] 16、32、64 px 的两个负形没有粘连
- [ ] 朱砂在 16 / 32 px 不像随机坏点
- [ ] 1024 图标外框透明，纸面内部不透明
- [ ] `魏碑.app/Contents/Resources/AppIcon.icns` 存在
- [ ] Info.plist 的 `CFBundleIconFile` 指向它
- [ ] Dock、Finder、Spotlight、About、通知和设置都显示新图标
- [ ] 浅色与深色桌面上都清楚
- [ ] 与 Notes、Safari、Obsidian 等并排时视觉尺寸不过满

## 核心闭环

- [ ] 打开 HTML、PDF、Markdown、纯文本
- [ ] 选区提问，范围显示正确
- [ ] 论断旁的引用能回到文件、页码或章节
- [ ] 当前出处的石青高亮和朱砂落点语义一致
- [ ] 写入笔记前有差异和确认
- [ ] 拒绝、撤销和保存状态正常
- [ ] 索引不全、扫描 PDF、离线和无证据均明确说明边界

## 布局连续性

- [ ] `reader / agent / notes` 重排后内容实例不重建
- [ ] pane 切换不丢滚动、光标、选择、撤销栈和未发送输入
- [ ] 课程目录 220–430 范围正常
- [ ] 内容轨道 28 / 240 / 420 三个关键状态正常
- [ ] 拖动分隔条命中区足够，视觉仍只有 1 px
- [ ] 两栏、三栏、对半和三种沉浸模式均截图检查

## 主题与无障碍

- [ ] 纸面与墨石主题无闪白、低对比或颜色漂移
- [ ] Web 编辑器和 SwiftUI 的纸面差异已解释或消除
- [ ] VoiceOver 完成核心闭环
- [ ] 仅键盘完成核心闭环与 pane 重排
- [ ] 200% 字号下不压坏正文
- [ ] Reduce Motion / Transparency / Increase Contrast 已测试
- [ ] 当前状态、错误和离线都不只靠颜色

## 回归

- [ ] `WeiBeiSelfCheck` 通过
- [ ] 与布局、字体、cinnabar、glass、EmptyWorkspace 相关断言已同步
- [ ] 视觉变更已更新相应 `DesignReferences/` 或基线截图
- [ ] `script/verify_release_metadata.sh` 检查图标与 plist

最后问一次：**去掉 Logo，这个界面是否仍然像一张为长期阅读和写作准备的工作台，而不是通用 AI 聊天壳？**
