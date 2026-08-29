import { mkdir, open } from "node:fs/promises";
import path from "node:path";
import {
  AGENT_WORKER_PROTOCOL_VERSION,
  isAgentWorkerCommand,
  type AgentWorkerCommand,
  type AgentWorkerEvent,
  type AgentWorkerStartCommand,
} from "./protocol";
import { streamProviderAnswer } from "../services/provider-client";

export interface AgentWorkerPort {
  postMessage(event: AgentWorkerEvent): void;
  on(event: "message", listener: (event: { data: unknown }) => void): this;
}

export type ProviderStream = typeof streamProviderAnswer;

interface ActiveRequest {
  controller: AbortController;
  timeout: ReturnType<typeof setTimeout>;
}

export class AgentWorkerServer {
  private readonly active = new Map<string, ActiveRequest>();
  private shuttingDown = false;

  constructor(
    private readonly port: AgentWorkerPort,
    private readonly providerStream: ProviderStream = streamProviderAnswer,
  ) {}

  listen(): void {
    this.port.on("message", (event) => this.handle(event.data));
    this.send({ version: AGENT_WORKER_PROTOCOL_VERSION, type: "ready" });
  }

  private handle(value: unknown): void {
    if (!isAgentWorkerCommand(value)) return;
    if (value.type === "initialize") {
      this.send({ version: AGENT_WORKER_PROTOCOL_VERSION, type: "ready" });
      return;
    }
    if (value.type === "shutdown") {
      this.shuttingDown = true;
      for (const request of this.active.values()) request.controller.abort("shutdown");
      return;
    }
    if (value.type === "abort") {
      this.active.get(value.requestId)?.controller.abort("cancelled");
      return;
    }
    if (this.shuttingDown) {
      value.credential.fill(0);
      this.sendFailure(value.requestId, "agent-worker-shutting-down");
      return;
    }
    if (this.active.has(value.requestId)) {
      value.credential.fill(0);
      this.sendFailure(value.requestId, "agent-worker-duplicate-request");
      return;
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort("timeout"), value.timeoutMs);
    this.active.set(value.requestId, { controller, timeout });
    void this.run(value, controller).finally(() => {
      clearTimeout(timeout);
      this.active.delete(value.requestId);
    });
  }

  private async run(command: AgentWorkerStartCommand, controller: AbortController): Promise<void> {
    let apiKey = "";
    try {
      apiKey = new TextDecoder("utf-8", { fatal: true }).decode(command.credential);
      command.credential.fill(0);
      if (!apiKey) throw new Error("provider-credential-missing");
      await appendLedger(command.ledgerRoot, command.sessionId, {
        type: "turn/start",
        requestId: command.requestId,
        timeMS: Date.now(),
      });
      await appendLedger(command.ledgerRoot, command.sessionId, {
        type: "user/message",
        requestId: command.requestId,
        text: command.question,
        timeMS: Date.now(),
      });
      const text = await this.providerStream({
        provider: command.provider,
        apiKey,
        question: command.question,
        context: command.context,
        signal: controller.signal,
        onDelta: (delta) => this.send({
          version: AGENT_WORKER_PROTOCOL_VERSION,
          type: "delta",
          requestId: command.requestId,
          delta,
        }),
      });
      await appendLedger(command.ledgerRoot, command.sessionId, {
        type: "assistant/message",
        requestId: command.requestId,
        text,
        timeMS: Date.now(),
      });
      await appendLedger(command.ledgerRoot, command.sessionId, {
        type: "turn/end",
        requestId: command.requestId,
        finishReason: "stop",
        timeMS: Date.now(),
      });
      this.send({
        version: AGENT_WORKER_PROTOCOL_VERSION,
        type: "completed",
        requestId: command.requestId,
        text,
      });
    } catch (error) {
      const abortReason = controller.signal.aborted ? controller.signal.reason : null;
      const cancelled = abortReason === "cancelled" || abortReason === "shutdown";
      const failureKind = abortReason === "timeout"
        ? "provider-timeout"
        : sanitizeFailure(error, apiKey);
      await appendLedger(command.ledgerRoot, command.sessionId, {
        type: "turn/end",
        requestId: command.requestId,
        finishReason: cancelled ? "cancelled" : "error",
        isError: true,
        failureKind: cancelled ? undefined : failureKind,
        timeMS: Date.now(),
      }).catch(() => undefined);
      if (cancelled) {
        this.send({ version: AGENT_WORKER_PROTOCOL_VERSION, type: "cancelled", requestId: command.requestId });
      } else {
        this.sendFailure(command.requestId, failureKind);
      }
    } finally {
      // Strings cannot be overwritten in JavaScript, but dropping the final strong
      // reference here bounds plaintext lifetime to this worker request.
      apiKey = "";
      command.credential.fill(0);
    }
  }

  private sendFailure(requestId: string, failureKind: string): void {
    this.send({
      version: AGENT_WORKER_PROTOCOL_VERSION,
      type: "failed",
      requestId,
      failureKind: failureKind.slice(0, 512) || "provider",
    });
  }

  private send(event: AgentWorkerEvent): void {
    this.port.postMessage(event);
  }
}

async function appendLedger(ledgerRoot: string, sessionId: string, event: Record<string, unknown>): Promise<void> {
  const directory = path.join(ledgerRoot, sessionId.toLocaleLowerCase("en-US"));
  await mkdir(directory, { recursive: true });
  const handle = await open(path.join(directory, "ledger.jsonl"), "a", 0o600);
  try {
    await handle.write(`${JSON.stringify(event)}\n`);
    await handle.sync();
  } finally {
    await handle.close();
  }
}

function sanitizeFailure(error: unknown, apiKey: string): string {
  let message = error instanceof Error && error.message ? error.message : "provider";
  if (apiKey) message = message.split(apiKey).join("[redacted]");
  return message.replace(/[\r\n\0]/gu, " ").slice(0, 512) || "provider";
}
