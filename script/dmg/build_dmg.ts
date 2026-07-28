#!/usr/bin/env -S npm exec -- tsx
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";

interface DMGProgressEvent {
  type?: string;
  status?: string;
  title?: string;
}

interface DMGEmitter {
  on(
    event: "progress",
    listener: (event: DMGProgressEvent) => void,
  ): DMGEmitter;
  on(event: "finish", listener: () => void): DMGEmitter;
  on(event: "error", listener: (error: Error) => void): DMGEmitter;
}

interface AppDMGFactory {
  (configuration: {
    target: string;
    basepath: string;
    specification: {
      title: string;
      icon: string;
      background: string;
      "icon-size": number;
      format: string;
      filesystem: string;
      window: {
        position: { x: number; y: number };
        size: { width: number; height: number };
      };
      contents: Array<{
        x: number;
        y: number;
        type: "file" | "link";
        path: string;
        name: string;
      }>;
    };
  }): DMGEmitter;
}

// appdmg 0.6.6 does not publish TypeScript declarations.
const require = createRequire(import.meta.url);
const appdmg = require("appdmg") as AppDMGFactory;

const [rootArgument, appArgument, targetArgument, version] =
  process.argv.slice(2);
if (!rootArgument || !appArgument || !targetArgument || !version) {
  throw new Error(
    "usage: build_dmg.ts <repo-root> <魏碑.app> <output.dmg> <version>",
  );
}

const root = path.resolve(rootArgument);
const appPath = path.resolve(appArgument);
const target = path.resolve(targetArgument);
const designSystem = path.join(root, "DesignSystem");
const background = path.join(designSystem, "assets/dmg/dmg-background.png");
const icon = path.join(designSystem, "assets/app-icon/AppIcon.icns");

for (const requiredPath of [
  appPath,
  background,
  `${background.slice(0, -4)}@2x.png`,
  icon,
]) {
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

await new Promise<void>((resolve, reject) => {
  emitter.on("progress", (event) => {
    if (event.type === "step-end" && event.status === "fail") {
      process.stderr.write(`DMG step failed: ${event.title}\n`);
    }
  });
  emitter.on("finish", resolve);
  emitter.on("error", reject);
});

process.stdout.write(`dmg_created=${target}\n`);
