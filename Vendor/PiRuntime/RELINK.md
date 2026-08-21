# Pi / Bun 重新构建与替换说明

本目录随 App 提供许可证和固定版本信息；正式发布另附一次生成、可跨版本复用的
`WeiBei-Pi-relink-<指纹>.tar.gz` 源码材料包。该材料包不是魏碑 App 的许可证，
而是让接收者能够修改 WebKit / JavaScriptCore 或 TinyCC 后重新构建 Pi 运行时。

## 固定版本

- Pi：`b4f293684bba718d59cc1157679bcf6157b3a7f5`
- Bun：`0d9b296af33f2b851fcbf4df3e9ec89751734ba4`
- WebKit：`5488984d20e0dbfe4be2c3ba8fb18eb81a5e0e8b`
- TinyCC：`12882eee073cfe5c7621bcfadf679e1372d4537b`

材料包内的 `SHA256SUMS` 用于校验所有源码归档；完整 LGPL-2.0 与 LGPL-2.1
文本也在其中。魏碑发布脚本通过 `WEIBEI_PI_RELINK_BUNDLE` 接收并校验该材料包。

## 修改 WebKit / JavaScriptCore 后重建

1. 解压 Bun 与 WebKit 源码，把 WebKit 放到 Bun 源码的 `vendor/WebKit`。
2. 在 WebKit 源码中完成修改。
3. 按 Bun 1.3.14 源码中的依赖说明安装工具，然后在 Bun 源码根目录运行：

   ```sh
   bun run build:release:local
   ./build/release-local/bun --version
   ```

该命令使用本地 WebKit 源码重新构建 JavaScriptCore 和 Bun；不要使用材料包里的
预编译 WebKit 作为“修改后”的证明。

## 修改 TinyCC 后重建

1. 在带有固定提交 Git 元数据的 Bun 源码中运行 `bun run build:release`；构建脚本会
   取得固定的 TinyCC 源码、应用 `patches/tinycc/tcc.h.patch` 并写入来源标记。
2. 修改 `vendor/tinycc` 下的源码，再次运行 `bun run build:release`。上游构建脚本会
   保留来源标记匹配目录中的手工修改，只重编 TinyCC 对象并重新链接 Bun。

## 用重建的 Bun 生成 Pi

在 Pi 源码根目录安装锁定依赖并构建，再用刚生成的 Bun 执行上游同款命令：

```sh
npm ci --ignore-scripts
npm run build:offline
/path/to/bun build --compile --target=bun-darwin-arm64 \
  ./packages/coding-agent/dist/bun/cli.js \
  ./packages/coding-agent/src/utils/image-resize-worker.ts \
  --outfile ./pi
cp ./packages/coding-agent/package.json ./package.json
./pi --version
```

把生成的 `pi` 替换到候选 App 的 `Contents/Resources/PiRuntime/bin/pi` 后重新签名，
再运行魏碑现有的 Pi 版本、哈希、RPC 和 App 包验证。普通魏碑版本不重做上述构建；
只有固定版本、补丁或构建工具链变化时才重新验收材料包和重建结果。
