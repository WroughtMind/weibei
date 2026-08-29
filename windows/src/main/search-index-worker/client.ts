import type {
  Fts5Capability,
  SearchCoverage,
  SearchCoverageUpdate,
  SearchHit,
  SearchIndexDiagnostics,
  SearchOptions,
  UpsertTextChunksInput,
} from "../services/search-index";
import {
  isSearchIndexRpcResponse,
  makeSearchIndexRpcRequest,
  type SearchIndexRpcMethod,
  type SearchIndexRpcParams,
  type SearchIndexRpcResult,
} from "../services/search-index-rpc";

const DEFAULT_STARTUP_TIMEOUT_MS = 10_000;
const DEFAULT_REQUEST_TIMEOUT_MS = 120_000;
const DEFAULT_CLOSE_TIMEOUT_MS = 5_000;

export interface SearchIndexUtilityProcess {
  postMessage(message: unknown): void;
  kill(): boolean;
  on(event: "message", listener: (message: unknown) => void): this;
  on(event: "exit", listener: (code: number) => void): this;
  off(event: "message", listener: (message: unknown) => void): this;
  off(event: "exit", listener: (code: number) => void): this;
}

export type SearchIndexUtilityProcessSpawner = () => SearchIndexUtilityProcess;

export interface SearchIndexClientOptions {
  dbPath: string;
  spawnWorker: SearchIndexUtilityProcessSpawner;
  startupTimeoutMs?: number;
  requestTimeoutMs?: number;
  closeTimeoutMs?: number;
}

interface PendingRequest {
  resolve(result: unknown): void;
  reject(error: Error): void;
  watchdog: ReturnType<typeof setTimeout>;
}

interface ChildState {
  process: SearchIndexUtilityProcess;
  ready: boolean;
  failed: boolean;
  pending: Map<number, PendingRequest>;
  onMessage(message: unknown): void;
  onExit(code: number): void;
}

/** Async main-process proxy. The synchronous SQLite implementation only runs in its worker. */
export class SearchIndexClient {
  private child: ChildState | null = null;
  private startPromise: Promise<ChildState> | null = null;
  private closePromise: Promise<void> | null = null;
  private nextRequestId = 1;
  private closed = false;

  private constructor(private readonly options: SearchIndexClientOptions) {}

  static async open(options: SearchIndexClientOptions): Promise<SearchIndexClient> {
    if (!options.dbPath || options.dbPath.includes("\0")) {
      throw new SearchIndexClientError("invalid-input", "dbPath must be a non-empty path");
    }
    validateTimeout(options.startupTimeoutMs);
    validateTimeout(options.requestTimeoutMs);
    validateTimeout(options.closeTimeoutMs);
    const client = new SearchIndexClient(options);
    await client.ensureChild();
    return client;
  }

  selfCheckFts5(): Promise<Fts5Capability> {
    return this.invoke("selfCheckFts5", null);
  }

  diagnostics(): Promise<SearchIndexDiagnostics> {
    return this.invoke("diagnostics", null);
  }

  upsertTextChunks(input: UpsertTextChunksInput): Promise<SearchCoverage> {
    return this.invoke("upsertTextChunks", { input });
  }

  updateCoverage(input: SearchCoverageUpdate): Promise<SearchCoverage> {
    return this.invoke("updateCoverage", { input });
  }

  coverage(itemId: string): Promise<SearchCoverage | null> {
    return this.invoke("coverage", { itemId });
  }

  search(query: string, options: SearchOptions = {}): Promise<SearchHit[]> {
    return this.invoke("search", { query, options });
  }

  deleteItem(itemId: string): Promise<boolean> {
    return this.invoke("deleteItem", { itemId });
  }

  rebuild(inputs: readonly UpsertTextChunksInput[] = []): Promise<SearchCoverage[]> {
    return this.invoke("rebuild", { inputs });
  }

  close(): Promise<void> {
    if (this.closePromise) return this.closePromise;
    this.closed = true;
    this.closePromise = this.shutdown();
    return this.closePromise;
  }

  private async invoke<M extends Exclude<SearchIndexRpcMethod, "open" | "close">>(
    method: M,
    params: SearchIndexRpcParams<M>,
  ): Promise<SearchIndexRpcResult<M>> {
    if (this.closed) throw new SearchIndexClientError("closed", "Search index client is closed");
    const child = await this.ensureChild();
    if (this.closed) throw new SearchIndexClientError("closed", "Search index client is closed");
    return this.request(
      child,
      method,
      params,
      this.options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS,
    );
  }

  private async ensureChild(): Promise<ChildState> {
    if (this.closed) throw new SearchIndexClientError("closed", "Search index client is closed");
    if (this.child?.ready && !this.child.failed) return this.child;
    if (this.startPromise) return this.startPromise;
    const startPromise = this.startChild();
    this.startPromise = startPromise;
    try {
      return await startPromise;
    } finally {
      if (this.startPromise === startPromise) this.startPromise = null;
    }
  }

  private async startChild(): Promise<ChildState> {
    let process: SearchIndexUtilityProcess;
    try {
      process = this.options.spawnWorker();
    } catch (error) {
      throw workerError(error, "worker-start-failed");
    }
    const child = {} as ChildState;
    child.process = process;
    child.ready = false;
    child.failed = false;
    child.pending = new Map();
    child.onMessage = (message) => this.handleMessage(child, message);
    child.onExit = (code) => this.failChild(
      child,
      new SearchIndexClientError("worker-crashed", `Search index worker exited with code ${code}`),
      false,
    );
    process.on("message", child.onMessage);
    process.on("exit", child.onExit);
    this.child = child;
    try {
      await this.request(
        child,
        "open",
        { dbPath: this.options.dbPath },
        this.options.startupTimeoutMs ?? DEFAULT_STARTUP_TIMEOUT_MS,
      );
      child.ready = true;
      return child;
    } catch (error) {
      if (!child.failed) this.failChild(child, workerError(error, "worker-start-failed"), true);
      throw error;
    }
  }

  private request<M extends SearchIndexRpcMethod>(
    child: ChildState,
    method: M,
    params: SearchIndexRpcParams<M>,
    timeoutMs: number,
  ): Promise<SearchIndexRpcResult<M>> {
    if (child.failed || this.child !== child) {
      return Promise.reject(new SearchIndexClientError("worker-crashed", "Search index worker is unavailable"));
    }
    const id = this.nextRequestId;
    this.nextRequestId += 1;
    return new Promise<SearchIndexRpcResult<M>>((resolve, reject) => {
      const watchdog = setTimeout(() => this.failChild(
        child,
        new SearchIndexClientError("timeout", `Search index ${method} request timed out`),
        true,
      ), timeoutMs);
      child.pending.set(id, {
        resolve: (result) => resolve(result as SearchIndexRpcResult<M>),
        reject,
        watchdog,
      });
      try {
        child.process.postMessage(makeSearchIndexRpcRequest(id, method, params));
      } catch (error) {
        this.failChild(child, workerError(error, "transport-error"), true);
      }
    });
  }

  private handleMessage(child: ChildState, message: unknown): void {
    if (child.failed || this.child !== child) return;
    if (!isSearchIndexRpcResponse(message)) {
      this.failChild(
        child,
        new SearchIndexClientError("invalid-response", "Search index worker returned an invalid response"),
        true,
      );
      return;
    }
    const pending = child.pending.get(message.id);
    if (!pending) return;
    child.pending.delete(message.id);
    clearTimeout(pending.watchdog);
    if (message.ok) pending.resolve(message.result);
    else pending.reject(new SearchIndexClientError(message.error.code, message.error.message));
  }

  private failChild(child: ChildState, error: SearchIndexClientError, kill: boolean): void {
    if (child.failed) return;
    child.failed = true;
    child.process.off("message", child.onMessage);
    child.process.off("exit", child.onExit);
    if (this.child === child) this.child = null;
    for (const pending of child.pending.values()) {
      clearTimeout(pending.watchdog);
      pending.reject(error);
    }
    child.pending.clear();
    if (kill) {
      try { child.process.kill(); } catch { /* The process may already be gone. */ }
    }
  }

  private async shutdown(): Promise<void> {
    if (this.startPromise) await this.startPromise.catch(() => undefined);
    const child = this.child;
    if (!child || child.failed) return;
    try {
      await this.request(
        child,
        "close",
        null,
        this.options.closeTimeoutMs ?? DEFAULT_CLOSE_TIMEOUT_MS,
      );
    } catch {
      // The cache is rebuildable. Always terminate a worker that cannot close in time.
    } finally {
      this.failChild(child, new SearchIndexClientError("closed", "Search index client is closed"), true);
    }
  }
}

export class SearchIndexClientError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "SearchIndexClientError";
  }
}

function validateTimeout(value: number | undefined): void {
  if (value !== undefined && (!Number.isSafeInteger(value) || value <= 0)) {
    throw new SearchIndexClientError("invalid-input", "Search index timeouts must be positive integers");
  }
}

function workerError(error: unknown, code: string): SearchIndexClientError {
  if (error instanceof SearchIndexClientError) return error;
  return new SearchIndexClientError(
    code,
    error instanceof Error && error.message ? error.message : code,
  );
}
