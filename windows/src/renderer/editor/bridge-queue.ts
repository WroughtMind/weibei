import type {
  EditorBridgeEvent,
  EditorBridgeEventBodies,
  EditorBridgeMessageName,
} from "../../shared/editor-contracts";
import {
  editorBridgeMessageNames,
  editorHostTransportVersion,
} from "../../shared/editor-contracts";

export interface EditorMessagePortWriter {
  postMessage(message: EditorBridgeEvent): void;
  start?(): void;
  close?(): void;
}

export interface WebKitMessageHandler {
  postMessage(body: unknown): void;
}

export type WebKitMessageHandlers = Readonly<
  Record<EditorBridgeMessageName, Readonly<WebKitMessageHandler>>
>;

/** Keeps host calls ordered until the canonical editorReady boundary. */
export class DeferredEditorRequestQueue<Request> {
  static readonly maximumQueuedRequests = 512;

  private ready = false;
  private readonly pending: Request[] = [];

  constructor(private readonly consume: (request: Request) => void) {}

  enqueue(request: Request): void {
    if (this.ready) {
      this.consume(request);
      return;
    }
    if (this.pending.length === DeferredEditorRequestQueue.maximumQueuedRequests) {
      throw new Error("WeiBei editor request queue is full");
    }
    this.pending.push(request);
  }

  markReady(): void {
    if (this.ready) return;
    this.ready = true;
    for (const request of this.pending.splice(0)) this.consume(request);
  }

  clear(): void {
    this.pending.splice(0);
  }
}

/**
 * A bounded, ordered queue for events emitted before the parent transfers the
 * MessagePort. In particular, this retains the first editorFailure/editorReady
 * instead of depending on iframe and parent scheduling.
 */
export class DeferredEditorEventBridge {
  static readonly maximumQueuedEvents = 512;

  readonly handlers: WebKitMessageHandlers;
  private port: EditorMessagePortWriter | null = null;
  private readonly pending: EditorBridgeEvent[] = [];

  constructor(
    private readonly instanceId: string,
    private readonly onEvent?: (
      name: EditorBridgeMessageName,
      body: unknown,
    ) => void,
  ) {
    const handlers = Object.create(null) as Record<
      EditorBridgeMessageName,
      Readonly<WebKitMessageHandler>
    >;
    for (const name of editorBridgeMessageNames) {
      handlers[name] = Object.freeze({
        postMessage: (body: unknown) => this.post(name, body),
      });
    }
    this.handlers = Object.freeze(handlers);
  }

  attach(port: EditorMessagePortWriter): void {
    if (this.port) {
      throw new Error("WeiBei editor host port is already attached");
    }
    this.port = port;
    port.start?.();
    for (const event of this.pending.splice(0)) {
      port.postMessage(event);
    }
  }

  close(): void {
    this.port?.close?.();
    this.port = null;
    this.pending.splice(0);
  }

  private post<Name extends EditorBridgeMessageName>(
    name: Name,
    body: unknown,
  ): void {
    const event = {
      kind: "event",
      transportVersion: editorHostTransportVersion,
      instanceId: this.instanceId,
      name,
      body: body as EditorBridgeEventBodies[Name],
    } as EditorBridgeEvent<Name>;
    if (this.port) {
      this.port.postMessage(event as EditorBridgeEvent);
      this.onEvent?.(name, body);
      return;
    }
    if (this.pending.length === DeferredEditorEventBridge.maximumQueuedEvents) {
      this.pending.shift();
    }
    this.pending.push(event as EditorBridgeEvent);
    this.onEvent?.(name, body);
  }
}
