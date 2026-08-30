import {
  AGENT_WORKER_PROTOCOL_VERSION,
  DEFAULT_AGENT_TIMEOUT_MS,
  isAgentWorkerEvent,
  type AgentWorkerHistoryMessage,
  type AgentWorkerCommand,
  type AgentWorkerEvent,
} from "./protocol";
import type { ProviderPublicConfig } from "../../shared/contracts";

export interface AgentUtilityProcess {
  readonly pid?: number;
  postMessage(message: AgentWorkerCommand): void;
  kill(): boolean;
  on(event: "message", listener: (message: unknown) => void): this;
  on(event: "exit", listener: (code: number) => void): this;
  off(event: "message", listener: (message: unknown) => void): this;
  off(event: "exit", listener: (code: number) => void): this;
}

export type AgentUtilityProcessSpawner = () => AgentUtilityProcess;

export interface AgentWorkerStreamRequest {
  requestId: string;
  sessionId: string;
  provider: ProviderPublicConfig;
  credential: Uint8Array;
  history?: readonly AgentWorkerHistoryMessage[];
  question: string;
  context?: string;
  ledgerRoot: string;
  timeoutMs?: number;
  signal: AbortSignal;
  onDelta(delta: string): void;
}

interface PendingRequest {
  resolve(text: string): void;
  reject(error: Error): void;
  onDelta(delta: string): void;
  watchdog: ReturnType<typeof setTimeout>;
  removeAbortListener(): void;
}

interface ChildState {
  process: AgentUtilityProcess;
  ready: boolean;
  readyPromise: Promise<void>;
  resolveReady(): void;
  rejectReady(error: Error): void;
  readyWatchdog: ReturnType<typeof setTimeout>;
  onMessage(message: unknown): void;
  onExit(code: number): void;
}

export class AgentWorkerClient {
  private child: ChildState | null = null;
  private readonly pending = new Map<string, PendingRequest>();
  private readonly claimedRequestIds = new Set<string>();
  private disposed = false;

  constructor(
    private readonly spawn: AgentUtilityProcessSpawner,
    private readonly options: { readyTimeoutMs?: number; responseGraceMs?: number } = {},
  ) {}

  async stream(request: AgentWorkerStreamRequest): Promise<string> {
    if (this.disposed) throw new AgentWorkerError("agent-worker-disposed");
    if (this.claimedRequestIds.has(request.requestId)) throw new AgentWorkerError("agent-worker-duplicate-request");
    this.claimedRequestIds.add(request.requestId);
    if (request.signal.aborted) {
      this.claimedRequestIds.delete(request.requestId);
      request.credential.fill(0);
      throw new AgentWorkerCancelledError();
    }
    const timeoutMs = request.timeoutMs ?? DEFAULT_AGENT_TIMEOUT_MS;
    let child: ChildState;
    try {
      child = await this.ensureChild(request.signal);
    } catch (error) {
      this.claimedRequestIds.delete(request.requestId);
      request.credential.fill(0);
      throw error;
    }
    if (request.signal.aborted) {
      this.claimedRequestIds.delete(request.requestId);
      request.credential.fill(0);
      throw new AgentWorkerCancelledError();
    }
    return new Promise<string>((resolve, reject) => {
      const watchdog = setTimeout(() => {
        if (!this.pending.has(request.requestId)) return;
        this.failChild(child, new AgentWorkerError("agent-worker-unresponsive"));
        child.process.kill();
      }, timeoutMs + (this.options.responseGraceMs ?? 5_000));
      const onAbort = () => this.cancel(request.requestId);
      request.signal.addEventListener("abort", onAbort, { once: true });
      this.pending.set(request.requestId, {
        resolve,
        reject,
        onDelta: request.onDelta,
        watchdog,
        removeAbortListener: () => request.signal.removeEventListener("abort", onAbort),
      });
      try {
        child.process.postMessage({
          version: AGENT_WORKER_PROTOCOL_VERSION,
          type: "start",
          requestId: request.requestId,
          sessionId: request.sessionId,
          provider: request.provider,
          credential: request.credential,
          history: request.history ? request.history.map((message) => ({ ...message })) : [],
          question: request.question,
          context: request.context ?? "",
          ledgerRoot: request.ledgerRoot,
          timeoutMs,
        });
      } catch (error) {
        this.takePending(request.requestId)?.reject(asWorkerError(error, "agent-worker-send-failed"));
        this.failChild(child, asWorkerError(error, "agent-worker-send-failed"));
      } finally {
        // postMessage synchronously structured-clones this array. Keep no reusable
        // main-process credential buffer after the one request hand-off.
        request.credential.fill(0);
      }
    });
  }

  cancel(requestId: string): void {
    if (!this.pending.has(requestId)) return;
    try {
      this.child?.process.postMessage({ version: AGENT_WORKER_PROTOCOL_VERSION, type: "abort", requestId });
    } catch (error) {
      if (this.child) this.failChild(this.child, asWorkerError(error, "agent-worker-send-failed"));
    }
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    const child = this.child;
    if (!child) {
      this.rejectAll(new AgentWorkerError("agent-worker-disposed"));
      return;
    }
    try {
      child.process.postMessage({ version: AGENT_WORKER_PROTOCOL_VERSION, type: "shutdown" });
    } catch {
      // A crashed process is handled identically below.
    }
    child.process.kill();
    this.detachChild(child);
    this.child = null;
    if (!child.ready) child.rejectReady(new AgentWorkerError("agent-worker-disposed"));
    this.rejectAll(new AgentWorkerError("agent-worker-disposed"));
  }

  private async ensureChild(signal?: AbortSignal): Promise<ChildState> {
    if (this.disposed) throw new AgentWorkerError("agent-worker-disposed");
    if (!this.child) {
      const child = this.createChild();
      this.child = child;
      try {
        child.process.postMessage({ version: AGENT_WORKER_PROTOCOL_VERSION, type: "initialize" });
      } catch (error) {
        const workerError = asWorkerError(error, "agent-worker-start-failed");
        this.failChild(child, workerError);
        throw workerError;
      }
    }
    const child = this.child;
    await waitForReady(child.readyPromise, signal);
    if (this.child !== child || !child.ready) throw new AgentWorkerError("agent-worker-start-failed");
    return child;
  }

  private createChild(): ChildState {
    const process = this.spawn();
    let resolveReady!: () => void;
    let rejectReady!: (error: Error) => void;
    const readyPromise = new Promise<void>((resolve, reject) => {
      resolveReady = resolve;
      rejectReady = reject;
    });
    // Avoid a Node unhandled-rejection report when the process exits before the
    // first stream call has reached its await boundary.
    void readyPromise.catch(() => undefined);
    const child = {} as ChildState;
    child.process = process;
    child.ready = false;
    child.readyPromise = readyPromise;
    child.resolveReady = resolveReady;
    child.rejectReady = rejectReady;
    child.onMessage = (message) => this.handleMessage(child, message);
    child.onExit = (code) => this.failChild(child, new AgentWorkerError(`agent-worker-exited-${code}`));
    child.readyWatchdog = setTimeout(() => {
      this.failChild(child, new AgentWorkerError("agent-worker-ready-timeout"));
    }, this.options.readyTimeoutMs ?? 10_000);
    process.on("message", child.onMessage);
    process.on("exit", child.onExit);
    return child;
  }

  private handleMessage(child: ChildState, message: unknown): void {
    if (this.child !== child || !isAgentWorkerEvent(message)) return;
    if (message.type === "ready") {
      if (!child.ready) {
        child.ready = true;
        clearTimeout(child.readyWatchdog);
        child.resolveReady();
      }
      return;
    }
    const pending = this.pending.get(message.requestId);
    if (!pending) return;
    if (message.type === "delta") {
      pending.onDelta(message.delta);
      return;
    }
    this.takePending(message.requestId);
    if (message.type === "completed") pending.resolve(message.text);
    else if (message.type === "cancelled") pending.reject(new AgentWorkerCancelledError());
    else pending.reject(new AgentWorkerError(message.failureKind));
  }

  private failChild(child: ChildState, error: Error): void {
    if (this.child !== child) return;
    this.detachChild(child);
    this.child = null;
    if (!child.ready) child.rejectReady(error);
    this.rejectAll(error);
    child.process.kill();
  }

  private detachChild(child: ChildState): void {
    clearTimeout(child.readyWatchdog);
    child.process.off("message", child.onMessage);
    child.process.off("exit", child.onExit);
  }

  private takePending(requestId: string): PendingRequest | undefined {
    const pending = this.pending.get(requestId);
    if (!pending) return undefined;
    this.pending.delete(requestId);
    this.claimedRequestIds.delete(requestId);
    clearTimeout(pending.watchdog);
    pending.removeAbortListener();
    return pending;
  }

  private rejectAll(error: Error): void {
    for (const [requestId, pending] of this.pending) {
      this.takePending(requestId);
      pending.reject(error);
    }
  }
}

export class AgentWorkerError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "AgentWorkerError";
  }
}

export class AgentWorkerCancelledError extends AgentWorkerError {
  constructor() {
    super("cancelled");
    this.name = "AgentWorkerCancelledError";
  }
}

function asWorkerError(error: unknown, fallback: string): AgentWorkerError {
  if (error instanceof AgentWorkerError) return error;
  return new AgentWorkerError(error instanceof Error && error.message ? `${fallback}: ${error.message}` : fallback);
}

async function waitForReady(ready: Promise<void>, signal?: AbortSignal): Promise<void> {
  if (!signal) return ready;
  if (signal.aborted) throw new AgentWorkerCancelledError();
  let rejectAbort!: (error: Error) => void;
  const aborted = new Promise<never>((_resolve, reject) => { rejectAbort = reject; });
  const onAbort = () => rejectAbort(new AgentWorkerCancelledError());
  signal.addEventListener("abort", onAbort, { once: true });
  try {
    await Promise.race([ready, aborted]);
  } finally {
    signal.removeEventListener("abort", onAbort);
  }
}
