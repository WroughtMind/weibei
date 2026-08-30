import type { ProviderPublicConfig } from "../../shared/contracts";

export const AGENT_WORKER_PROTOCOL_VERSION = 1 as const;
export const DEFAULT_AGENT_TIMEOUT_MS = 120_000;
export const MAXIMUM_AGENT_TIMEOUT_MS = 10 * 60_000;
export const MAXIMUM_AGENT_CREDENTIAL_BYTES = 1024 * 1024;

export interface AgentWorkerHistoryMessage {
  role: "user" | "assistant";
  text: string;
}

export interface AgentWorkerStartCommand {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "start";
  requestId: string;
  sessionId: string;
  provider: ProviderPublicConfig;
  credential: Uint8Array;
  history: AgentWorkerHistoryMessage[];
  question: string;
  context: string;
  ledgerRoot: string;
  timeoutMs: number;
}

export interface AgentWorkerAbortCommand {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "abort";
  requestId: string;
}

export interface AgentWorkerShutdownCommand {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "shutdown";
}

export interface AgentWorkerInitializeCommand {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "initialize";
}

export type AgentWorkerCommand =
  | AgentWorkerInitializeCommand
  | AgentWorkerStartCommand
  | AgentWorkerAbortCommand
  | AgentWorkerShutdownCommand;

export interface AgentWorkerReadyEvent {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "ready";
}

export interface AgentWorkerDeltaEvent {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "delta";
  requestId: string;
  delta: string;
}

export interface AgentWorkerCompletedEvent {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "completed";
  requestId: string;
  text: string;
}

export interface AgentWorkerFailedEvent {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "failed";
  requestId: string;
  failureKind: string;
}

export interface AgentWorkerCancelledEvent {
  version: typeof AGENT_WORKER_PROTOCOL_VERSION;
  type: "cancelled";
  requestId: string;
}

export type AgentWorkerEvent =
  | AgentWorkerReadyEvent
  | AgentWorkerDeltaEvent
  | AgentWorkerCompletedEvent
  | AgentWorkerFailedEvent
  | AgentWorkerCancelledEvent;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

export function isAgentWorkerCommand(value: unknown): value is AgentWorkerCommand {
  if (!isRecord(value) || value.version !== AGENT_WORKER_PROTOCOL_VERSION || typeof value.type !== "string") return false;
  if (value.type === "initialize" || value.type === "shutdown") return true;
  if (value.type === "abort") return isUUID(value.requestId);
  if (value.type !== "start") return false;
  return isUUID(value.requestId)
    && isUUID(value.sessionId)
    && isProvider(value.provider)
    && value.credential instanceof Uint8Array
    && value.credential.byteLength > 0
    && value.credential.byteLength <= MAXIMUM_AGENT_CREDENTIAL_BYTES
    && isHistory(value.history)
    && typeof value.question === "string"
    && value.question.trim().length > 0
    && value.question.length <= 32_000
    && typeof value.context === "string"
    && value.context.length <= 128_000
    && typeof value.ledgerRoot === "string"
    && value.ledgerRoot.length > 0
    && value.ledgerRoot.length <= 32_767
    && !value.ledgerRoot.includes("\0")
    && typeof value.timeoutMs === "number"
    && Number.isInteger(value.timeoutMs)
    && value.timeoutMs >= 1_000
    && value.timeoutMs <= MAXIMUM_AGENT_TIMEOUT_MS;
}

function isHistory(value: unknown): value is AgentWorkerHistoryMessage[] {
  if (!Array.isArray(value) || value.length > 40) return false;
  let characters = 0;
  for (const message of value) {
    if (!isRecord(message)) return false;
    if (message.role !== "user" && message.role !== "assistant") return false;
    if (typeof message.text !== "string" || !message.text.trim() || message.text.length > 16_000) return false;
    characters += message.text.length;
    if (characters > 64_000) return false;
  }
  return true;
}

export function isAgentWorkerEvent(value: unknown): value is AgentWorkerEvent {
  if (!isRecord(value) || value.version !== AGENT_WORKER_PROTOCOL_VERSION || typeof value.type !== "string") return false;
  if (value.type === "ready") return true;
  if (!isUUID(value.requestId)) return false;
  if (value.type === "cancelled") return true;
  if (value.type === "delta") return typeof value.delta === "string";
  if (value.type === "completed") return typeof value.text === "string";
  if (value.type === "failed") return typeof value.failureKind === "string" && value.failureKind.length > 0 && value.failureKind.length <= 512;
  return false;
}

function isProvider(value: unknown): value is ProviderPublicConfig {
  return isRecord(value)
    && typeof value.providerId === "string"
    && value.providerId.length > 0
    && value.providerId.length <= 80
    && typeof value.model === "string"
    && value.model.length > 0
    && value.model.length <= 200
    && typeof value.baseUrl === "string"
    && value.baseUrl.length > 0
    && value.baseUrl.length <= 2_048
    && typeof value.hasCredential === "boolean";
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
