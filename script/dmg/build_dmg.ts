#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

// appdmg 的类型声明见同目录 appdmg.d.ts（无官方类型包）。

async function main() {
  let appdmg: (options: any) => any;
  try {
    appdmg = (await import("appdmg")).default;
  } catch {
    console.error("build failed: appdmg is unavailable; run npm ci first");
    process.exit(1);
    throw new Error("appdmg unavailable"); // 不可达；仅为满足 TS 的赋值分析
  }

  const [rootArgument, appArgument, targetArgument, version] = process.argv.slice(2);
  if (!rootArgument || !appArgument || !targetArgument || !version) {
    throw new Error("usage: build_dmg.ts <repo-root> <魏碑.app> <output.dmg> <version>");
  }

  const root = path.resolve(rootArgument);
  const appPath = path.resolve(appArgument);
  const target = path.resolve(targetArgument);
  const designSystem = path.join(root, "DesignSystem");
  const background = path.join(designSystem, "assets/dmg/dmg-background.png");
  const icon = path.join(designSystem, "assets/app-icon/AppIcon.icns");

  for (const requiredPath of [appPath, background, `${background.slice(0, -4)}@2x.png`, icon]) {
    if (!fs.existsSync(requiredPath)) {
      throw new Error(`missing DMG input: ${requiredPath}`);
    }
  }

  fs.rmSync(target, { force: true });
  fs.mkdirSync(path.dirname(target), { recursive: true });

  const emitter = appdmg({
    target,
    basepath: root,
    specification: {
      title: `魏碑 ${version}`,
      icon,
      background,
      "icon-size": 112,
      format: "UDZO",
      filesystem: "HFS+",
      window: {
        position: { x: 220, y: 180 },
        size: { width: 720, height: 460 },
      },
      contents: [
        { x: 205, y: 270, type: "file", path: appPath, name: "魏碑.app" },
        { x: 515, y: 270, type: "link", path: "/Applications", name: "应用程序" },
      ],
    },
  });

  await new Promise((resolve, reject) => {
    emitter.on("progress", (event: any) => {
      if (event.type === "step-end" && event.status === "fail") {
        process.stderr.write(`DMG step failed: ${event.title}\n`);
      }
    });
    emitter.on("finish", resolve);
    emitter.on("error", reject);
  });

  process.stdout.write(`dmg_created=${target}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
