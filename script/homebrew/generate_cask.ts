#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const [version, armSha256, intelSha256, trust, outputArgument] = process.argv.slice(2);
if (!version || !/^[0-9]+\.[0-9]+\.[0-9]+$/.test(version)) {
  throw new Error(
    "usage: generate_cask.ts <version> <arm-sha256> <intel-sha256> <community|notarized> <output.rb>",
  );
}
if (!armSha256 || !/^[0-9a-f]{64}$/.test(armSha256)) {
  throw new Error("ARM64 DMG SHA-256 must be 64 lowercase hexadecimal characters");
}
if (!intelSha256 || !/^[0-9a-f]{64}$/.test(intelSha256)) {
  throw new Error("Intel DMG SHA-256 must be 64 lowercase hexadecimal characters");
}
if (trust !== "community" && trust !== "notarized") {
  throw new Error("release trust must be community or notarized");
}
if (!outputArgument) {
  throw new Error("missing output path");
}

const output = path.resolve(outputArgument);
const caveats = trust === "community"
  ? `
  caveats <<~EOS
    魏碑 ${version} 尚未经过 Apple 公证。Homebrew 会使用固定 SHA-256 校验下载文件，
    但不会替代 macOS 的首次启动确认。

    首次打开如被拦截，请先尝试打开一次，再前往：
    “系统设置 → 隐私与安全性 → 安全性 → 仍要打开”。

    这只为魏碑建立单应用例外，请勿关闭整个 Gatekeeper。
  EOS
`
  : "";
const cask = `cask "weibei" do
  version "${version}"
  arch arm: "arm64", intel: "x86_64"
  sha256 arm: "${armSha256}", intel: "${intelSha256}"

  url "https://github.com/WroughtMind/weibei/releases/download/v#{version}/WeiBei-#{version}-macOS-#{arch}.dmg"
  name "魏碑"
  desc "Source-grounded reading, learning, and note workspace"
  homepage "https://github.com/WroughtMind/weibei"

  depends_on macos: :sonoma

  app "魏碑.app"
${caveats}
end
`;

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, cask, "utf8");
process.stdout.write(`homebrew_cask=${output}\n`);
