import { randomUUID } from "node:crypto";
import type { AgentEvent, AgentMessage, AgentStartRequest, Citation, ProviderPublicConfig } from "../../shared/contracts";
import {
  AgentWorkerClient,
  type AgentUtilityProcessSpawner,
} from "../agent-worker/client";
import type { AgentWorkerHistoryMessage } from "../agent-worker/protocol";
import type { CredentialVault } from "./credential-vault";
import {
  providerCredentialID,
  userLedCompleteConversationHistory,
} from "./provider-client";
import type { StudySessionStore } from "./session-store";

interface ActiveTurn {
  controller: AbortController;
  assistantID: string;
  text: string;
}

export class AgentRuntime {
  private readonly turns = new Map<string, ActiveTurn>();
  private readonly reservedSessionIDs = new Set<string>();
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
    const reservationID = request.sessionId.toLocaleLowerCase("en-US");
    if (this.reservedSessionIDs.has(reservationID)) throw new Error("session-already-generating");
    this.reservedSessionIDs.add(reservationID);

    let credential: Uint8Array | null = null;
    let requestId: string | null = null;
    let assistantMessage: AgentMessage | null = null;
    let sessionID = request.sessionId;
    let handedOff = false;
    try {
      const session = await this.options.sessions.get(request.sessionId);
      if (!session) throw new Error("session-not-found");
      sessionID = session.id;
      const canonicalRequest = { ...request, sessionId: sessionID };
      const history = boundedConversationHistory(session.messages);
      const provider = this.options.provider();
      const credentialID = providerCredentialID(provider.providerId, provider.baseUrl);
      if (!await this.options.vault.hasSecret(credentialID)) throw new Error("provider-credential-missing");
      requestId = randomUUID();
      const now = new Date().toISOString();
      const userMessage: AgentMessage = {
        id: randomUUID(), role: "user", text: request.question, completionState: "completed",
        sources: [], actions: [], failureKind: null, retryQuestion: null, createdAt: now,
      };
      assistantMessage = {
        id: randomUUID(), role: "assistant", text: "", completionState: "generating",
        sources: [...sources], actions: [], failureKind: null, retryQuestion: request.question, createdAt: now,
      };
      await this.options.sessions.appendMessages(sessionID, [userMessage, assistantMessage]);
      let secret = await this.options.vault.getSecret(credentialID);
      if (!secret) throw new Error("provider-credential-missing");
      credential = new TextEncoder().encode(secret);
      // Never retain plaintext in the turn map or across disk persistence. The byte
      // buffer is erased by AgentWorkerClient immediately after structured cloning.
      secret = "";
      const turn: ActiveTurn = {
        controller: new AbortController(),
        assistantID: assistantMessage.id,
        text: "",
      };
      this.turns.set(requestId, turn);
      this.emit({ type: "started", requestId, sessionId: sessionID, userMessage, assistantMessage });
      const running = this.run(requestId, reservationID, canonicalRequest, provider, credential, history, context, assistantMessage);
      handedOff = true;
      this.running.add(running);
      void running.finally(() => this.running.delete(running));
      return { requestId };
    } catch (error) {
      if (assistantMessage) {
        await this.options.sessions.updateMessage(sessionID, {
          ...assistantMessage,
          completionState: "interrupted",
          failureKind: error instanceof Error && error.message === "provider-credential-missing"
            ? "provider-credential-missing"
            : "agent-start-failed",
        }).catch(() => undefined);
      }
      throw error;
    } finally {
      if (!handedOff) {
        credential?.fill(0);
        if (requestId) this.turns.delete(requestId);
        this.reservedSessionIDs.delete(reservationID);
      }
    }
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
    reservationID: string,
    request: AgentStartRequest,
    provider: ProviderPublicConfig,
    credential: Uint8Array,
    history: AgentWorkerHistoryMessage[],
    context: string,
    initial: AgentMessage,
  ) {
    const turn = this.turns.get(requestID);
    if (!turn) {
      credential.fill(0);
      this.reservedSessionIDs.delete(reservationID);
      return;
    }
    try {
      const text = await this.worker.stream({
        requestId: requestID,
        sessionId: request.sessionId,
        provider,
        credential,
        history,
        question: request.question,
        context,
        ledgerRoot: this.options.ledgerRoot,
        timeoutMs: this.options.requestTimeoutMs,
        signal: turn.controller.signal,
        onDelta: (delta) => {
          turn.text += delta;
          this.emit({ type: "delta", requestId: requestID, sessionId: request.sessionId, messageId: turn.assistantID, text: turn.text });
        },
      });
      const message = { ...initial, text, completionState: "completed" as const };
      await this.options.sessions.updateMessage(request.sessionId, message);
      this.emit({ type: "completed", requestId: requestID, sessionId: request.sessionId, message });
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
      if (cancelled) this.emit({ type: "cancelled", requestId: requestID, sessionId: request.sessionId, message });
      else this.emit({
        type: "failed",
        requestId: requestID,
        sessionId: request.sessionId,
        messageId: message.id,
        message,
        failureKind,
      });
    } finally {
      credential.fill(0);
      this.turns.delete(requestID);
      this.reservedSessionIDs.delete(reservationID);
    }
  }

  private emit(event: AgentEvent) {
    for (const listener of this.listeners) listener(event);
  }
}

function boundedConversationHistory(messages: readonly AgentMessage[]): AgentWorkerHistoryMessage[] {
  const completed = userLedCompleteConversationHistory(messages.flatMap((message): AgentWorkerHistoryMessage[] => {
    if (message.completionState !== "completed") return [];
    const text = message.text.trim().slice(-16_000);
    return text ? [{ role: message.role, text }] : [];
  }));
  const result: AgentWorkerHistoryMessage[] = [];
  let remainingCharacters = 64_000;
  for (let index = completed.length - 2; index >= 0 && result.length <= 38; index -= 2) {
    const user = completed[index];
    const assistant = completed[index + 1];
    if (!user || !assistant) continue;
    const turnCharacters = user.text.length + assistant.text.length;
    if (turnCharacters > remainingCharacters) break;
    remainingCharacters -= turnCharacters;
    result.unshift(user, assistant);
  }
  return result;
}
