import {
  editorBridgeMessageNames,
  editorHostTransportVersion,
  type EditorBridgeEvent,
  type EditorBridgeMessageName,
  type EditorCommand,
  type EditorFrameReadyMessage,
  type EditorFrameRequest,
  type EditorHostBootstrap,
  type EditorHostBootstrapInput,
  type EditorHostInitMessage,
  type EditorRuntimeCall,
} from "../../shared/editor-contracts";

export interface WeiBeiEditorHostOptions {
  /** Defaults to the packaged canonical-derived Windows host page. */
  frameURL?: string | URL;
  instanceId?: string;
}

export type EditorEventListener = (event: EditorBridgeEvent) => void;

const bridgeMessageNameSet = new Set<string>(editorBridgeMessageNames);
const viewerOnlyMethods = new Set<EditorRuntimeCall["method"]>([
  "setMarkdown",
  "updateStreamingMarkdown",
  "appendStreamingMarkdown",
  "finishStreamingMarkdown",
  "setDocumentID",
]);
const editorOnlyMethods = new Set<EditorRuntimeCall["method"]>([
  "resolveAttachment",
  "rejectAttachment",
  "resolveImagePicker",
  "cancelImagePicker",
  "discardImagePicker",
  "rejectImagePicker",
]);

export function normalizeEditorHostBootstrap(
  input: EditorHostBootstrapInput,
): EditorHostBootstrap {
  return {
    markdown: input.markdown,
    documentID: input.documentID,
    documentGeneration: Number.isInteger(input.documentGeneration)
      && Number(input.documentGeneration) >= 0
      ? Number(input.documentGeneration)
      : 0,
    editable: input.editable,
    markdownBaseURL: input.markdownBaseURL ?? "",
    localImageScheme: input.localImageScheme || "weibeiimage",
    theme: input.theme ?? "paper",
    interfaceLanguage: input.interfaceLanguage ?? "zh-Hans",
    compactPreview: input.compactPreview ?? false,
    wideTypography: input.wideTypography ?? false,
    reduceMotion: input.reduceMotion ?? false,
    textScale: Number.isFinite(input.textScale) && Number(input.textScale) > 0
      ? Number(input.textScale)
      : 1,
  };
}

function isFrameReadyMessage(value: unknown): value is EditorFrameReadyMessage {
  if (!value || typeof value !== "object") return false;
  const message = value as Partial<EditorFrameReadyMessage>;
  return message.kind === "weibei-editor-frame-ready"
    && message.transportVersion === editorHostTransportVersion
    && typeof message.instanceId === "string"
    && typeof message.frameNonce === "string"
    && message.frameNonce.length > 0;
}

function isEditorBridgeEvent(value: unknown): value is EditorBridgeEvent {
  if (!value || typeof value !== "object") return false;
  const event = value as Partial<EditorBridgeEvent>;
  return event.kind === "event"
    && event.transportVersion === editorHostTransportVersion
    && typeof event.instanceId === "string"
    && bridgeMessageNameSet.has(String(event.name))
    && Boolean(event.body)
    && typeof event.body === "object";
}

function originForURL(url: URL): string {
  return url.origin === "null" ? "null" : url.origin;
}

/**
 * Owns one isolated editor iframe and its ordered MessageChannel transport.
 * The frame emits a nonce-bearing ready message before any canonical bundle is
 * loaded. Only then does this host transfer bootstrap state and a dedicated
 * port; the frame queues calls until the canonical editorReady event.
 */
export class WeiBeiEditorHost {
  readonly instanceId: string;
  readonly bootstrap: EditorHostBootstrap;
  readonly frameURL: URL;

  private port: MessagePort | null = null;
  private connectedFrameNonce: string | null = null;
  private connectionEpoch = 0;
  private destroyed = false;
  private readonly pendingRequests: EditorFrameRequest[] = [];
  private readonly listeners = new Set<EditorEventListener>();

  constructor(
    readonly frame: HTMLIFrameElement,
    bootstrap: EditorHostBootstrapInput,
    options: WeiBeiEditorHostOptions = {},
  ) {
    this.bootstrap = normalizeEditorHostBootstrap(bootstrap);
    this.instanceId = options.instanceId ?? crypto.randomUUID();
    this.frameURL = new URL(
      options.frameURL ?? "./Editor/windows-host.html",
      document.baseURI,
    );
    this.frameURL.searchParams.set("instanceId", this.instanceId);
  }

  mount(): void {
    if (this.destroyed) {
      throw new Error("Cannot mount a destroyed WeiBei editor host");
    }
    window.addEventListener("message", this.handleWindowMessage);
    this.frame.src = this.frameURL.href;
  }

  subscribe(listener: EditorEventListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  dispatchCommand(command: EditorCommand): void {
    if (!this.bootstrap.editable) {
      throw new Error("Cannot dispatch an editable command to a viewer frame");
    }
    this.send({
      kind: "command",
      transportVersion: editorHostTransportVersion,
      instanceId: this.instanceId,
      command,
    });
  }

  call(call: EditorRuntimeCall): void {
    if (this.bootstrap.editable && viewerOnlyMethods.has(call.method)) {
      throw new Error(`Viewer-only WeiBei editor method: ${call.method}`);
    }
    if (!this.bootstrap.editable && editorOnlyMethods.has(call.method)) {
      throw new Error(`Editable-only WeiBei editor method: ${call.method}`);
    }
    this.send({
      kind: "call",
      transportVersion: editorHostTransportVersion,
      instanceId: this.instanceId,
      call,
    });
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    window.removeEventListener("message", this.handleWindowMessage);
    if (this.port) {
      this.port.postMessage({
        kind: "dispose",
        transportVersion: editorHostTransportVersion,
        instanceId: this.instanceId,
      } satisfies EditorFrameRequest);
      this.port.close();
    }
    this.port = null;
    this.pendingRequests.splice(0);
    this.listeners.clear();
  }

  private readonly handleWindowMessage = (event: MessageEvent<unknown>): void => {
    if (this.destroyed
        || event.source !== this.frame.contentWindow
        || !isFrameReadyMessage(event.data)
        || event.data.instanceId !== this.instanceId) return;

    const expectedOrigin = originForURL(this.frameURL);
    if (expectedOrigin !== "null" && event.origin !== expectedOrigin) return;
    if (expectedOrigin === "null" && event.origin !== "null") return;
    if (event.data.frameNonce === this.connectedFrameNonce && this.port) return;
    this.connect(event.data.frameNonce);
  };

  private connect(frameNonce: string): void {
    this.port?.close();
    this.connectedFrameNonce = frameNonce;
    const epoch = ++this.connectionEpoch;
    const channel = new MessageChannel();
    this.port = channel.port1;
    channel.port1.addEventListener("message", (event: MessageEvent<unknown>) => {
      if (this.destroyed || epoch !== this.connectionEpoch
          || !isEditorBridgeEvent(event.data)
          || event.data.instanceId !== this.instanceId) return;
      for (const listener of this.listeners) listener(event.data);
    });
    channel.port1.start();

    const init: EditorHostInitMessage = {
      kind: "weibei-editor-host-init",
      transportVersion: editorHostTransportVersion,
      instanceId: this.instanceId,
      frameNonce,
      bootstrap: this.bootstrap,
    };
    const targetOrigin = originForURL(this.frameURL);
    this.frame.contentWindow?.postMessage(
      init,
      targetOrigin === "null" ? "*" : targetOrigin,
      [channel.port2],
    );
    for (const request of this.pendingRequests.splice(0)) {
      channel.port1.postMessage(request);
    }
  }

  private send(request: EditorFrameRequest): void {
    if (this.destroyed) {
      throw new Error("Cannot call a destroyed WeiBei editor host");
    }
    if (this.port) {
      this.port.postMessage(request);
      return;
    }
    this.pendingRequests.push(request);
  }
}

export type { EditorBridgeMessageName };
