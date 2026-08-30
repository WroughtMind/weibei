import { createHash } from "node:crypto";
import type { ProviderPublicConfig } from "../../shared/contracts";
import type { CredentialVault } from "./credential-vault";

export type TextDeltaHandler = (delta: string) => void;

export interface ProviderConversationMessage {
  role: "user" | "assistant";
  text: string;
}

/**
 * Keep only complete user-led turns. Imported or interrupted histories can
 * contain leading assistants or a final unanswered user message, neither of
 * which is a valid portable chat prefix for every native provider.
 */
export function userLedCompleteConversationHistory(
  messages: readonly ProviderConversationMessage[],
): ProviderConversationMessage[] {
  const result: ProviderConversationMessage[] = [];
  let pendingUser: ProviderConversationMessage | null = null;
  for (const message of messages) {
    const text = message.text.trim();
    if (!text) continue;
    if (message.role === "user") {
      pendingUser = { role: "user", text };
      continue;
    }
    if (!pendingUser) continue;
    result.push(pendingUser, { role: "assistant", text });
    pendingUser = null;
  }
  return result;
}

export async function streamProviderAnswer(options: {
  provider: ProviderPublicConfig;
  apiKey: string;
  history?: readonly ProviderConversationMessage[];
  question: string;
  context?: string;
  signal: AbortSignal;
  onDelta: TextDeltaHandler;
}): Promise<string> {
  const endpoint = normalizeProviderEndpoint(options.provider.baseUrl);
  const family = protocolFamily(options.provider.providerId);
  if (family === "anthropic") return streamAnthropic(endpoint, options);
  if (family === "google") return streamGoogle(endpoint, options);
  if (family === "responses") return streamOpenAIResponses(endpoint, options);
  return streamOpenAIChat(endpoint, options);
}

export function normalizeProviderEndpoint(input: string): URL {
  if (input.length > 2_048) throw new ProviderEndpointError("endpoint-too-long");
  let url: URL;
  try { url = new URL(input); } catch { throw new ProviderEndpointError("invalid-endpoint"); }
  if (url.protocol !== "https:" && url.protocol !== "http:") throw new ProviderEndpointError("unsupported-scheme");
  if (url.username || url.password || url.search || url.hash) throw new ProviderEndpointError("endpoint-has-forbidden-components");
  url.hostname = url.hostname.toLocaleLowerCase("en-US");
  if (url.protocol === "http:" && !isLocalOrLANHost(url.hostname)) throw new ProviderEndpointError("insecure-public-http");
  url.pathname = url.pathname.replace(/\/+$/u, "") || "/";
  return url;
}

export function providerCredentialID(providerID: string, baseURL: string): string {
  const normalized = normalizeProviderEndpoint(baseURL).toString();
  const safeProvider = providerCredentialSegment(providerID);
  const endpointOwner = createHash("sha256").update(normalized).digest("hex");
  return `provider.${safeProvider}.${endpointOwner}`;
}

type ProviderCredentialLookup = Pick<CredentialVault, "hasSecret">;
type ProviderCredentialMigrationVault = Pick<
  CredentialVault,
  "deleteSecret" | "getSecret" | "hasSecret" | "setSecret"
>;

/** Reports only whether this exact provider endpoint owns a credential. */
export async function hasEndpointBoundProviderCredential(
  vault: ProviderCredentialLookup,
  providerID: string,
  baseURL: string,
): Promise<boolean> {
  return vault.hasSecret(providerCredentialID(providerID, baseURL));
}

/**
 * Consumes the endpoint-unbound credential left by the pre-binding release.
 * Only a provider already stored on its official endpoint may copy it first;
 * every other endpoint discards it so a later endpoint change cannot revive it.
 */
export async function consumeLegacyProviderCredentialOnUpgrade(
  vault: ProviderCredentialMigrationVault,
  providerID: string,
  baseURL: string,
): Promise<boolean> {
  const credentialID = providerCredentialID(providerID, baseURL);
  let hasCredential = await vault.hasSecret(credentialID);
  const legacyID = legacyUnboundProviderCredentialID(providerID);
  if (!legacyID || !await vault.hasSecret(legacyID)) return hasCredential;

  if (!hasCredential && isOfficialProviderEndpoint(providerID, baseURL)) {
    let secret = await vault.getSecret(legacyID);
    if (secret) {
      try {
        await vault.setSecret(credentialID, secret);
        hasCredential = true;
      } finally {
        secret = "";
      }
    }
  }
  await vault.deleteSecret(legacyID);
  return hasCredential;
}

/** Removes any endpoint-unbound key before a newly saved endpoint is used. */
export async function deleteLegacyUnboundProviderCredential(
  vault: Pick<CredentialVault, "deleteSecret">,
  providerID: string,
): Promise<void> {
  const legacyID = legacyUnboundProviderCredentialID(providerID);
  if (legacyID) await vault.deleteSecret(legacyID);
}

const officialProviderEndpoints: Readonly<Record<string, string>> = Object.freeze({
  openai: "https://api.openai.com/v1",
  anthropic: "https://api.anthropic.com/v1",
  google: "https://generativelanguage.googleapis.com/v1beta",
});

function isOfficialProviderEndpoint(providerID: string, baseURL: string): boolean {
  const safeProvider = providerCredentialSegment(providerID);
  const officialEndpoint = officialProviderEndpoints[safeProvider];
  if (!officialEndpoint) return false;
  const normalized = normalizeProviderEndpoint(baseURL).toString();
  return normalized === normalizeProviderEndpoint(officialEndpoint).toString();
}

function legacyUnboundProviderCredentialID(providerID: string): string | null {
  const safeProvider = providerCredentialSegment(providerID);
  if (safeProvider === "custom" || safeProvider.includes("llama")) return null;
  return `provider.${safeProvider}`;
}

function providerCredentialSegment(providerID: string): string {
  return providerID.toLocaleLowerCase("en-US").replace(/[^a-z0-9._-]/gu, "-").slice(0, 64) || "custom";
}

export class ProviderEndpointError extends Error {
  constructor(readonly code: string) { super(code); this.name = "ProviderEndpointError"; }
}

function protocolFamily(providerID: string): "chat" | "responses" | "anthropic" | "google" {
  const id = providerID.toLocaleLowerCase("en-US");
  if (id.includes("anthropic") || id.includes("claude")) return "anthropic";
  if (id.includes("google") || id.includes("gemini")) return "google";
  if (id.includes("response") || id === "openai" || id.includes("codex")) return "responses";
  return "chat";
}

async function streamOpenAIResponses(endpoint: URL, options: Parameters<typeof streamProviderAnswer>[0]): Promise<string> {
  const response = await fetch(joinEndpoint(endpoint, "responses"), {
    method: "POST",
    headers: { Authorization: `Bearer ${options.apiKey}`, "Content-Type": "application/json", Accept: "text/event-stream" },
    body: JSON.stringify({
      model: options.provider.model,
      input: providerConversation(options).map((message) => ({ role: message.role, content: message.text })),
      stream: true,
    }),
    signal: options.signal,
    redirect: "error",
  });
  return consumeSSE(response, options.onDelta, (event, data) => {
    if (event === "response.output_text.delta" && typeof data.delta === "string") return data.delta;
    if (event === "error") throw providerError(response, data);
    return null;
  });
}

async function streamOpenAIChat(endpoint: URL, options: Parameters<typeof streamProviderAnswer>[0]): Promise<string> {
  const response = await fetch(joinEndpoint(endpoint, "chat/completions"), {
    method: "POST",
    headers: { Authorization: `Bearer ${options.apiKey}`, "Content-Type": "application/json", Accept: "text/event-stream" },
    body: JSON.stringify({
      model: options.provider.model,
      messages: providerConversation(options).map((message) => ({ role: message.role, content: message.text })),
      stream: true,
    }),
    signal: options.signal,
    redirect: "error",
  });
  return consumeSSE(response, options.onDelta, (_event, data) => {
    const choices = Array.isArray(data.choices) ? data.choices : [];
    const first = choices[0] as { delta?: { content?: unknown } } | undefined;
    return typeof first?.delta?.content === "string" ? first.delta.content : null;
  });
}

async function streamAnthropic(endpoint: URL, options: Parameters<typeof streamProviderAnswer>[0]): Promise<string> {
  const response = await fetch(joinEndpoint(endpoint, "messages"), {
    method: "POST",
    headers: { "x-api-key": options.apiKey, "anthropic-version": "2023-06-01", "Content-Type": "application/json", Accept: "text/event-stream" },
    body: JSON.stringify({
      model: options.provider.model,
      max_tokens: 8_192,
      messages: providerConversation(options).map((message) => ({ role: message.role, content: message.text })),
      stream: true,
    }),
    signal: options.signal,
    redirect: "error",
  });
  return consumeSSE(response, options.onDelta, (event, data) => {
    if (event === "error") throw providerStreamError(data);
    if (event !== "content_block_delta") return null;
    const delta = data.delta as { type?: unknown; text?: unknown } | undefined;
    return delta?.type === "text_delta" && typeof delta.text === "string" ? delta.text : null;
  });
}

async function streamGoogle(endpoint: URL, options: Parameters<typeof streamProviderAnswer>[0]): Promise<string> {
  const model = encodeURIComponent(options.provider.model.replace(/^models\//u, ""));
  const response = await fetch(joinEndpoint(endpoint, `models/${model}:streamGenerateContent?alt=sse`), {
    method: "POST",
    headers: { "x-goog-api-key": options.apiKey, "Content-Type": "application/json", Accept: "text/event-stream" },
    body: JSON.stringify({
      contents: providerConversation(options).map((message) => ({
        role: message.role === "assistant" ? "model" : "user",
        parts: [{ text: message.text }],
      })),
    }),
    signal: options.signal,
    redirect: "error",
  });
  return consumeSSE(response, options.onDelta, (_event, data) => {
    const candidates = Array.isArray(data.candidates) ? data.candidates : [];
    const candidate = candidates[0] as { content?: { parts?: Array<{ text?: unknown }> } } | undefined;
    return candidate?.content?.parts?.map((part) => typeof part.text === "string" ? part.text : "").join("") || null;
  });
}

async function consumeSSE(
  response: Response,
  onDelta: TextDeltaHandler,
  decode: (event: string, data: Record<string, unknown>) => string | null,
): Promise<string> {
  if (!response.ok || !response.body) {
    const detail = (await response.text().catch(() => "")).slice(0, 2_048);
    throw new Error(`provider-http-${response.status}${detail ? `: ${detail}` : ""}`);
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let output = "";
  while (true) {
    const { value, done } = await reader.read();
    buffer += decoder.decode(value, { stream: !done });
    const frames = buffer.split(/\r?\n\r?\n/u);
    buffer = frames.pop() ?? "";
    for (const frame of frames) {
      let event = "message";
      const dataLines: string[] = [];
      for (const line of frame.split(/\r?\n/u)) {
        if (line.startsWith("event:")) event = line.slice(6).trim();
        if (line.startsWith("data:")) dataLines.push(line.slice(5).trimStart());
      }
      const raw = dataLines.join("\n");
      if (!raw || raw === "[DONE]") continue;
      let data: Record<string, unknown>;
      try { data = JSON.parse(raw) as Record<string, unknown>; } catch { continue; }
      const delta = decode(event, data);
      if (delta) { output += delta; onDelta(delta); }
    }
    if (done) break;
  }
  return output;
}

function prompt(options: { question: string; context?: string }) {
  if (!options.context) return options.question;
  return `以下是应用提供的证据状态与有界上下文。严格遵守其中的出处约束，并把课程证据、通用知识与推断清楚区分。\n\n${options.context}\n\n用户问题：${options.question}`;
}
function providerConversation(
  options: { question: string; context?: string; history?: readonly ProviderConversationMessage[] },
): ProviderConversationMessage[] {
  return [
    ...userLedCompleteConversationHistory(options.history ?? []),
    { role: "user", text: prompt(options) },
  ];
}
function joinEndpoint(endpoint: URL, route: string): string {
  const base = endpoint.toString().replace(/\/+$/u, "");
  const cleanRoute = route.replace(/^\/+/, "");
  // Preserve Google's intentional query while base endpoints themselves forbid it.
  return `${base}/${cleanRoute}`;
}
function providerError(response: Response, data: unknown): Error { return new Error(`provider-http-${response.status}: ${JSON.stringify(data).slice(0, 1024)}`); }
function providerStreamError(data: Record<string, unknown>): Error {
  const detail = isRecord(data.error) ? data.error.type : null;
  const kind = typeof detail === "string"
    ? detail.toLocaleLowerCase("en-US").replace(/[^a-z0-9._-]+/gu, "-").slice(0, 80)
    : "error";
  return new Error(`provider-stream-${kind || "error"}`);
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
function isLocalOrLANHost(host: string): boolean {
  if (host === "localhost" || host === "::1" || host.endsWith(".local")) return true;
  const v4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/u.exec(host);
  if (!v4) return false;
  const parts = v4.slice(1).map(Number);
  if (parts.some((part) => part > 255)) return false;
  return parts[0] === 10 || parts[0] === 127 || (parts[0] === 192 && parts[1] === 168) || (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31);
}
