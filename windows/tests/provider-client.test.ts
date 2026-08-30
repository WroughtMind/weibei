import assert from "node:assert/strict";
import test from "node:test";
import {
  consumeLegacyProviderCredentialOnUpgrade,
  deleteLegacyUnboundProviderCredential,
  hasEndpointBoundProviderCredential,
  providerCredentialID,
  streamProviderAnswer,
} from "../src/main/services/provider-client.ts";

class MemoryCredentialVault {
  readonly secrets = new Map<string, string>();
  failDeletion = false;

  async hasSecret(id: string): Promise<boolean> {
    return this.secrets.has(id);
  }

  async getSecret(id: string): Promise<string | null> {
    return this.secrets.get(id) ?? null;
  }

  async setSecret(id: string, secret: string): Promise<void> {
    this.secrets.set(id, secret);
  }

  async deleteSecret(id: string): Promise<boolean> {
    if (this.failDeletion) throw new Error("credential-delete-failed");
    return this.secrets.delete(id);
  }
}

test("changing a provider endpoint cannot reuse the credential saved for another endpoint", async () => {
  const vault = new MemoryCredentialVault();
  const officialEndpoint = "https://api.openai.com/v1";
  const otherEndpoint = "https://proxy.example/v1";
  const officialID = providerCredentialID("openai", officialEndpoint);
  const otherID = providerCredentialID("openai", otherEndpoint);
  assert.notEqual(officialID, otherID);

  vault.secrets.set(officialID, "official-endpoint-key");
  assert.equal(
    await hasEndpointBoundProviderCredential(vault, "openai", otherEndpoint),
    false,
  );
  assert.equal(vault.secrets.has(otherID), false);
});

test("an official stored endpoint consumes its legacy credential after binding it", async () => {
  const vault = new MemoryCredentialVault();
  vault.secrets.set("provider.openai", "legacy-openai-key");

  const officialEndpoint = "https://api.openai.com/v1/";
  assert.equal(
    await consumeLegacyProviderCredentialOnUpgrade(vault, "openai", officialEndpoint),
    true,
  );
  assert.equal(
    vault.secrets.get(providerCredentialID("openai", officialEndpoint)),
    "legacy-openai-key",
  );
  assert.equal(vault.secrets.has("provider.openai"), false);
});

test("a legacy proxy key is consumed without binding and cannot revive on a later official endpoint", async () => {
  const vault = new MemoryCredentialVault();
  vault.secrets.set("provider.openai", "legacy-proxy-key");

  const proxyEndpoint = "https://proxy.example/v1";
  assert.equal(
    await consumeLegacyProviderCredentialOnUpgrade(vault, "openai", proxyEndpoint),
    false,
  );
  assert.equal(vault.secrets.has("provider.openai"), false);
  assert.equal(
    vault.secrets.has(providerCredentialID("openai", proxyEndpoint)),
    false,
  );

  const officialEndpoint = "https://api.openai.com/v1";
  await deleteLegacyUnboundProviderCredential(vault, "openai");
  assert.equal(await hasEndpointBoundProviderCredential(vault, "openai", officialEndpoint), false);
  assert.equal(
    await consumeLegacyProviderCredentialOnUpgrade(vault, "openai", officialEndpoint),
    false,
  );
  assert.equal(vault.secrets.has(providerCredentialID("openai", officialEndpoint)), false);
});

test("a legacy cleanup persistence failure blocks endpoint upgrade", async () => {
  const vault = new MemoryCredentialVault();
  const proxyEndpoint = "https://proxy.example/v1";
  vault.secrets.set("provider.openai", "legacy-proxy-key");
  vault.failDeletion = true;

  await assert.rejects(consumeLegacyProviderCredentialOnUpgrade(vault, "openai", proxyEndpoint));
  assert.equal(vault.secrets.has("provider.openai"), true);
  assert.equal(vault.secrets.has(providerCredentialID("openai", proxyEndpoint)), false);
});

test("provider families preserve native conversation roles and append the contextual question", async (t) => {
  const originalFetch = globalThis.fetch;
  const history = [
    { role: "assistant" as const, text: "不能作为 Gemini 首条的孤立回答" },
    { role: "user" as const, text: "前一问" },
    { role: "assistant" as const, text: "前一答" },
    { role: "user" as const, text: "当前问题" },
  ];
  const question = "当前问题";
  const context = "课程证据";
  const contextualQuestion = [
    "以下是应用提供的证据状态与有界上下文。严格遵守其中的出处约束，并把课程证据、通用知识与推断清楚区分。",
    context,
    `用户问题：${question}`,
  ].join("\n\n");

  const cases = [
    {
      name: "OpenAI Responses",
      providerId: "openai",
      baseUrl: "https://api.openai.com/v1",
      path: "/v1/responses",
      sse: "event: response.output_text.delta\ndata: {\"delta\":\"答\"}\n\n",
      messagesKey: "input",
      expectedMessages: [
        { role: "user", content: "前一问" },
        { role: "assistant", content: "前一答" },
        { role: "user", content: contextualQuestion },
      ],
    },
    {
      name: "OpenAI-compatible custom chat",
      providerId: "custom",
      baseUrl: "https://llm.example/v1",
      path: "/v1/chat/completions",
      sse: "data: {\"choices\":[{\"delta\":{\"content\":\"答\"}}]}\n\n",
      messagesKey: "messages",
      expectedMessages: [
        { role: "user", content: "前一问" },
        { role: "assistant", content: "前一答" },
        { role: "user", content: contextualQuestion },
      ],
    },
    {
      name: "Anthropic",
      providerId: "anthropic",
      baseUrl: "https://api.anthropic.com/v1",
      path: "/v1/messages",
      sse: "event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"答\"}}\n\n",
      messagesKey: "messages",
      expectedMessages: [
        { role: "user", content: "前一问" },
        { role: "assistant", content: "前一答" },
        { role: "user", content: contextualQuestion },
      ],
    },
    {
      name: "Google",
      providerId: "google",
      baseUrl: "https://generativelanguage.googleapis.com/v1beta",
      path: "/v1beta/models/test-model:streamGenerateContent?alt=sse",
      sse: "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"答\"}]}}]}\n\n",
      messagesKey: "contents",
      expectedMessages: [
        { role: "user", parts: [{ text: "前一问" }] },
        { role: "model", parts: [{ text: "前一答" }] },
        { role: "user", parts: [{ text: contextualQuestion }] },
      ],
    },
  ] as const;

  try {
    for (const providerCase of cases) {
      await t.test(providerCase.name, async () => {
        let requestURL = "";
        let requestBody: Record<string, unknown> | null = null;
        let fetchCalls = 0;
        globalThis.fetch = (async (input, init) => {
          fetchCalls += 1;
          requestURL = String(input);
          requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
          return new Response(providerCase.sse, {
            status: 200,
            headers: { "Content-Type": "text/event-stream" },
          });
        }) as typeof fetch;

        const deltas: string[] = [];
        const answer = await streamProviderAnswer({
          provider: {
            providerId: providerCase.providerId,
            model: "test-model",
            baseUrl: providerCase.baseUrl,
            hasCredential: true,
          },
          apiKey: "test-key",
          history,
          question,
          context,
          signal: new AbortController().signal,
          onDelta: (delta) => deltas.push(delta),
        });

        assert.equal(fetchCalls, 1);
        assert.equal(new URL(requestURL).pathname + new URL(requestURL).search, providerCase.path);
        assert.ok(requestBody);
        assert.deepEqual(requestBody[providerCase.messagesKey], providerCase.expectedMessages);
        assert.equal(answer, "答");
        assert.deepEqual(deltas, ["答"]);
      });
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("an Anthropic in-stream error rejects after retaining every delivered partial delta", async () => {
  const originalFetch = globalThis.fetch;
  const deltas: string[] = [];
  try {
    globalThis.fetch = (async () => new Response([
      "event: content_block_delta",
      "data: {\"delta\":{\"type\":\"text_delta\",\"text\":\"部分回答\"}}",
      "",
      "event: error",
      "data: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"raw provider detail must not escape\"}}",
      "",
      "",
    ].join("\n"), {
      status: 200,
      headers: { "Content-Type": "text/event-stream" },
    })) as typeof fetch;

    await assert.rejects(
      streamProviderAnswer({
        provider: {
          providerId: "anthropic",
          model: "claude-test",
          baseUrl: "https://api.anthropic.com/v1",
          hasCredential: true,
        },
        apiKey: "test-key",
        question: "当前问题",
        signal: new AbortController().signal,
        onDelta: (delta) => deltas.push(delta),
      }),
      (error: unknown) => {
        assert.ok(error instanceof Error);
        assert.equal(error.message, "provider-stream-overloaded_error");
        assert.doesNotMatch(error.message, /raw provider detail/u);
        return true;
      },
    );
    assert.deepEqual(deltas, ["部分回答"]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
