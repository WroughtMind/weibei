import { randomUUID } from "node:crypto";
import type { AgentEvent, AgentMessage, AgentStartRequest, Citation, ProviderPublicConfig } from "../../shared/contracts";
import {
  AgentWorkerClient,
  type AgentUtilityProcessSpawner,
} from "../agent-worker/client";
import type { CredentialVault } from "./credential-vault";
import { providerCredentialID } from "./provider-client";
import type { StudySessionStore } from "./session-store";

interface ActiveTurn {
  controller: AbortController;
  sessionID: string;
  assistantID: string;
  text: string;
}

export class AgentRuntime {
  private readonly turns = new Map<string, ActiveTurn>();
  private readonly listeners = new Set<(event: AgentEvent) => void>();
  private readonly running = new Set<Promise<void>>();
  private readonly worker: AgentWorkerClient;
  private disposed = false;

  constructor(
    private readonly options: {
      sessions: StudySessionStore;
      vault: CredentialVault;
      provider: () => ProviderPublicConfig;
      ledgerRoot: string;
      spawnWorker: AgentUtilityProcessSpawner;
      requestTimeoutMs?: number;
    },
  ) {
    this.worker = new AgentWorkerClient(options.spawnWorker);
  }

  onEvent(listener: (event: AgentEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async start(request: AgentStartRequest, context = "", sources: readonly Citation[] = []): Promise<{ requestId: string }> {
    if (this.disposed) throw new Error("agent-runtime-disposed");
    if ([...this.turns.values()].some((turn) => turn.sessionID === request.sessionId)) throw new Error("session-already-generating");
    const provider = this.options.provider();
    const credentialID = providerCredentialID(provider.providerId, provider.baseUrl);
    if (!await this.options.vault.hasSecret(credentialID)) throw new Error("provider-credential-missing");
    const requestId = randomUUID();
    const now = new Date().toISOString();
    const userMessage: AgentMessage = {
      id: randomUUID(), role: "user", text: request.question, completionState: "completed",
      sources: [], actions: [], failureKind: null, retryQuestion: null, createdAt: now,
    };
    const assistantMessage: AgentMessage = {
      id: randomUUID(), role: "assistant", text: "", completionState: "generating",
      sources: [...sources], actions: [], failureKind: null, retryQuestion: request.question, createdAt: now,
    };
    await this.options.sessions.appendMessages(request.sessionId, [userMessage, assistantMessage]);
    let secret = await this.options.vault.getSecret(credentialID);
    if (!secret) {
      await this.options.sessions.updateMessage(request.sessionId, {
        ...assistantMessage,
        completionState: "interrupted",
        failureKind: "provider-credential-missing",
      }).catch(() => undefined);
      throw new Error("provider-credential-missing");
    }
    const credential = new TextEncoder().encode(secret);
    // Never retain plaintext in the turn map or across disk persistence. The byte
    // buffer is erased by AgentWorkerClient immediately after structured cloning.
    secret = "";
    const turn: ActiveTurn = {
      controller: new AbortController(),
      sessionID: request.sessionId,
      assistantID: assistantMessage.id,
      text: "",
    };
    this.turns.set(requestId, turn);
    this.emit({ type: "started", requestId, sessionId: request.sessionId, userMessage, assistantMessage });
    const running = this.run(requestId, request, provider, credential, context, assistantMessage);
    this.running.add(running);
    void running.finally(() => this.running.delete(running));
    return { requestId };
  }

  async cancel(requestID: string): Promise<void> {
    this.turns.get(requestID)?.controller.abort("cancelled");
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    for (const turn of this.turns.values()) turn.controller.abort("window-closed");
    await this.worker.dispose();
    await Promise.allSettled(this.running);
    this.listeners.clear();
  }

  private async run(
    requestID: string,
    request: AgentStartRequest,
    provider: ProviderPublicConfig,
    credential: Uint8Array,
    context: string,
    initial: AgentMessage,
  ) {
    const turn = this.turns.get(requestID);
    if (!turn) {
      credential.fill(0);
      return;
    }
    try {
      const text = await this.worker.stream({
        requestId: requestID,
        sessionId: request.sessionId,
        provider,
        credential,
        question: request.question,
        context,
        ledgerRoot: this.options.ledgerRoot,
        timeoutMs: this.options.requestTimeoutMs,
        signal: turn.controller.signal,
        onDelta: (delta) => {
          turn.text += delta;
          this.emit({ type: "delta", requestId: requestID, messageId: turn.assistantID, text: turn.text });
        },
      });
      const message = { ...initial, text, completionState: "completed" as const };
      await this.options.sessions.updateMessage(request.sessionId, message);
      this.emit({ type: "completed", requestId: requestID, message });
    } catch (error) {
      const cancelled = turn.controller.signal.aborted;
      const failureKind = cancelled
        ? "cancelled"
        : error instanceof Error && error.message ? error.message : "provider";
      const message = {
        ...initial,
        text: turn.text,
        completionState: "interrupted" as const,
        failureKind,
      };
      await this.options.sessions.updateMessage(request.sessionId, message).catch(() => undefined);
      if (cancelled) this.emit({ type: "cancelled", requestId: requestID, message });
      else this.emit({
        type: "failed",
        requestId: requestID,
        messageId: message.id,
        failureKind,
      });
    } finally {
      credential.fill(0);
      this.turns.delete(requestID);
    }
  }

  private emit(event: AgentEvent) {
    for (const listener of this.listeners) listener(event);
  }
}
