import {
  editorHostTransportVersion,
  editorRuntimeMethods,
  type EditorFrameReadyMessage,
  type EditorFrameRequest,
  type EditorHostBootstrap,
  type EditorHostInitMessage,
  type EditorRuntimeCall,
} from "../../shared/editor-contracts";
import {
  DeferredEditorEventBridge,
  DeferredEditorRequestQueue,
} from "./bridge-queue";

type EditorRuntime = Record<string, ((...args: unknown[]) => unknown) | undefined>;
type ReadyEditorFrameRequest = Exclude<EditorFrameRequest, { kind: "dispose" }>;

declare global {
  interface Window {
    webkit?: { messageHandlers: DeferredEditorEventBridge["handlers"] };
    initialMarkdown?: string;
    weiBeiDocumentID?: string;
    weiBeiDocumentGeneration?: number;
    weiBeiMarkdownEditable?: boolean;
    weiBeiMarkdownBaseURL?: string;
    weiBeiLocalImageScheme?: string;
    weiBeiTheme?: string;
    weiBeiInterfaceLanguage?: string;
    weiBeiMarkdownCompactPreview?: boolean;
    weiBeiChatWideTypography?: boolean;
    weiBeiReduceMotion?: boolean;
    weiBeiTextScale?: number;
    WeiBeiEditor?: EditorRuntime;
    WeiBeiEditorBootFailed?: (error: unknown) => void;
  }
}

const instanceId = new URL(window.location.href).searchParams.get("instanceId") ?? "";
const frameNonce = crypto.randomUUID();
let initialized = false;
let hostPort: MessagePort | null = null;

const requestQueue = new DeferredEditorRequestQueue<ReadyEditorFrameRequest>((request) => {
  try {
    executeReadyRequest(request);
  } catch (error) {
    reportFailure(error);
  }
});

const eventBridge = new DeferredEditorEventBridge(instanceId, (name) => {
  if (name !== "editorReady") return;
  requestQueue.markReady();
});

Object.defineProperty(window, "webkit", {
  configurable: false,
  enumerable: false,
  writable: false,
  value: Object.freeze({ messageHandlers: eventBridge.handlers }),
});

const runtimeMethodNames = new Set<string>(editorRuntimeMethods);
const editorThemes = new Set([
  "paper",
  "xuan",
  "inkstone",
  "stele",
  "glassLight",
  "glassDark",
  "glassMist",
  "glassSlate",
]);

function isBootstrap(value: unknown): value is EditorHostBootstrap {
  if (!value || typeof value !== "object") return false;
  const bootstrap = value as Partial<EditorHostBootstrap>;
  return typeof bootstrap.markdown === "string"
    && typeof bootstrap.documentID === "string"
    && Number.isInteger(bootstrap.documentGeneration)
    && Number(bootstrap.documentGeneration) >= 0
    && typeof bootstrap.editable === "boolean"
    && typeof bootstrap.markdownBaseURL === "string"
    && typeof bootstrap.localImageScheme === "string"
    && editorThemes.has(String(bootstrap.theme))
    && (bootstrap.interfaceLanguage === "zh-Hans" || bootstrap.interfaceLanguage === "en")
    && typeof bootstrap.compactPreview === "boolean"
    && typeof bootstrap.wideTypography === "boolean"
    && typeof bootstrap.reduceMotion === "boolean"
    && typeof bootstrap.textScale === "number"
    && Number.isFinite(bootstrap.textScale)
    && bootstrap.textScale > 0;
}

function isHostInitMessage(value: unknown): value is EditorHostInitMessage {
  if (!value || typeof value !== "object") return false;
  const message = value as Partial<EditorHostInitMessage>;
  return message.kind === "weibei-editor-host-init"
    && message.transportVersion === editorHostTransportVersion
    && message.instanceId === instanceId
    && message.frameNonce === frameNonce
    && isBootstrap(message.bootstrap);
}

function isFrameRequest(value: unknown): value is EditorFrameRequest {
  if (!value || typeof value !== "object") return false;
  const request = value as Partial<EditorFrameRequest>;
  if (request.transportVersion !== editorHostTransportVersion
      || request.instanceId !== instanceId) return false;
  if (request.kind === "dispose") return true;
  if (request.kind === "command") {
    return Boolean(request.command) && typeof request.command === "object";
  }
  return request.kind === "call"
    && Boolean(request.call)
    && typeof request.call === "object"
    && runtimeMethodNames.has(String(request.call?.method))
    && Array.isArray(request.call?.args);
}

function invokeRuntimeCall(call: EditorRuntimeCall): void {
  const method = window.WeiBeiEditor?.[call.method];
  if (typeof method !== "function") {
    throw new Error(`WeiBei editor method is unavailable: ${call.method}`);
  }
  method(...call.args);
}

function processRequest(request: EditorFrameRequest): void {
  if (request.kind === "dispose") {
    requestQueue.clear();
    hostPort?.close();
    hostPort = null;
    eventBridge.close();
    return;
  }
  requestQueue.enqueue(request);
}

function executeReadyRequest(request: ReadyEditorFrameRequest): void {
  if (request.kind === "command") {
    const dispatch = window.WeiBeiEditor?.dispatchCommand;
    if (typeof dispatch !== "function") {
      throw new Error("WeiBei editor command dispatch is unavailable");
    }
    dispatch(request.command);
    return;
  }
  invokeRuntimeCall(request.call);
}

function reportFailure(error: unknown): void {
  if (window.WeiBeiEditorBootFailed) {
    window.WeiBeiEditorBootFailed(error);
    return;
  }
  eventBridge.handlers.editorFailure.postMessage({
    documentID: window.weiBeiDocumentID ?? "",
    message: error instanceof Error ? error.stack ?? error.message : String(error),
  });
}

function installSelectionMarkStyles(): void {
  const style = document.createElement("style");
  style.dataset.weibeiWindowsSelectionMarks = "true";
  style.textContent = `
    .weibei-selection-ask-mark {
      text-decoration-line: underline;
      text-decoration-color: rgba(145, 38, 27, 0.72);
      text-decoration-thickness: 1.5px;
      text-underline-offset: 3px;
      cursor: pointer;
      border-radius: 2px;
      transition: background-color 120ms ease;
    }
    .weibei-selection-ask-mark:hover { background-color: rgba(145, 38, 27, 0.12); }
    [data-weibei-theme="inkstone"] .weibei-selection-ask-mark {
      text-decoration-color: rgba(200, 120, 100, 0.85);
    }
    [data-weibei-theme="inkstone"] .weibei-selection-ask-mark:hover {
      background-color: rgba(200, 120, 100, 0.16);
    }
    .weibei-remark-mark {
      cursor: pointer;
      border-radius: 2px;
      transition: background-color 120ms ease;
    }
    .weibei-remark-mark::after {
      content: "";
      display: inline-block;
      width: 9px;
      height: 9px;
      margin-left: 5px;
      vertical-align: -0.06em;
      border-radius: 50%;
      background-color: rgba(145, 38, 27, 1);
    }
    .weibei-remark-mark:hover { background-color: rgba(145, 38, 27, 0.14); }
    [data-weibei-theme="inkstone"] .weibei-remark-mark::after {
      background-color: rgba(200, 120, 100, 1);
    }
    [data-weibei-theme="inkstone"] .weibei-remark-mark:hover {
      background-color: rgba(200, 120, 100, 0.18);
    }
  `;
  document.documentElement.appendChild(style);
}

function installNavigationGuard(): void {
  document.addEventListener("click", (event) => {
    const anchor = event.target instanceof Element
      ? event.target.closest("a[href]")
      : null;
    const href = anchor?.getAttribute("href") ?? "";
    if (!href || href.startsWith("#")) return;
    let target: URL;
    try {
      target = new URL(href, window.location.href);
    } catch {
      event.preventDefault();
      return;
    }
    const current = new URL(window.location.href);
    if (target.hash
        && target.origin === current.origin
        && target.pathname === current.pathname
        && target.search === current.search) return;
    if (["http:", "https:", "mailto:"].includes(target.protocol)) {
      event.preventDefault();
      event.stopPropagation();
      eventBridge.handlers.externalLinkActivated.postMessage({
        url: target.href,
      });
      return;
    }
    // Canonical source/wiki handlers own their private schemes. Everything
    // else is blocked so a link can never replace the editor frame.
    if (target.protocol !== "weibei-source:"
        && target.protocol !== "weibei-source-group:") {
      event.preventDefault();
    }
  }, true);
}

function applyBootstrap(bootstrap: EditorHostBootstrap): void {
  window.initialMarkdown = bootstrap.markdown;
  window.weiBeiDocumentID = bootstrap.documentID;
  window.weiBeiDocumentGeneration = bootstrap.documentGeneration;
  window.weiBeiMarkdownEditable = bootstrap.editable;
  window.weiBeiMarkdownBaseURL = bootstrap.markdownBaseURL;
  window.weiBeiLocalImageScheme = bootstrap.localImageScheme;
  window.weiBeiTheme = bootstrap.theme;
  window.weiBeiInterfaceLanguage = bootstrap.interfaceLanguage;
  window.weiBeiMarkdownCompactPreview = bootstrap.compactPreview;
  window.weiBeiChatWideTypography = bootstrap.wideTypography;
  window.weiBeiReduceMotion = bootstrap.reduceMotion;
  window.weiBeiTextScale = bootstrap.textScale;

  const root = document.documentElement;
  root.dataset.weibeiReduceMotion = String(bootstrap.reduceMotion);
  root.style.setProperty("--weibei-text-scale", String(bootstrap.textScale));
  root.dataset.weibeiTheme = bootstrap.theme === "glassLight"
      || bootstrap.theme === "glassMist"
    ? "xuan"
    : bootstrap.theme === "glassDark" || bootstrap.theme === "glassSlate"
      ? "stele"
      : bootstrap.theme;
  if (bootstrap.theme.startsWith("glass")) {
    root.dataset.weibeiGlass = bootstrap.theme;
  } else {
    delete root.dataset.weibeiGlass;
  }
  root.dataset.weibeiLanguage = bootstrap.interfaceLanguage;
  root.dataset.weibeiCompactPreview = String(bootstrap.compactPreview);
  root.dataset.weibeiChatWide = String(bootstrap.wideTypography);

  installSelectionMarkStyles();
  installNavigationGuard();
  if (bootstrap.compactPreview) {
    window.addEventListener("wheel", (event) => {
      if (Math.abs(event.deltaY) < Math.abs(event.deltaX)) return;
      event.preventDefault();
      eventBridge.handlers.compactPreviewWheel.postMessage({
        documentID: bootstrap.documentID,
        deltaY: event.deltaY,
      });
    }, { capture: true, passive: false });
  }
}

function loadCanonicalEntry(editable: boolean): void {
  const script = document.createElement("script");
  script.src = editable ? "./editor-entry.js" : "./viewer-entry.js";
  script.onerror = () => reportFailure(new Error("WeiBei canonical editor entry failed to load"));
  document.body.appendChild(script);
}

function initialize(message: EditorHostInitMessage, port: MessagePort): void {
  if (initialized) return;
  initialized = true;
  hostPort = port;
  port.addEventListener("message", (event: MessageEvent<unknown>) => {
    if (!isFrameRequest(event.data)) return;
    try {
      processRequest(event.data);
    } catch (error) {
      reportFailure(error);
    }
  });
  eventBridge.attach(port);
  applyBootstrap(message.bootstrap);
  loadCanonicalEntry(message.bootstrap.editable);
}

window.addEventListener("message", (event: MessageEvent<unknown>) => {
  if (event.source !== window.parent || !isHostInitMessage(event.data)) return;
  const port = event.ports[0];
  if (!port) {
    reportFailure(new Error("WeiBei editor host did not transfer a MessagePort"));
    return;
  }
  try {
    initialize(event.data, port);
  } catch (error) {
    reportFailure(error);
  }
});

const readyMessage: EditorFrameReadyMessage = {
  kind: "weibei-editor-frame-ready",
  transportVersion: editorHostTransportVersion,
  instanceId,
  frameNonce,
};
window.parent.postMessage(readyMessage, "*");
