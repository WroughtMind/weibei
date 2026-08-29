import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import {
  AgentWorkerCancelledError,
  AgentWorkerClient,
  type AgentUtilityProcess,
} from "../src/main/agent-worker/client";
import { formatAgentContext } from "../src/main/agent-worker/context";
import {
  AGENT_WORKER_PROTOCOL_VERSION,
  isAgentWorkerCommand,
  isAgentWorkerEvent,
  type AgentWorkerCommand,
  type AgentWorkerEvent,
  type AgentWorkerStartCommand,
} from "../src/main/agent-worker/protocol";
import { AgentWorkerServer, type AgentWorkerPort, type ProviderStream } from "../src/main/agent-worker/server";
import { AgentRuntime } from "../src/main/services/agent-runtime";
import type { CredentialVault } from "../src/main/services/credential-vault";
import type { StudySessionStore } from "../src/main/services/session-store";

const requestID = "11111111-1111-4111-8111-111111111111";
const secondRequestID = "22222222-2222-4222-8222-222222222222";
const sessionID = "33333333-3333-4333-8333-333333333333";
const courseID = "44444444-4444-4444-8444-444444444444";
const provider = {
  providerId: "openai",
  model: "gpt-test",
  baseUrl: "https://example.invalid/v1",
  hasCredential: true,
};

class FakeUtilityProcess extends EventEmitter implements AgentUtilityProcess {
  readonly commands: AgentWorkerCommand[] = [];
  killed = false;
  readonly pid = 1234;

  postMessage(message: AgentWorkerCommand): void {
    this.commands.push(structuredClone(message));
  }

  kill(): boolean {
    this.killed = true;
    return true;
  }

  send(event: AgentWorkerEvent): void {
    this.emit("message", event);
  }

  exit(code: number): void {
    this.emit("exit", code);
  }
}

class FakeWorkerPort extends EventEmitter implements AgentWorkerPort {
  readonly events: AgentWorkerEvent[] = [];

  postMessage(event: AgentWorkerEvent): void {
    this.events.push(structuredClone(event));
    this.emit("worker-event", event);
  }

  command(command: AgentWorkerCommand): void {
    this.emit("message", { data: command });
  }
}

test("agent worker protocol rejects malformed capabilities", () => {
  assert.equal(isAgentWorkerCommand({ version: 1, type: "abort", requestId: "../escape" }), false);
  assert.equal(isAgentWorkerCommand(startCommand({ credential: new Uint8Array(), timeoutMs: 120_000 })), false);
  assert.equal(isAgentWorkerCommand(startCommand({ credential: new Uint8Array([1]), timeoutMs: 999 })), false);
  assert.equal(isAgentWorkerCommand(startCommand()), true);
  assert.equal(isAgentWorkerEvent({ version: 1, type: "failed", requestId: requestID, failureKind: "provider-timeout" }), true);
  assert.equal(isAgentWorkerEvent({ version: 1, type: "delta", requestId: "bad", delta: "x" }), false);
});

test("client streams typed events and erases the handed-off credential buffer", async () => {
  const child = new FakeUtilityProcess();
  const client = new AgentWorkerClient(() => child, { readyTimeoutMs: 100 });
  const credential = new TextEncoder().encode("sk-short-lived");
  const deltas: string[] = [];
  const result = client.stream(streamRequest({ credential, onDelta: (delta) => deltas.push(delta) }));
  child.send({ version: 1, type: "ready" });
  await nextTurn();
  assert.deepEqual([...credential], new Array(credential.length).fill(0));
  const start = child.commands.find((command): command is AgentWorkerStartCommand => command.type === "start");
  assert.ok(start);
  assert.equal(new TextDecoder().decode(start.credential), "sk-short-lived");
  child.send({ version: 1, type: "delta", requestId: requestID, delta: "甲" });
  child.send({ version: 1, type: "delta", requestId: requestID, delta: "乙" });
  child.send({ version: 1, type: "completed", requestId: requestID, text: "甲乙" });
  assert.equal(await result, "甲乙");
  assert.deepEqual(deltas, ["甲", "乙"]);
  await client.dispose();
});

test("client propagates abort and worker cancellation", async () => {
  const child = new FakeUtilityProcess();
  const client = new AgentWorkerClient(() => child, { readyTimeoutMs: 100 });
  const controller = new AbortController();
  const result = client.stream(streamRequest({ signal: controller.signal }));
  child.send({ version: 1, type: "ready" });
  await nextTurn();
  controller.abort("cancelled");
  assert.ok(child.commands.some((command) => command.type === "abort" && command.requestId === requestID));
  child.send({ version: 1, type: "cancelled", requestId: requestID });
  await assert.rejects(result, AgentWorkerCancelledError);
  await client.dispose();
});

test("client fails a crashed turn and lazily restarts for the next turn", async () => {
  const children = [new FakeUtilityProcess(), new FakeUtilityProcess()];
  let spawnCount = 0;
  const client = new AgentWorkerClient(() => children[spawnCount++], { readyTimeoutMs: 100 });
  const first = client.stream(streamRequest());
  children[0].send({ version: 1, type: "ready" });
  await nextTurn();
  children[0].exit(37);
  await assert.rejects(first, /agent-worker-exited-37/u);

  const second = client.stream(streamRequest({ requestId: secondRequestID }));
  children[1].send({ version: 1, type: "ready" });
  await nextTurn();
  children[1].send({ version: 1, type: "completed", requestId: secondRequestID, text: "restarted" });
  assert.equal(await second, "restarted");
  assert.equal(spawnCount, 2);
  await client.dispose();
});

test("client watchdog terminates an unresponsive process", async () => {
  const child = new FakeUtilityProcess();
  const client = new AgentWorkerClient(() => child, { readyTimeoutMs: 100, responseGraceMs: -999 });
  const result = client.stream(streamRequest({ timeoutMs: 1_000 }));
  child.send({ version: 1, type: "ready" });
  await assert.rejects(result, /agent-worker-unresponsive/u);
  assert.equal(child.killed, true);
  await client.dispose();
});

test("worker owns streaming and durable ledger writes", async (t) => {
  const root = await mkdtemp(path.join(tmpdir(), "weibei-agent-worker-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const port = new FakeWorkerPort();
  const seenKeys: string[] = [];
  const stream: ProviderStream = async (options) => {
    seenKeys.push(options.apiKey);
    options.onDelta("碑");
    return "碑帖";
  };
  new AgentWorkerServer(port, stream).listen();
  const command = startCommand({ ledgerRoot: root, credential: new TextEncoder().encode("worker-only") });
  const completed = waitForWorkerEvent(port, "completed");
  port.command(command);
  const event = await completed;
  assert.equal(event.type === "completed" ? event.text : null, "碑帖");
  assert.deepEqual(seenKeys, ["worker-only"]);
  assert.deepEqual([...command.credential], new Array(command.credential.length).fill(0));
  assert.ok(port.events.some((candidate) => candidate.type === "delta" && candidate.delta === "碑"));
  const ledger = await readFile(path.join(root, sessionID, "ledger.jsonl"), "utf8");
  const lines = ledger.trim().split("\n").map((line) => JSON.parse(line) as Record<string, unknown>);
  assert.deepEqual(lines.map((line) => line.type), ["turn/start", "user/message", "assistant/message", "turn/end"]);
});

test("worker enforces provider timeout and records a truthful terminal event", async (t) => {
  const root = await mkdtemp(path.join(tmpdir(), "weibei-agent-timeout-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const port = new FakeWorkerPort();
  const stream: ProviderStream = async (options) => new Promise((_resolve, reject) => {
    options.signal.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
  });
  new AgentWorkerServer(port, stream).listen();
  const failed = waitForWorkerEvent(port, "failed", 2_000);
  port.command(startCommand({ ledgerRoot: root, timeoutMs: 1_000 }));
  const event = await failed;
  assert.equal(event.type === "failed" ? event.failureKind : null, "provider-timeout");
  const ledger = await readFile(path.join(root, sessionID, "ledger.jsonl"), "utf8");
  const terminal = JSON.parse(ledger.trim().split("\n").at(-1) ?? "{}") as Record<string, unknown>;
  assert.equal(terminal.type, "turn/end");
  assert.equal(terminal.finishReason, "error");
  assert.equal(terminal.failureKind, "provider-timeout");
});

test("runtime window disposal aborts its turn and kills the utility process", async () => {
  const child = new FakeUtilityProcess();
  const updated: Array<{ completionState: string; failureKind: string | null; sources: Array<{ itemId: string | null }> }> = [];
  const sessions = {
    async appendMessages() { return undefined; },
    async updateMessage(_sessionId: string, message: { completionState: string; failureKind: string | null; sources: Array<{ itemId: string | null }> }) {
      updated.push(message);
      return undefined;
    },
  } as unknown as StudySessionStore;
  const vault = {
    async hasSecret() { return true; },
    async getSecret() { return "runtime-secret"; },
  } as unknown as CredentialVault;
  const runtime = new AgentRuntime({
    sessions,
    vault,
    provider: () => provider,
    ledgerRoot: "C:\\WeiBei\\Ledgers",
    spawnWorker: () => child,
  });
  const events: string[] = [];
  runtime.onEvent((event) => events.push(event.type));
  await runtime.start(
    { courseId: courseID, sessionId: sessionID, question: "问题", selection: null },
    "课程上下文",
    [{
      id: "55555555-5555-4555-8555-555555555555",
      itemId: "material:item",
      courseId: courseID,
      kind: "material",
      title: "课程文稿",
      label: "1",
      excerpt: "真实命中",
      pageIndex: null,
      sectionTitle: null,
      sectionLocationId: null,
    }],
  );
  child.send({ version: 1, type: "ready" });
  await nextTurn();
  await runtime.dispose();
  assert.equal(child.killed, true);
  assert.ok(child.commands.some((command) => command.type === "abort"));
  assert.ok(child.commands.some((command) => command.type === "shutdown"));
  assert.equal(updated.length, 1);
  assert.equal(updated[0]?.completionState, "interrupted");
  assert.equal(updated[0]?.failureKind, "cancelled");
  assert.equal(updated[0]?.sources[0]?.itemId, "material:item");
  assert.deepEqual(events, ["started", "cancelled"]);
});

test("course context is bounded and explicit when retrieval has no evidence", () => {
  const empty = formatAgentContext({ selection: null, hits: [] });
  assert.match(empty, /没有返回可验证/u);
  const bounded = formatAgentContext({
    selection: "选区",
    hits: [{ itemId: "item", title: "文稿", kind: "text", excerpt: "甲".repeat(4_000), rank: -1 }],
    maximumCharacters: 1_200,
  });
  assert.ok(bounded.length <= 1_200);
  assert.match(bounded, /课程资料 1/u);
  assert.match(bounded, /已截断/u);
});

function startCommand(overrides: Partial<AgentWorkerStartCommand> = {}): AgentWorkerStartCommand {
  return {
    version: AGENT_WORKER_PROTOCOL_VERSION,
    type: "start",
    requestId: requestID,
    sessionId: sessionID,
    provider,
    credential: new TextEncoder().encode("secret"),
    question: "解释课程",
    context: "课程片段",
    ledgerRoot: "C:\\WeiBei\\Ledgers",
    timeoutMs: 120_000,
    ...overrides,
  };
}

function streamRequest(overrides: Partial<Parameters<AgentWorkerClient["stream"]>[0]> = {}): Parameters<AgentWorkerClient["stream"]>[0] {
  return {
    requestId: requestID,
    sessionId: sessionID,
    provider,
    credential: new TextEncoder().encode("secret"),
    question: "解释课程",
    context: "课程片段",
    ledgerRoot: "C:\\WeiBei\\Ledgers",
    timeoutMs: 120_000,
    signal: new AbortController().signal,
    onDelta: () => undefined,
    ...overrides,
  };
}

function waitForWorkerEvent<T extends AgentWorkerEvent["type"]>(
  port: FakeWorkerPort,
  type: T,
  timeoutMs = 1_000,
): Promise<Extract<AgentWorkerEvent, { type: T }>> {
  const existing = port.events.find((event): event is Extract<AgentWorkerEvent, { type: T }> => event.type === type);
  if (existing) return Promise.resolve(existing);
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      port.off("worker-event", listener);
      reject(new Error(`worker event timed out: ${type}`));
    }, timeoutMs);
    const listener = (event: AgentWorkerEvent) => {
      if (event.type !== type) return;
      clearTimeout(timeout);
      port.off("worker-event", listener);
      resolve(event as Extract<AgentWorkerEvent, { type: T }>);
    };
    port.on("worker-event", listener);
  });
}

function nextTurn(): Promise<void> {
  return new Promise((resolve) => setImmediate(resolve));
}
