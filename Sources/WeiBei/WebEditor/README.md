# 魏碑 Web Editor

`src/editor.js` 是笔记编辑器 JavaScript 真源。根目录运行
`npm run build:editor` 后，会生成
`Sources/WeiBei/Resources/Editor/editor.js`、`editor.css` 和 `fonts/`。

`Sources/WeiBei/Resources/Editor/index.html` 是宿主页面真源，属于手写资源；
其余三个位置属于可重建生成物，不应手工修改。

`npm run check:editor` 在临时目录重建并逐字节比较，不修改工作树。
