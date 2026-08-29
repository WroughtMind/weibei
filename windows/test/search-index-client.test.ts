import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";
import {
  SearchIndexClient,
  SearchIndexClientError,
  type SearchIndexUtilityProcess,
} from "../src/main/search-index-worker/client";
import {
  isSearchIndexRpcRequest,
  SEARCH_INDEX_RPC_PROTOCOL,
  SEARCH_INDEX_RPC_VERSION,
  type SearchIndexRpcRequest,
} from "../src/main/services/search-index-rpc";

class FakeWorker extends EventEmitter implements SearchIndexUtilityProcess {
  readonly requests: SearchIndexRpcRequest[] = [];
  killed = false;

  constructor(private readonly handle: (request: SearchIndexRpcRequest, worker: FakeWorker) => void) {
    super();
  }

  postMessage(message: unknown): void {
    assert.ok(isSearchIndexRpcRequest(message));
    this.requests.push(message);
    this.handle(message, this);
  }

  kill(): boolean {
    this.killed = true;
    return true;
  }

  succeed(request: SearchIndexRpcRequest, result: unknown): void {
    queueMicrotask(() => this.emit("message", {
      protocol: SEARCH_INDEX_RPC_PROTOCOL,
      version: SEARCH_INDEX_RPC_VERSION,
      id: request.id,
      ok: true,
      result,
    }));
  }

  crash(code = 1): void {
    this.emit("exit", code);
  }
}

test("proxies search index calls through the typed worker protocol", async () => {
  const worker = new FakeWorker((request, process) => {
    if (request.method === "open") process.succeed(request, { schema: "v3" });
    if (request.method === "coverage") process.succeed(request, null);
    if (request.method === "search") process.succeed(request, [{
      itemId: "item-a",
      sortOrder: 0,
      location: "正文",
      excerpt: "流动性偏好",
      rank: -1,
    }]);
    if (request.method === "close") process.succeed(request, null);
  });
  const client = await SearchIndexClient.open({
    dbPath: "C:\\WeiBei\\course-search-v3.sqlite3",
    spawnWorker: () => worker,
  });

  assert.equal(await client.coverage("item-a"), null);
  assert.equal((await client.search("流动性"))[0]?.itemId, "item-a");
  await client.close();
  assert.deepEqual(worker.requests.map((request) => request.method), [
    "open",
    "coverage",
    "search",
    "close",
  ]);
});

test("rejects a crashed call and opens a fresh worker on the next call", async () => {
  const workers = [
    new FakeWorker((request, process) => {
      if (request.method === "open") process.succeed(request, { schema: "v3" });
    }),
    new FakeWorker((request, process) => {
      if (request.method === "open") process.succeed(request, { schema: "v3" });
      if (request.method === "coverage") process.succeed(request, null);
      if (request.method === "close") process.succeed(request, null);
    }),
  ];
  let spawnCount = 0;
  const client = await SearchIndexClient.open({
    dbPath: "C:\\WeiBei\\course-search-v3.sqlite3",
    spawnWorker: () => workers[spawnCount++],
  });

  const pending = client.coverage("item-a");
  await new Promise<void>((resolve) => setImmediate(resolve));
  workers[0].crash(9);
  await assert.rejects(pending, hasCode("worker-crashed"));
  assert.equal(await client.coverage("item-a"), null);
  assert.equal(spawnCount, 2);
  await client.close();
});

test("times out and terminates an unresponsive worker", async () => {
  const worker = new FakeWorker((request, process) => {
    if (request.method === "open") process.succeed(request, { schema: "v3" });
  });
  const client = await SearchIndexClient.open({
    dbPath: "C:\\WeiBei\\course-search-v3.sqlite3",
    spawnWorker: () => worker,
    requestTimeoutMs: 20,
  });

  await assert.rejects(client.coverage("item-a"), hasCode("timeout"));
  assert.equal(worker.killed, true);
  await client.close();
});

test("close is idempotent, closes the database before terminating, and rejects later calls", async () => {
  const worker = new FakeWorker((request, process) => {
    if (request.method === "open") process.succeed(request, { schema: "v3" });
    if (request.method === "close") process.succeed(request, null);
  });
  const client = await SearchIndexClient.open({
    dbPath: "C:\\WeiBei\\course-search-v3.sqlite3",
    spawnWorker: () => worker,
  });

  const firstClose = client.close();
  assert.equal(client.close(), firstClose);
  await firstClose;
  assert.equal(worker.killed, true);
  assert.deepEqual(worker.requests.map((request) => request.method), ["open", "close"]);
  await assert.rejects(client.search("test"), hasCode("closed"));
});

function hasCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof SearchIndexClientError && error.code === code;
}
