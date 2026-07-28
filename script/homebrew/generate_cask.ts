#!/usr/bin/env -S npm exec -- tsx
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const [version, sha256, outputArgument] = process.argv.slice(2);
if (!version || !/^[0-9]+\.[0-9]+\.[0-9]+$/.test(version)) {
  throw new Error(
    "usage: generate_cask.ts <version> <64-char-sha256> <output.rb>",
  );
}
if (!sha256 || !/^[0-9a-f]{64}$/.test(sha256)) {
  throw new Error("DMG SHA-256 must be 64 lowercase hexadecimal characters");
}
if (!outputArgument) {
  throw new Error("missing output path");
}

/**
 * Renders the Homebrew Cask checked into a release's evidence directory.
 *
 * @param releaseVersion - Semantic application version
 * @param releaseSHA256 - Lowercase SHA-256 for the published DMG
 * @returns Complete Ruby Cask source
 */
function renderCask(releaseVersion: string, releaseSHA256: string): string {
  return `cask "weibei" do
  version "${releaseVersion}"
  sha256 "${releaseSHA256}"

  url "https://github.com/weibei-app/weibei/releases/download/v#{version}/WeiBei-#{version}-macOS-arm64.dmg"
  name "魏碑"
  desc "Source-grounded reading, learning, and note workspace"
  homepage "https://github.com/weibei-app/weibei"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "魏碑.app"

  caveats <<~EOS
    魏碑 ${releaseVersion} 尚未经过 Apple 公证。Homebrew 会使用固定 SHA-256 校验下载文件，
    但不会替代 macOS 的首次启动确认。

    首次打开如被拦截，请先尝试打开一次，再前往：
    “系统设置 → 隐私与安全性 → 安全性 → 仍要打开”。

    这只为魏碑建立单应用例外，请勿关闭整个 Gatekeeper。
  EOS
end
`;
}

const output = path.resolve(outputArgument);
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, renderCask(version, sha256), "utf8");
process.stdout.write(`homebrew_cask=${output}\n`);
