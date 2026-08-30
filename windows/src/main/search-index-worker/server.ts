import {
  SearchIndex,
  SearchIndexError,
  type SearchIndexErrorCode,
} from "../services/search-index";
import {
  isSearchIndexRpcRequest,
  SEARCH_INDEX_RPC_PROTOCOL,
  SEARCH_INDEX_RPC_VERSION,
  type SearchIndexRpcFailure,
  type SearchIndexRpcRequest,
  type SearchIndexRpcSuccess,
} from "../services/search-index-rpc";

export interface SearchIndexWorkerPort {
  postMessage(message: SearchIndexRpcSuccess | SearchIndexRpcFailure): void;
  on(event: "message", listener: (event: { data: unknown }) => void): this;
}

export class SearchIndexWorkerServer {
  private index: SearchIndex | null = null;
  private queue: Promise<void> = Promise.resolve();
  private closed = false;

  constructor(private readonly port: SearchIndexWorkerPort) {}

  listen(): void {
    this.port.on("message", (event) => {
      this.queue = this.queue.then(
        () => this.handle(event.data),
        () => this.handle(event.data),
      );
    });
  }

  private async handle(value: unknown): Promise<void> {
    if (!isSearchIndexRpcRequest(value)) {
      const id = requestId(value);
      if (id !== null) this.sendFailure(id, "invalid-request", "Invalid search index RPC request");
      return;
    }
    try {
      const result = this.dispatch(value);
      this.port.postMessage({
        protocol: SEARCH_INDEX_RPC_PROTOCOL,
        version: SEARCH_INDEX_RPC_VERSION,
        id: value.id,
        ok: true,
        result,
      });
    } catch (error) {
      const serialized = serializeError(error);
      this.sendFailure(value.id, serialized.code, serialized.message);
    }
  }

  private dispatch(request: SearchIndexRpcRequest): unknown {
    if (request.method === "open") {
      if (this.closed || this.index) throw new WorkerStateError("already-open", "Search index worker is already open");
      this.index = SearchIndex.open({ dbPath: request.params.dbPath });
      return this.index.diagnostics();
    }
    if (request.method === "close") {
      if (!this.closed) this.index?.close();
      this.index = null;
      this.closed = true;
      return null;
    }
    const index = this.requireIndex();
    switch (request.method) {
      case "selfCheckFts5":
        return index.selfCheckFts5();
      case "diagnostics":
        return index.diagnostics();
      case "upsertTextChunks":
        return index.upsertTextChunks(request.params.input);
      case "updateCoverage":
        return index.updateCoverage(request.params.input);
      case "coverage":
        return index.coverage(request.params.itemId);
      case "search":
        return index.search(request.params.query, request.params.options);
      case "deleteItem":
        return index.deleteItem(request.params.itemId);
      case "rebuild":
        return index.rebuild(request.params.inputs);
    }
  }

  private requireIndex(): SearchIndex {
    if (this.closed) throw new WorkerStateError("closed", "Search index worker is closed");
    if (!this.index) throw new WorkerStateError("not-open", "Search index worker is not open");
    return this.index;
  }

  private sendFailure(id: number, code: string, message: string): void {
    this.port.postMessage({
      protocol: SEARCH_INDEX_RPC_PROTOCOL,
      version: SEARCH_INDEX_RPC_VERSION,
      id,
      ok: false,
      error: {
        code: sanitize(code, 128) || "internal",
        message: sanitize(message, 2_048) || "Search index worker operation failed",
      },
    });
  }
}

class WorkerStateError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "WorkerStateError";
  }
}

function serializeError(error: unknown): { code: SearchIndexErrorCode | string; message: string } {
  if (error instanceof SearchIndexError || error instanceof WorkerStateError) {
    return { code: error.code, message: error.message };
  }
  return { code: "internal", message: "Search index worker operation failed" };
}

function requestId(value: unknown): number | null {
  if (!isRecord(value) || !Number.isSafeInteger(value.id) || (value.id as number) <= 0) return null;
  return value.id as number;
}

function sanitize(value: string, maximumLength: number): string {
  return value.replace(/[\r\n\0]/gu, " ").slice(0, maximumLength);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
