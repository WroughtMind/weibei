# WKWebView 本地 ESM 动态加载预研

日期：2026-08-19
结论：**不要在当前 `loadFileURL` 架构下采用 ESM dynamic import。** 本机最小验证在允许读取模块目录及其父目录两种权限下都被 WebKit 同源策略拒绝。工作包 H 应选“多个本地静态 bundle，按需注入”的备用路径；继续禁止运行时 CDN。

## 与正式 App 对齐的条件

- macOS 原生 `WKWebView`；
- 主页面通过 `loadFileURL(_:allowingReadAccessTo:)` 加载；
- HTML 中执行 `import('./feature.js')`；
- `feature.js` 与 HTML 同目录；
- 安装与正式 App 相同口径的内容规则，拦截 `http/https/ws/wss`；
- 全程无网络、无 CDN。

最小页面只动态导入一个导出字符串 `local-esm-ok` 的本地模块，并通过 script message 回传结果。分别验证：

1. `allowingReadAccessTo` 指向 HTML/模块所在目录；
2. `allowingReadAccessTo` 扩大到该目录的父目录，与正式编辑器当前授权粒度一致。

两次结果相同：

```text
TypeError: Cross-origin script load denied by Cross-Origin Resource Sharing policy.
```

这证明问题不是文件读取范围不足；在当前 `file://` 主页面下，WebKit 把 ESM 模块加载挡在同源策略上。签名候选包尚未测，因为未签名本地条件已经确定失败，继续做签名验证没有决策价值。

## 可用路径

现有编辑器已经用普通本地脚本成功工作：`Resources/Editor/index.html:1346` 通过 `<script src="./editor.js">` 加载产物，`WeiBeiWebEditorCheck` 也用 `loadFileURL` 覆盖这条路径。因此工作包 H 采用：

- 编辑器核心保持一个本地静态 bundle；
- Mermaid、Prism grammar 等重模块各自产出本地 IIFE/普通脚本 bundle；
- 第一次需要时由 Host 或页面插入本地 `<script src>`，加载完成缓存 Promise，后续复用；
- 资源清单与完整性检查覆盖全部 bundle；
- 网络 guard 保持不变，不增加本地 HTTP 服务和自定义协议层。

只有未来编辑器主页面不再使用 `loadFileURL`，或 WebKit 明确改变本地模块同源行为时，才重新评估 ESM chunks。
