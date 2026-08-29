import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { app, BrowserWindow, net, protocol, safeStorage, session } from "electron";
import { WeiBeiController } from "./controller";
import { registerIPC } from "./ipc";
import { CredentialVault, type SafeStorageAdapter } from "./services/credential-vault";
import {
  DocumentGrantService,
  documentGrantScheme,
  documentGrantSchemePrivileges,
} from "./services/document-grants";

const editorScheme = "weibei-editor";
protocol.registerSchemesAsPrivileged([
  { scheme: documentGrantScheme, privileges: documentGrantSchemePrivileges },
  {
    scheme: editorScheme,
    privileges: {
      standard: true,
      secure: true,
      supportFetchAPI: true,
      stream: true,
      corsEnabled: true,
    },
  },
]);

if (!app.requestSingleInstanceLock()) app.quit();

let mainWindow: BrowserWindow | null = null;
let disposeIPC: (() => void) | null = null;
let controller: WeiBeiController | null = null;
let controllerShutdown: Promise<void> | null = null;

app.on("second-instance", () => {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
});

app.whenReady().then(async () => {
  app.setAppUserModelId("app.weibei.desktop");
  const rendererScope = randomUUID();
  const grants = new DocumentGrantService();
  const rendererURL = process.env.WEIBEI_RENDERER_URL;
  await registerEditorProtocol(rendererURL);
  await session.defaultSession.protocol.handle(documentGrantScheme, (request) => grants.handleRequest(request, rendererScope));
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  session.defaultSession.setPermissionCheckHandler(() => false);

  const userDataPath = app.getPath("userData");
  const localDataPath = process.env.LOCALAPPDATA
    ? path.join(process.env.LOCALAPPDATA, "WeiBei")
    : path.join(userDataPath, "LocalCache");
  const vault = await CredentialVault.open({
    vaultPath: path.join(userDataPath, "credentials.encrypted.json"),
    safeStorage: electronSafeStorageAdapter(),
  });

  const window = new BrowserWindow({
    title: "魏碑",
    width: 1240,
    height: 760,
    minWidth: 520,
    minHeight: 720,
    show: false,
    backgroundColor: "#f4ead5",
    titleBarStyle: "hidden",
    titleBarOverlay: { color: "#00000000", symbolColor: "#5e554a", height: 36 },
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
      devTools: !app.isPackaged,
    },
  });
  mainWindow = window;
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event, target) => {
    const allowed = rendererURL ? target.startsWith(rendererURL) : target.startsWith("file:");
    if (!allowed) event.preventDefault();
  });
  window.once("ready-to-show", () => window.show());

  let libraryRootPath = path.join(userDataPath, "魏碑资料库");
  try {
    libraryRootPath = path.join(app.getPath("documents"), "魏碑资料库");
  } catch {
    console.warn(
      `Windows Documents folder is unavailable; using the app-owned WeiBei library at ${libraryRootPath}.`,
    );
  }
  controller = await WeiBeiController.open({
    window,
    appVersion: app.getVersion(),
    userDataPath,
    localDataPath,
    defaultLibraryRootPath: libraryRootPath,
    rendererScope,
    grants,
    vault,
  });
  disposeIPC = registerIPC(controller, window);
  window.on("closed", () => {
    disposeIPC?.();
    disposeIPC = null;
    grants.revokeScope(rendererScope);
    mainWindow = null;
  });
  if (rendererURL) await window.loadURL(rendererURL);
  else await window.loadFile(path.join(app.getAppPath(), "dist", "renderer", "index.html"));
}).catch((error) => {
  console.error(error);
  void shutdownController().finally(() => app.exit(1));
});

app.on("before-quit", (event) => {
  if (!controller) return;
  event.preventDefault();
  void shutdownController().finally(() => app.quit());
});

app.on("window-all-closed", () => {
  void shutdownController().finally(() => app.quit());
});

function shutdownController(): Promise<void> {
  if (controllerShutdown) return controllerShutdown;
  const activeController = controller;
  controller = null;
  controllerShutdown = activeController?.close() ?? Promise.resolve();
  return controllerShutdown;
}

async function registerEditorProtocol(rendererURL?: string) {
  await session.defaultSession.protocol.handle(editorScheme, async (request) => {
    let url: URL;
    try { url = new URL(request.url); } catch { return new Response(null, { status: 400 }); }
    if (url.hostname !== "app" || url.username || url.password || url.port || url.hash) return new Response(null, { status: 404 });
    let pathname: string;
    try { pathname = decodeURIComponent(url.pathname); } catch { return new Response(null, { status: 400 }); }
    if (!pathname.startsWith("/Editor/") && !pathname.startsWith("/Fonts/")) return new Response(null, { status: 404 });
    const normalized = path.posix.normalize(pathname);
    if (normalized !== pathname || normalized.includes("..")) return new Response(null, { status: 404 });
    if (rendererURL) {
      const upstream = new URL(`${normalized}${url.search}`, rendererURL);
      return net.fetch(upstream.toString(), { bypassCustomProtocolHandlers: true });
    }
    const rendererRoot = path.join(app.getAppPath(), "dist", "renderer");
    const filePath = path.join(rendererRoot, ...normalized.split("/").filter(Boolean));
    const relative = path.relative(rendererRoot, filePath);
    if (path.isAbsolute(relative) || relative === ".." || relative.startsWith(`..${path.sep}`)) return new Response(null, { status: 404 });
    try {
      const bytes = await readFile(filePath);
      return new Response(bytes, {
        status: 200,
        headers: {
          "Content-Type": mediaType(filePath),
          "Cache-Control": app.isPackaged ? "public, max-age=31536000, immutable" : "no-store",
          "Cross-Origin-Resource-Policy": "same-origin",
          "X-Content-Type-Options": "nosniff",
        },
      });
    } catch { return new Response(null, { status: 404 }); }
  });
}

function electronSafeStorageAdapter(): SafeStorageAdapter {
  const storage = safeStorage as typeof safeStorage & {
    isAsyncEncryptionAvailable?: () => Promise<boolean>;
    encryptStringAsync?: (value: string) => Promise<Buffer>;
    decryptStringAsync?: (value: Buffer) => Promise<{ result: string; shouldReEncrypt: boolean }>;
  };
  return {
    async isAsyncEncryptionAvailable() {
      return storage.isAsyncEncryptionAvailable
        ? storage.isAsyncEncryptionAvailable()
        : storage.isEncryptionAvailable();
    },
    async encryptStringAsync(value) {
      return storage.encryptStringAsync
        ? Buffer.from(await storage.encryptStringAsync(value))
        : storage.encryptString(value);
    },
    async decryptStringAsync(value) {
      if (storage.decryptStringAsync) return storage.decryptStringAsync(value);
      return { result: storage.decryptString(value), shouldReEncrypt: false };
    },
  };
}

function mediaType(filePath: string): string {
  return {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
    ".svg": "image/svg+xml",
    ".png": "image/png",
  }[path.extname(filePath).toLocaleLowerCase("en-US")] ?? "application/octet-stream";
}
