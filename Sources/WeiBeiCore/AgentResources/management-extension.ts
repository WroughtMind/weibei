import { join } from "node:path";

import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import type { AuthEvent, AuthInteraction, AuthPrompt, AuthType } from "@earendil-works/pi-ai";

const COMMAND = "weibei-management";
const CHANNEL = "weibei.pi.management";
const SCHEMA_VERSION = 1;
const PI_PACKAGE: string = "@earendil-works/pi-coding-agent";
const AZURE_PROVIDER = "azure-openai-responses";
const AZURE_BASE_URL_ENV = "AZURE_OPENAI_BASE_URL";

type ManagementRequest =
  | { action: "catalog"; refresh?: boolean }
  | { action: "login"; providerId: string; authType: AuthType; endpoint?: string }
  | { action: "logout"; providerId: string };

function message(payload: Record<string, unknown>): string {
  return JSON.stringify({ schemaVersion: SCHEMA_VERSION, channel: CHANNEL, ...payload });
}

function errorMessage(error: unknown): string {
  const value = error instanceof Error ? error.message : String(error);
  return value.replace(/[\r\n\t]+/gu, " ").slice(0, 1_000) || "Pi 管理操作失败";
}

function credentialEndpoint(value: unknown): string {
  if (typeof value !== "string" || new TextEncoder().encode(value).byteLength > 2_048) {
    throw new Error("Pi 凭据地址无效");
  }
  const endpoint = value.trim();
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    throw new Error("Pi 凭据地址无效");
  }
  if (
    (url.protocol !== "https:" && url.protocol !== "http:") ||
    !url.hostname ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  ) {
    throw new Error("Pi 凭据地址无效");
  }
  return endpoint;
}

function parseRequest(args: string): ManagementRequest {
  if (new TextEncoder().encode(args).byteLength > 4_096) {
    throw new Error("Pi 管理请求超过大小上限");
  }
  const value = JSON.parse(args) as Partial<ManagementRequest>;
  if (value.action === "catalog") {
    return { action: "catalog", refresh: value.refresh === true };
  }
  if (
    (value.action === "login" || value.action === "logout") &&
    typeof value.providerId === "string" &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/u.test(value.providerId)
  ) {
    if (value.action === "logout") return { action: "logout", providerId: value.providerId };
    if (value.authType === "api_key" || value.authType === "oauth") {
      const endpoint = value.endpoint === undefined
        ? undefined
        : credentialEndpoint(value.endpoint);
      if (
        (value.providerId === AZURE_PROVIDER && value.authType === "api_key") !==
        (endpoint !== undefined)
      ) {
        throw new Error("Pi 凭据地址无效");
      }
      return { action: "login", providerId: value.providerId, authType: value.authType, endpoint };
    }
  }
  throw new Error("Pi 管理请求无效");
}

function promptTitle(prompt: AuthPrompt): string {
  return message({
    kind: "prompt",
    prompt: {
      type: prompt.type,
      message: prompt.message,
      placeholder: "placeholder" in prompt ? prompt.placeholder : undefined,
      options: prompt.type === "select" ? prompt.options : undefined,
    },
  });
}

function interaction(ctx: ExtensionCommandContext): AuthInteraction {
  return {
    async prompt(prompt) {
      const title = promptTitle(prompt);
      if (prompt.type === "select") {
        const labels = prompt.options.map((option) => option.label);
        const selected = await ctx.ui.select(title, labels, { signal: prompt.signal });
        const option = prompt.options.find((candidate) => candidate.label === selected);
        if (!option) throw new Error("登录已取消");
        return option.id;
      }
      const value = await ctx.ui.input(title, prompt.placeholder, { signal: prompt.signal });
      if (value === undefined) throw new Error("登录已取消");
      return value;
    },
    notify(event: AuthEvent) {
      ctx.ui.notify(message({ kind: "event", event }));
    },
  };
}

async function run(args: string, ctx: ExtensionCommandContext): Promise<void> {
  let action: ManagementRequest["action"] | undefined;
  try {
    const request = parseRequest(args);
    action = request.action;
    const agentDirectory = process.env.PI_CODING_AGENT_DIR;
    const authPath = process.env.WEIBEI_PI_AUTH_PATH;
    if (!agentDirectory || !authPath) throw new Error("魏碑 Pi 配置目录不可用");

    const { ModelRuntime, readStoredCredential } = await import(PI_PACKAGE);
    const runtime = await ModelRuntime.create({
      authPath,
      modelsPath: join(agentDirectory, "models.json"),
    });

    if (request.action === "catalog") {
      const credentials = await runtime.listCredentials();
      const azureCredential = readStoredCredential(AZURE_PROVIDER, authPath);
      const boundAzureEndpoint = azureCredential?.type === "api_key" &&
        typeof azureCredential.env?.[AZURE_BASE_URL_ENV] === "string"
        ? azureCredential.env[AZURE_BASE_URL_ENV]
        : undefined;
      ctx.ui.notify(message({
        kind: "result",
        action: request.action,
        catalog: {
          providers: runtime.getProviders().map((provider) => {
            const status = runtime.getProviderAuthStatus(provider.id);
            return {
              id: provider.id,
              name: provider.name,
              authTypes: [
                provider.auth.apiKey ? "api_key" : undefined,
                provider.auth.oauth ? "oauth" : undefined,
              ].filter((type): type is AuthType => type !== undefined),
              configured: status.configured,
              authSource: status.source,
            };
          }),
          models: runtime.getModels().map((model) => ({
            id: model.id,
            name: model.name,
            providerId: model.provider,
            api: model.api,
            reasoning: model.reasoning,
            input: model.input,
            contextWindow: model.contextWindow,
            maxTokens: model.maxTokens,
          })),
          credentials: credentials.map((credential) => ({
            ...credential,
            boundEndpoint: credential.providerId === AZURE_PROVIDER
              ? boundAzureEndpoint
              : undefined,
          })),
        },
      }));
      return;
    }

    const provider = runtime.getProvider(request.providerId);
    if (!provider) throw new Error(`Pi 不认识供应商 ${request.providerId}`);
    if (request.action === "logout") {
      await runtime.logout(request.providerId);
      ctx.ui.notify(message({ kind: "result", action: request.action, providerId: request.providerId }));
      return;
    }

    const supported = request.authType === "api_key"
      ? provider.auth.apiKey !== undefined
      : provider.auth.oauth !== undefined;
    if (!supported) throw new Error(`供应商 ${request.providerId} 不支持 ${request.authType} 登录`);
    if (request.providerId === AZURE_PROVIDER && request.endpoint) {
      const apiKeyAuth = provider.auth.apiKey;
      const login = apiKeyAuth?.login;
      if (!apiKeyAuth || !login) throw new Error("Azure OpenAI API 密钥登录不可用");
      const endpoint = request.endpoint;
      runtime.registerNativeProvider({
        ...provider,
        auth: {
          ...provider.auth,
          apiKey: {
            ...apiKeyAuth,
            async login(interaction) {
              const credential = await login(interaction);
              return {
                ...credential,
                env: { ...credential.env, [AZURE_BASE_URL_ENV]: endpoint },
              };
            },
          },
        },
      });
    }
    await runtime.login(request.providerId, request.authType, interaction(ctx));
    ctx.ui.notify(message({
      kind: "result",
      action: request.action,
      credential: {
        providerId: request.providerId,
        type: request.authType,
        boundEndpoint: request.endpoint,
      },
    }));
  } catch (error) {
    ctx.ui.notify(message({ kind: "error", action, message: errorMessage(error) }), "error");
  }
}

export default function managementExtension(pi: ExtensionAPI): void {
  pi.registerCommand(COMMAND, {
    description: "通过魏碑内置 Pi 管理认证与模型目录",
    handler: run,
  });
}
