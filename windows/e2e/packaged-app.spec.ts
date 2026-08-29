import {
  _electron as electron,
  expect,
  test,
  type ElectronApplication,
  type Page,
  type TestInfo,
} from "@playwright/test";
import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { themeModes, type Preferences, type ThemeMode } from "../src/shared/contracts";

const WINDOWS_ROOT = fileURLToPath(new URL("../", import.meta.url));
const EVIDENCE_VIEWPORT = { width: 1240, height: 760 } as const;
const DEFAULT_PREFERENCES: Preferences = {
  theme: "paper",
  language: "zh-Hans",
  textScale: 1,
  glassIntensity: 1,
  reduceMotion: true,
  paneOrder: ["reader", "agent", "notes"],
  visiblePanes: ["reader", "agent", "notes"],
  paneWidths: { reader: 1, agent: 1, notes: 1 },
};

const themes: readonly ThemeMode[] = themeModes;

interface SandboxPaths {
  root: string;
  appData: string;
  localAppData: string;
  userData: string;
  home: string;
  temp: string;
  library: string;
}

interface RunningApp {
  application: ElectronApplication;
  page: Page;
  sandbox: SandboxPaths;
}

test.describe("packaged WeiBei Windows UI", () => {
  test.describe.configure({ mode: "serial" });
  test.skip(process.platform !== "win32", "A packaged Windows executable requires a Windows runner.");

  test("shows the fixed title bar, empty state, and course drawer", async ({}, testInfo) => {
    await withPackagedApp(testInfo, async ({ application, page }) => {
      expect(await application.evaluate(({ app }) => app.getName())).toBeTruthy();
      const nativeTitle = await application.evaluate(({ BrowserWindow }) =>
        BrowserWindow.getAllWindows()[0]?.getTitle() ?? "");
      expect(nativeTitle.length).toBeGreaterThan(0);
      expect(nativeTitle).toBe(await page.title());

      const topBar = page.getByTestId("top-bar");
      await expect(topBar).toBeVisible();
      await expect(topBar).toHaveCSS("height", "36px");
      await expect(page.locator(".empty-launcher")).toBeVisible();
      await expect(page.locator(".empty-actions .entry-button")).toHaveCount(3);
      await captureEvidence(page, testInfo, "01-empty-state.png");

      await page.locator(".top-bar-left > .chrome-button").first().click();
      const drawer = page.locator("aside.library-drawer");
      await expect(drawer).toHaveAttribute("aria-hidden", "false");
      await expect(drawer.locator(".drawer-header h2")).toBeVisible();
      await expect(drawer.locator(".drawer-empty")).toBeVisible();
      await captureEvidence(page, testInfo, "02-course-drawer.png");

      await drawer.locator(".drawer-header .chrome-button").click();
      await expect(drawer).toHaveAttribute("aria-hidden", "true");
    });
  });

  test("creates an isolated course and renders all three panes", async ({}, testInfo) => {
    await withPackagedApp(testInfo, async ({ page }) => {
      await page.locator(".empty-actions .entry-button").nth(1).click();
      const namePrompt = page.getByRole("dialog", { name: "新建课程" });
      await expect(namePrompt).toBeVisible();
      await expect(namePrompt.locator("input")).toHaveValue("新课程");
      await namePrompt.locator("input").fill("E2E visual course");
      await namePrompt.getByRole("button", { name: "确定" }).click();

      const workspace = page.locator(".three-pane-workspace");
      await expect(workspace).toBeVisible();
      await expect(workspace).toHaveAttribute("data-pane-count", "3");
      await expect(workspace.locator(".workspace-pane.is-visible")).toHaveCount(3);
      await expect(workspace.locator(".pane-reader .pane-header")).toBeVisible();
      await expect(workspace.locator(".pane-agent .pane-header")).toBeVisible();
      await expect(workspace.locator(".pane-notes .pane-header")).toBeVisible();
      await expect(page.locator(".course-pill")).toBeEnabled();

      const snapshot = await page.evaluate(() => window.weiBei.bootstrap());
      expect(snapshot.activeCourse).not.toBeNull();
      expect(snapshot.courses).toHaveLength(1);
      await captureEvidence(page, testInfo, "03-three-pane-workspace.png");
    });
  });

  test("opens settings and persists every theme through the UI", async ({}, testInfo) => {
    await withPackagedApp(testInfo, async ({ page }) => {
      await page.locator(".top-bar-right > .chrome-button").last().click();
      const settings = page.locator(".settings-sheet[role='dialog']");
      await expect(settings).toBeVisible();
      await expect(settings.locator(".settings-content-header h1")).toBeVisible();
      await captureEvidence(page, testInfo, "04-settings-paper.png");

      const themeButtons = settings.locator(".theme-grid > button");
      await expect(themeButtons).toHaveCount(themes.length);
      const seenThemes = new Set<ThemeMode>();
      for (const index of themes.keys()) {
        const button = themeButtons.nth(index);
        await button.click();
        const appliedTheme = await page.locator("main.app-shell").getAttribute("data-theme") as ThemeMode | null;
        expect(appliedTheme).not.toBeNull();
        expect(themes).toContain(appliedTheme);
        expect(seenThemes.has(appliedTheme!)).toBe(false);
        seenThemes.add(appliedTheme!);
        await expect(button).toHaveClass(/\bis-selected\b/);
        await expect.poll(() => page.evaluate(async () =>
          (await window.weiBei.bootstrap()).preferences.theme)).toBe(appliedTheme);
      }

      expect([...seenThemes].sort()).toEqual([...themes].sort());
      await captureEvidence(page, testInfo, "05-settings-final-theme.png");
    });
  });
});

async function withPackagedApp(
  testInfo: TestInfo,
  run: (app: RunningApp) => Promise<void>,
): Promise<void> {
  const executablePath = await findPackagedExecutable();
  const sandbox = await seedSandbox(testInfo);
  const application = await electron.launch({
    executablePath,
    args: [
      `--user-data-dir=${sandbox.userData}`,
      "--force-device-scale-factor=1",
    ],
    artifactsDir: testInfo.outputPath("electron-artifacts"),
    chromiumSandbox: true,
    cwd: path.dirname(executablePath),
    env: isolatedEnvironment(sandbox),
    timeout: 30_000,
  });

  try {
    const page = await application.firstWindow();
    await application.evaluate(({ BrowserWindow }, viewport) => {
      const window = BrowserWindow.getAllWindows()[0];
      if (!window) throw new Error("WeiBei did not create a BrowserWindow");
      window.setContentSize(viewport.width, viewport.height);
      window.show();
      window.focus();
    }, EVIDENCE_VIEWPORT);
    await page.setViewportSize(EVIDENCE_VIEWPORT);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.addStyleTag({ content: [
      "*, *::before, *::after {",
      "  animation-delay: 0ms !important;",
      "  animation-duration: 0.01ms !important;",
      "  animation-iteration-count: 1 !important;",
      "  caret-color: transparent !important;",
      "  scroll-behavior: auto !important;",
      "  transition-delay: 0ms !important;",
      "  transition-duration: 0.01ms !important;",
      "}",
    ].join("\n") });

    await expect(page.locator("main.app-shell")).toBeVisible();
    await expect(page.locator("main.app-shell")).toHaveAttribute("data-reduce-motion", "true");
    await expect.poll(() => page.evaluate(() => [window.innerWidth, window.innerHeight]))
      .toEqual([EVIDENCE_VIEWPORT.width, EVIDENCE_VIEWPORT.height]);
    await page.evaluate(async () => {
      await document.fonts.ready;
    });

    const runtime = await application.evaluate(({ app, BrowserWindow }) => ({
      appPath: app.getAppPath(),
      executablePath: app.getPath("exe"),
      isPackaged: app.isPackaged,
      userData: app.getPath("userData"),
      windowVisible: BrowserWindow.getAllWindows()[0]?.isVisible() ?? false,
    }));
    expect(runtime.isPackaged).toBe(true);
    expect(path.basename(runtime.appPath).toLocaleLowerCase("en-US")).toBe("app.asar");
    expect(equalWindowsPath(runtime.executablePath, executablePath)).toBe(true);
    expect(runtime.windowVisible).toBe(true);
    expect(equalWindowsPath(runtime.userData, sandbox.userData)).toBe(true);
    const snapshot = await page.evaluate(() => window.weiBei.bootstrap());
    expect(snapshot.platform).toBe("windows");
    expect(equalWindowsPath(snapshot.libraryRootPath, sandbox.library)).toBe(true);
    await expect(page.locator(".status-banner")).toHaveCount(0);

    await run({ application, page, sandbox });
  } finally {
    await application.close();
  }
}

async function seedSandbox(testInfo: TestInfo): Promise<SandboxPaths> {
  const root = testInfo.outputPath("profile");
  const sandbox: SandboxPaths = {
    root,
    appData: path.join(root, "AppData", "Roaming"),
    localAppData: path.join(root, "AppData", "Local"),
    userData: path.join(root, "UserData"),
    home: path.join(root, "User"),
    temp: path.join(root, "Temp"),
    library: path.join(root, "Library"),
  };
  await Promise.all(Object.values(sandbox).map((directory) =>
    mkdir(directory, { recursive: true })));

  const packageJSON = JSON.parse(await readFile(path.join(WINDOWS_ROOT, "package.json"), "utf8")) as {
    name?: string;
    productName?: string;
    build?: { productName?: string };
  };
  const appNames = new Set(
    [packageJSON.productName, packageJSON.build?.productName, packageJSON.name]
      .filter((value): value is string => Boolean(value)),
  );
  for (const appName of [...appNames]) {
    const finalSegment = appName.split(/[\\/]/u).at(-1);
    if (finalSegment) appNames.add(finalSegment);
    appNames.add(appName.replace(/^@/u, "").replace(/[\\/]/gu, "-"));
  }
  const state = JSON.stringify({
    schemaVersion: 1,
    libraryRootPath: sandbox.library,
    activeCourseId: null,
    activeItemsByCourse: {},
    activeNotesByCourse: {},
    activeSessionsByCourse: {},
    preferences: DEFAULT_PREFERENCES,
    provider: {
      providerId: "openai",
      model: "gpt-5.4",
      baseUrl: "https://api.openai.com/v1",
      hasCredential: false,
    },
  }, null, 2) + "\n";
  await writeFile(path.join(sandbox.userData, "windows-state.json"), state, "utf8");
  for (const appName of appNames) {
    const userData = path.resolve(sandbox.appData, appName);
    if (!isPathInside(sandbox.appData, userData)) continue;
    await mkdir(userData, { recursive: true });
    await writeFile(path.join(userData, "windows-state.json"), state, "utf8");
  }
  return sandbox;
}

function isolatedEnvironment(sandbox: SandboxPaths): Record<string, string> {
  const environment = Object.fromEntries(
    Object.entries(process.env).filter((entry): entry is [string, string] =>
      typeof entry[1] === "string"),
  );
  delete environment.WEIBEI_RENDERER_URL;
  const parsedHome = path.parse(sandbox.home);
  const homePath = sandbox.home.slice(parsedHome.root.length).replaceAll("/", "\\");
  return {
    ...environment,
    APPDATA: sandbox.appData,
    LOCALAPPDATA: sandbox.localAppData,
    USERPROFILE: sandbox.home,
    HOME: sandbox.home,
    HOMEDRIVE: parsedHome.root.replace(/[\\/]$/u, ""),
    HOMEPATH: `\\${homePath}`,
    TEMP: sandbox.temp,
    TMP: sandbox.temp,
    ELECTRON_ENABLE_LOGGING: "1",
    ELECTRON_LOG_FILE: path.join(sandbox.root, "electron.log"),
    WEIBEI_E2E_PROFILE_ROOT: sandbox.root,
  };
}

async function findPackagedExecutable(): Promise<string> {
  const explicit = process.env.WEIBEI_E2E_EXECUTABLE?.trim();
  if (explicit) {
    const candidate = path.resolve(explicit);
    if (path.extname(candidate).toLocaleLowerCase("en-US") !== ".exe"
        || !(await stat(candidate).catch(() => null))?.isFile()) {
      throw new Error(`WEIBEI_E2E_EXECUTABLE is not a packaged .exe: ${candidate}`);
    }
    return candidate;
  }

  const releaseDirectory = path.resolve(
    process.env.WEIBEI_E2E_RELEASE_DIR?.trim()
      || path.join(WINDOWS_ROOT, "release", "win-unpacked"),
  );
  const entries = await readdir(releaseDirectory, { withFileTypes: true }).catch((error: unknown) => {
    throw new Error(
      `Packaged application directory is unavailable: ${releaseDirectory}. Run npm run package:dir first.`,
      { cause: error },
    );
  });
  const candidates = entries
    .filter((entry) => entry.isFile() && entry.name.toLocaleLowerCase("en-US").endsWith(".exe"))
    .filter((entry) => !/(?:elevate|unins|uninstall|squirrel)/iu.test(entry.name))
    .map((entry) => path.join(releaseDirectory, entry.name));
  const packageJSON = JSON.parse(await readFile(path.join(WINDOWS_ROOT, "package.json"), "utf8")) as {
    productName?: string;
    build?: { executableName?: string; productName?: string };
  };
  const configuredExecutableName = packageJSON.build?.executableName
    ?? packageJSON.build?.productName
    ?? packageJSON.productName;
  const preferred = configuredExecutableName
    ? candidates.find((candidate) => path.basename(candidate).localeCompare(
      `${configuredExecutableName}.exe`,
      "en-US",
      { sensitivity: "accent" },
    ) === 0)
    : undefined;
  if (preferred) return preferred;
  if (candidates.length === 1) return candidates[0];
  throw new Error(
    `Expected one WeiBei executable in ${releaseDirectory}; found: ${candidates.join(", ") || "none"}`,
  );
}

async function captureEvidence(page: Page, testInfo: TestInfo, name: string): Promise<void> {
  const directory = testInfo.outputPath("evidence");
  const outputPath = path.join(directory, name);
  await mkdir(directory, { recursive: true });
  const png = await page.screenshot({
    path: outputPath,
    animations: "disabled",
    caret: "hide",
    scale: "css",
  });
  expect(png.subarray(12, 16).toString("ascii")).toBe("IHDR");
  expect([png.readUInt32BE(16), png.readUInt32BE(20)])
    .toEqual([EVIDENCE_VIEWPORT.width, EVIDENCE_VIEWPORT.height]);
  await testInfo.attach(name, { path: outputPath, contentType: "image/png" });
}

function isPathInside(parent: string, child: string): boolean {
  const relative = path.relative(path.resolve(parent), path.resolve(child));
  return relative === "" || (!path.isAbsolute(relative)
    && relative !== ".."
    && !relative.startsWith(`..${path.sep}`));
}

function equalWindowsPath(left: string, right: string): boolean {
  return path.resolve(left).toLocaleLowerCase("en-US")
    === path.resolve(right).toLocaleLowerCase("en-US");
}
