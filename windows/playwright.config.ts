import { defineConfig } from "@playwright/test";
import { fileURLToPath } from "node:url";

const windowsRoot = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
  testDir: fileURLToPath(new URL("./e2e", import.meta.url)),
  outputDir: fileURLToPath(new URL("./test-results", import.meta.url)),
  preserveOutput: "always",
  fullyParallel: false,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 8_000 },
  reporter: [
    ["list"],
    ["html", {
      open: "never",
      outputFolder: fileURLToPath(new URL("./playwright-report", import.meta.url)),
    }],
  ],
  metadata: {
    target: "packaged Windows Electron application",
    evidenceViewport: "1240x760",
    windowsRoot,
  },
  use: {
    actionTimeout: 10_000,
    trace: "retain-on-failure",
  },
});
