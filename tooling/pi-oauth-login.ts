/**
 * Pi-compatible OAuth login helper for WeiBei.
 * Mirrors Pi's /login subscription flows and writes credentials to auth.json
 * (default: ~/.pi/agent/auth.json), which PiAgentRuntime seeds into its config dir.
 *
 * Usage:
 *   node pi-oauth-login.mjs --provider openai-codex [--auth-path PATH]
 *   node pi-oauth-login.mjs --provider anthropic [--auth-path PATH]
 *   node pi-oauth-login.mjs --status
 *
 * Progress is printed as JSON lines to stdout for the host app.
 */
import { spawn } from "node:child_process";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as http from "node:http";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

export interface OAuthArguments {
  authPath: string;
  provider: string;
  status: boolean;
}

export interface OAuthCredential {
  access: string;
  accountId?: string;
  expires: number;
  refresh: string;
  type: "oauth";
}

export interface ProviderStatus {
  expires: unknown;
  hasAccess: boolean;
  id: string;
  type: unknown;
}

interface CallbackServerOptions {
  codeParam?: string;
  expectedState: string;
  host: string;
  pathName: string;
  port: number;
}

interface CallbackServer {
  close: () => Promise<void>;
  waitForCode: () => Promise<{ code: string }>;
}

type AuthStore = Record<string, unknown>;

const OPENAI_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const OPENAI_AUTH_BASE = "https://auth.openai.com";
const OPENAI_AUTHORIZE = `${OPENAI_AUTH_BASE}/oauth/authorize`;
const OPENAI_TOKEN = `${OPENAI_AUTH_BASE}/oauth/token`;
const OPENAI_REDIRECT = "http://localhost:1455/auth/callback";
const OPENAI_SCOPE = "openid profile email offline_access";
const OPENAI_JWT_CLAIM = "https://api.openai.com/auth";

const ANTHROPIC_CLIENT_ID = Buffer.from(
  "OWQxYzI1MGEtZTYxYi00NGQ5LTg4ZWQtNTk0NGQxOTYyZjVl",
  "base64",
).toString("utf8");
const ANTHROPIC_AUTHORIZE = "https://claude.ai/oauth/authorize";
const ANTHROPIC_TOKEN = "https://platform.claude.com/v1/oauth/token";
const ANTHROPIC_PORT = 53692;
const ANTHROPIC_PATH = "/callback";
const ANTHROPIC_REDIRECT = `http://localhost:${ANTHROPIC_PORT}${ANTHROPIC_PATH}`;
const ANTHROPIC_SCOPES =
  "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload";

/**
 * 判断未知值是否为可安全读取字段的普通对象。
 *
 * @param value - 待检查的 JSON 值
 * @returns 值是否为非数组对象
 */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * 从未知对象中读取字符串字段。
 *
 * @param value - OAuth 服务返回的未知 JSON 值
 * @param key - 要读取的字段名
 * @returns 字段为字符串时返回字段值
 */
function stringProperty(value: unknown, key: string): string | undefined {
  if (!isRecord(value)) return undefined;
  const property = value[key];
  return typeof property === "string" ? property : undefined;
}

/**
 * 将未知异常转换为适合 JSONL 输出的错误消息。
 *
 * @param error - 捕获到的异常
 * @returns 可展示的错误消息
 */
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * 向宿主应用输出一条 JSONL 进度记录。
 *
 * @param value - 可被 JSON 序列化的进度数据
 */
export function emit(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

/**
 * 解析 Pi OAuth helper 的命令行参数。
 *
 * @param argv - 包含 node 与脚本路径的完整参数数组
 * @returns 规范化后的 provider、认证文件路径与状态模式
 */
export function parseArgs(argv: readonly string[]): OAuthArguments {
  const result: OAuthArguments = { provider: "", authPath: "", status: false };
  for (let index = 2; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--status") {
      result.status = true;
    } else if (argument === "--provider") {
      result.provider = argv[index + 1] || "";
      index += 1;
    } else if (argument === "--auth-path") {
      result.authPath = argv[index + 1] || "";
      index += 1;
    }
  }
  if (!result.authPath) {
    result.authPath = path.join(os.homedir(), ".pi", "agent", "auth.json");
  }
  return result;
}

/**
 * 读取 Pi 认证存储；文件缺失或内容损坏时按空存储处理。
 *
 * @param authPath - auth.json 文件路径
 * @returns 可更新的认证存储
 */
export function readAuth(authPath: string): AuthStore {
  try {
    const parsed: unknown = JSON.parse(fs.readFileSync(authPath, "utf8"));
    return isRecord(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

/**
 * 以仅限当前用户读取的权限写入 Pi 认证存储。
 *
 * @param authPath - auth.json 文件路径
 * @param data - 要持久化的认证存储
 */
export function writeAuth(authPath: string, data: AuthStore): void {
  fs.mkdirSync(path.dirname(authPath), { recursive: true, mode: 0o700 });
  fs.writeFileSync(authPath, `${JSON.stringify(data, null, 2)}\n`, {
    mode: 0o600,
  });
  try {
    fs.chmodSync(authPath, 0o600);
  } catch {
    // 某些文件系统不支持 chmod；文件内容已经成功写入，继续让宿主读取。
  }
}

/**
 * 使用当前平台的系统命令打开 OAuth 授权页面。
 *
 * @param url - OAuth 授权地址
 */
export function openBrowser(url: string): void {
  if (process.platform === "darwin") {
    spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
  } else if (process.platform === "win32") {
    spawn("cmd", ["/c", "start", "", url], {
      detached: true,
      stdio: "ignore",
    }).unref();
  } else {
    spawn("xdg-open", [url], { detached: true, stdio: "ignore" }).unref();
  }
}

/**
 * 将二进制数据编码为无填充的 URL-safe Base64。
 *
 * @param buffer - 待编码的二进制数据
 * @returns Base64URL 文本
 */
export function base64url(buffer: Uint8Array): string {
  return Buffer.from(buffer)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

/**
 * 生成 OAuth PKCE verifier 与 SHA-256 challenge。
 *
 * @returns PKCE 参数
 */
export async function generatePKCE(): Promise<{
  challenge: string;
  verifier: string;
}> {
  const verifier = base64url(crypto.randomBytes(32));
  const challenge = base64url(
    crypto.createHash("sha256").update(verifier).digest(),
  );
  return { verifier, challenge };
}

/**
 * 生成 OAuth 成功后的本地回调页面。
 *
 * @param message - 展示给用户的后续提示
 * @returns 完整 HTML
 */
export function oauthSuccessHtml(message: string): string {
  return `<!doctype html><html><head><meta charset="utf-8"/><title>OK</title>
  <style>body{font-family:system-ui;display:flex;min-height:100vh;align-items:center;justify-content:center;background:#0b0b0c;color:#f5f5f5;margin:0}
  main{max-width:28rem;text-align:center;padding:2rem}h1{font-size:1.4rem}</style></head>
  <body><main><h1>Authentication successful</h1><p>${message}</p></main></body></html>`;
}

/**
 * 生成 OAuth 失败后的本地回调页面。
 *
 * @param message - 展示给用户的错误说明
 * @returns 完整 HTML
 */
export function oauthErrorHtml(message: string): string {
  return `<!doctype html><html><head><meta charset="utf-8"/><title>Failed</title>
  <style>body{font-family:system-ui;display:flex;min-height:100vh;align-items:center;justify-content:center;background:#0b0b0c;color:#f5f5f5;margin:0}
  main{max-width:28rem;text-align:center;padding:2rem}h1{font-size:1.4rem;color:#f87171}</style></head>
  <body><main><h1>Authentication failed</h1><p>${message}</p></main></body></html>`;
}

/**
 * 启动仅监听本机的 OAuth 回调服务。
 *
 * @param options - 回调端口、路径、状态校验与授权码字段
 * @returns 可等待授权码并关闭的服务句柄
 */
export function startCallbackServer(
  options: CallbackServerOptions,
): Promise<CallbackServer> {
  const { port, host, pathName, expectedState, codeParam = "code" } = options;
  return new Promise((resolve, reject) => {
    let settle!: (value: { code: string }) => void;
    const wait = new Promise<{ code: string }>((waitResolve) => {
      settle = waitResolve;
    });
    const server = http.createServer((request, response) => {
      try {
        const url = new URL(request.url || "", `http://${host}:${port}`);
        if (url.pathname !== pathName) {
          response.writeHead(404, {
            "Content-Type": "text/html; charset=utf-8",
          });
          response.end(oauthErrorHtml("Callback route not found."));
          return;
        }
        if (expectedState && url.searchParams.get("state") !== expectedState) {
          response.writeHead(400, {
            "Content-Type": "text/html; charset=utf-8",
          });
          response.end(oauthErrorHtml("State mismatch."));
          return;
        }
        const code = url.searchParams.get(codeParam);
        if (!code) {
          response.writeHead(400, {
            "Content-Type": "text/html; charset=utf-8",
          });
          response.end(oauthErrorHtml("Missing authorization code."));
          return;
        }
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        response.end(
          oauthSuccessHtml("You can close this window and return to WeiBei."),
        );
        settle({ code });
      } catch (error: unknown) {
        response.writeHead(500, { "Content-Type": "text/html; charset=utf-8" });
        response.end(oauthErrorHtml(errorMessage(error)));
      }
    });
    server.once("error", reject);
    server.listen(port, host, () => {
      resolve({
        waitForCode: () => wait,
        close: () =>
          new Promise<void>((closeResolve) => {
            server.close(() => closeResolve());
          }),
      });
    });
  });
}

/**
 * 通过 ChatGPT OAuth 获取 Pi 可消费的 OpenAI Codex 凭据。
 *
 * @returns OpenAI OAuth 凭据
 */
export async function loginOpenAICodex(): Promise<OAuthCredential> {
  const { verifier, challenge } = await generatePKCE();
  const state = crypto.randomBytes(16).toString("hex");
  const url = new URL(OPENAI_AUTHORIZE);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", OPENAI_CLIENT_ID);
  url.searchParams.set("redirect_uri", OPENAI_REDIRECT);
  url.searchParams.set("scope", OPENAI_SCOPE);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("state", state);
  url.searchParams.set("id_token_add_organizations", "true");
  url.searchParams.set("codex_cli_simplified_flow", "true");
  url.searchParams.set("originator", "weibei");

  const server = await startCallbackServer({
    port: 1455,
    host: "127.0.0.1",
    pathName: "/auth/callback",
    expectedState: state,
  });

  emit({ type: "auth_url", url: url.toString(), provider: "openai-codex" });
  openBrowser(url.toString());
  emit({ type: "progress", message: "Waiting for browser login…" });

  try {
    const { code } = await server.waitForCode();
    const body = new URLSearchParams({
      grant_type: "authorization_code",
      client_id: OPENAI_CLIENT_ID,
      code,
      code_verifier: verifier,
      redirect_uri: OPENAI_REDIRECT,
    });
    const response = await fetch(OPENAI_TOKEN, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(`Token exchange failed (${response.status}): ${text}`);
    }

    const json: unknown = await response.json();
    const access = stringProperty(json, "access_token");
    const refresh = stringProperty(json, "refresh_token");
    const expiresIn = isRecord(json) ? json.expires_in : undefined;
    if (!access || !refresh || typeof expiresIn !== "number") {
      throw new Error("Token response missing fields");
    }

    const tokenParts = access.split(".");
    if (!tokenParts[1])
      throw new Error("Failed to decode ChatGPT account id from token");
    const payload: unknown = JSON.parse(
      Buffer.from(tokenParts[1], "base64url").toString("utf8"),
    );
    const authClaim = isRecord(payload) ? payload[OPENAI_JWT_CLAIM] : undefined;
    const accountId = stringProperty(authClaim, "chatgpt_account_id");
    if (!accountId)
      throw new Error("Failed to extract ChatGPT account id from token");
    return {
      type: "oauth",
      access,
      refresh,
      expires: Date.now() + expiresIn * 1000,
      accountId,
    };
  } finally {
    await server.close();
  }
}

/**
 * 通过 Claude OAuth 获取 Pi 可消费的 Anthropic 凭据。
 *
 * @returns Anthropic OAuth 凭据
 */
export async function loginAnthropic(): Promise<OAuthCredential> {
  const { verifier, challenge } = await generatePKCE();
  const state = crypto.randomBytes(16).toString("hex");
  const url = new URL(ANTHROPIC_AUTHORIZE);
  url.searchParams.set("code", "true");
  url.searchParams.set("client_id", ANTHROPIC_CLIENT_ID);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("redirect_uri", ANTHROPIC_REDIRECT);
  url.searchParams.set("scope", ANTHROPIC_SCOPES);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("state", state);

  const server = await startCallbackServer({
    port: ANTHROPIC_PORT,
    host: "127.0.0.1",
    pathName: ANTHROPIC_PATH,
    expectedState: state,
  });

  emit({ type: "auth_url", url: url.toString(), provider: "anthropic" });
  openBrowser(url.toString());
  emit({ type: "progress", message: "Waiting for Claude login…" });

  try {
    const { code } = await server.waitForCode();
    const response = await fetch(ANTHROPIC_TOKEN, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        grant_type: "authorization_code",
        client_id: ANTHROPIC_CLIENT_ID,
        code,
        redirect_uri: ANTHROPIC_REDIRECT,
        code_verifier: verifier,
        state,
      }),
    });
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(
        `Anthropic token exchange failed (${response.status}): ${text}`,
      );
    }

    const json: unknown = await response.json();
    const access =
      stringProperty(json, "access_token") || stringProperty(json, "access");
    const refresh =
      stringProperty(json, "refresh_token") || stringProperty(json, "refresh");
    const rawExpiresIn = isRecord(json) ? (json.expires_in ?? 3600) : 3600;
    if (!access || !refresh)
      throw new Error("Anthropic token response missing fields");
    return {
      type: "oauth",
      access,
      refresh,
      expires: Date.now() + Number(rawExpiresIn) * 1000,
    };
  } finally {
    await server.close();
  }
}

/**
 * 将认证存储转换为宿主状态面板所需的摘要。
 *
 * @param data - Pi 认证存储
 * @returns 各 provider 的状态摘要
 */
export function buildProviderStatuses(data: AuthStore): ProviderStatus[] {
  return Object.entries(data).map(([id, value]) => {
    const credential = isRecord(value) ? value : {};
    return {
      id,
      type: credential.type || "unknown",
      expires: credential.expires || null,
      hasAccess: Boolean(credential.access || credential.key),
    };
  });
}

/**
 * 读取认证存储并向宿主输出状态摘要。
 *
 * @param authPath - auth.json 文件路径
 */
export function statusReport(authPath: string): void {
  emit({
    type: "status",
    authPath,
    providers: buildProviderStatuses(readAuth(authPath)),
  });
}

/**
 * 将命令行 provider 别名转换为认证存储键。
 *
 * @param provider - 命令行 provider
 * @returns 支持的存储键；不支持时返回 undefined
 */
export function normalizeProvider(
  provider: string,
): "anthropic" | "openai-codex" | undefined {
  if (provider === "openai-codex" || provider === "openai")
    return "openai-codex";
  if (provider === "anthropic" || provider === "claude") return "anthropic";
  return undefined;
}

/**
 * 执行一次 OAuth helper 命令。
 *
 * @param argv - 包含 node 与脚本路径的完整参数数组
 */
export async function main(
  argv: readonly string[] = process.argv,
): Promise<void> {
  const args = parseArgs(argv);
  if (args.status) {
    statusReport(args.authPath);
    return;
  }

  const provider = args.provider.trim();
  if (!provider) {
    emit({
      type: "error",
      message: "Missing --provider (openai-codex | anthropic)",
    });
    process.exitCode = 2;
    return;
  }

  emit({ type: "start", provider, authPath: args.authPath });

  const authKey = normalizeProvider(provider);
  if (!authKey) {
    emit({
      type: "error",
      message: `OAuth provider not wired yet: ${provider}. Supported: openai-codex, anthropic`,
    });
    process.exitCode = 2;
    return;
  }

  const credential =
    authKey === "openai-codex"
      ? await loginOpenAICodex()
      : await loginAnthropic();
  const data = readAuth(args.authPath);
  data[authKey] = credential;
  writeAuth(args.authPath, data);
  emit({ type: "success", provider: authKey, authPath: args.authPath });
}

/**
 * 判断当前模块是否由 Node 作为 CLI 入口直接执行。
 *
 * @param moduleUrl - 当前模块的 import.meta.url
 * @param argvEntry - Node 记录的入口脚本路径
 * @returns 当前模块是否为 CLI 入口
 */
export function isMainModule(
  moduleUrl: string,
  argvEntry: string | undefined = process.argv[1],
): boolean {
  if (!argvEntry || !moduleUrl.startsWith("file:")) return false;
  const modulePath = fileURLToPath(moduleUrl);
  const entryPath = path.resolve(argvEntry);
  try {
    return fs.realpathSync(modulePath) === fs.realpathSync(entryPath);
  } catch {
    return modulePath === entryPath;
  }
}

if (isMainModule(import.meta.url)) {
  void main().catch((error: unknown) => {
    emit({ type: "error", message: errorMessage(error) });
    process.exitCode = 1;
  });
}
