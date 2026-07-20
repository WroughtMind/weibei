#!/usr/bin/env node
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
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function parseArgs(argv) {
  const out = { provider: "", authPath: "", status: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--status") out.status = true;
    else if (a === "--provider") out.provider = argv[++i] || "";
    else if (a === "--auth-path") out.authPath = argv[++i] || "";
  }
  if (!out.authPath) {
    out.authPath = path.join(os.homedir(), ".pi", "agent", "auth.json");
  }
  return out;
}

function readAuth(authPath) {
  try {
    const raw = fs.readFileSync(authPath, "utf8");
    const json = JSON.parse(raw);
    return json && typeof json === "object" ? json : {};
  } catch {
    return {};
  }
}

function writeAuth(authPath, data) {
  fs.mkdirSync(path.dirname(authPath), { recursive: true, mode: 0o700 });
  fs.writeFileSync(authPath, JSON.stringify(data, null, 2) + "\n", { mode: 0o600 });
  try {
    fs.chmodSync(authPath, 0o600);
  } catch {
    // ignore
  }
}

function openBrowser(url) {
  const platform = process.platform;
  if (platform === "darwin") spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
  else if (platform === "win32") spawn("cmd", ["/c", "start", "", url], { detached: true, stdio: "ignore" }).unref();
  else spawn("xdg-open", [url], { detached: true, stdio: "ignore" }).unref();
}

function base64url(buf) {
  return Buffer.from(buf)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

async function generatePKCE() {
  const verifier = base64url(crypto.randomBytes(32));
  const challenge = base64url(crypto.createHash("sha256").update(verifier).digest());
  return { verifier, challenge };
}

function oauthSuccessHtml(message) {
  return `<!doctype html><html><head><meta charset="utf-8"/><title>OK</title>
  <style>body{font-family:system-ui;display:flex;min-height:100vh;align-items:center;justify-content:center;background:#0b0b0c;color:#f5f5f5;margin:0}
  main{max-width:28rem;text-align:center;padding:2rem}h1{font-size:1.4rem}</style></head>
  <body><main><h1>Authentication successful</h1><p>${message}</p></main></body></html>`;
}

function oauthErrorHtml(message) {
  return `<!doctype html><html><head><meta charset="utf-8"/><title>Failed</title>
  <style>body{font-family:system-ui;display:flex;min-height:100vh;align-items:center;justify-content:center;background:#0b0b0c;color:#f5f5f5;margin:0}
  main{max-width:28rem;text-align:center;padding:2rem}h1{font-size:1.4rem;color:#f87171}</style></head>
  <body><main><h1>Authentication failed</h1><p>${message}</p></main></body></html>`;
}

function startCallbackServer({ port, host, pathName, expectedState, codeParam = "code" }) {
  return new Promise((resolve, reject) => {
    let settle;
    const wait = new Promise((res) => {
      settle = res;
    });
    const server = http.createServer((req, res) => {
      try {
        const url = new URL(req.url || "", `http://${host}:${port}`);
        if (url.pathname !== pathName) {
          res.writeHead(404, { "Content-Type": "text/html; charset=utf-8" });
          res.end(oauthErrorHtml("Callback route not found."));
          return;
        }
        if (expectedState && url.searchParams.get("state") !== expectedState) {
          res.writeHead(400, { "Content-Type": "text/html; charset=utf-8" });
          res.end(oauthErrorHtml("State mismatch."));
          return;
        }
        const code = url.searchParams.get(codeParam);
        if (!code) {
          res.writeHead(400, { "Content-Type": "text/html; charset=utf-8" });
          res.end(oauthErrorHtml("Missing authorization code."));
          return;
        }
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        res.end(oauthSuccessHtml("You can close this window and return to WeiBei."));
        settle({ code });
      } catch (error) {
        res.writeHead(500, { "Content-Type": "text/html; charset=utf-8" });
        res.end(oauthErrorHtml(String(error?.message || error)));
      }
    });
    server.once("error", reject);
    server.listen(port, host, () => {
      resolve({
        waitForCode: () => wait,
        close: () =>
          new Promise((res) => {
            server.close(() => res());
          }),
      });
    });
  });
}

// --- OpenAI Codex (ChatGPT Plus/Pro) — same as Pi /login openai-codex ---
const OPENAI_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const OPENAI_AUTH_BASE = "https://auth.openai.com";
const OPENAI_AUTHORIZE = `${OPENAI_AUTH_BASE}/oauth/authorize`;
const OPENAI_TOKEN = `${OPENAI_AUTH_BASE}/oauth/token`;
const OPENAI_REDIRECT = "http://localhost:1455/auth/callback";
const OPENAI_SCOPE = "openid profile email offline_access";
const OPENAI_JWT_CLAIM = "https://api.openai.com/auth";

async function loginOpenAICodex() {
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
    const json = await response.json();
    if (!json?.access_token || !json.refresh_token || typeof json.expires_in !== "number") {
      throw new Error("Token response missing fields");
    }
    const parts = String(json.access_token).split(".");
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    const accountId = payload?.[OPENAI_JWT_CLAIM]?.chatgpt_account_id;
    if (!accountId) throw new Error("Failed to extract ChatGPT account id from token");
    return {
      type: "oauth",
      access: json.access_token,
      refresh: json.refresh_token,
      expires: Date.now() + json.expires_in * 1000,
      accountId,
    };
  } finally {
    await server.close();
  }
}

// --- Anthropic Claude Pro/Max — same ports/constants as Pi ---
const ANTHROPIC_CLIENT_ID = Buffer.from("OWQxYzI1MGEtZTYxYi00NGQ5LTg4ZWQtNTk0NGQxOTYyZjVl", "base64").toString("utf8");
const ANTHROPIC_AUTHORIZE = "https://claude.ai/oauth/authorize";
const ANTHROPIC_TOKEN = "https://platform.claude.com/v1/oauth/token";
const ANTHROPIC_PORT = 53692;
const ANTHROPIC_PATH = "/callback";
const ANTHROPIC_REDIRECT = `http://localhost:${ANTHROPIC_PORT}${ANTHROPIC_PATH}`;
const ANTHROPIC_SCOPES =
  "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload";

async function loginAnthropic() {
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
      throw new Error(`Anthropic token exchange failed (${response.status}): ${text}`);
    }
    const json = await response.json();
    const access = json.access_token || json.access;
    const refresh = json.refresh_token || json.refresh;
    const expiresIn = json.expires_in ?? 3600;
    if (!access || !refresh) throw new Error("Anthropic token response missing fields");
    return {
      type: "oauth",
      access,
      refresh,
      expires: Date.now() + Number(expiresIn) * 1000,
    };
  } finally {
    await server.close();
  }
}

function statusReport(authPath) {
  const data = readAuth(authPath);
  const providers = Object.entries(data).map(([id, value]) => ({
    id,
    type: value?.type || "unknown",
    expires: value?.expires || null,
    hasAccess: Boolean(value?.access || value?.key),
  }));
  emit({ type: "status", authPath, providers });
}

async function main() {
  const args = parseArgs(process.argv);
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

  let credential;
  if (provider === "openai-codex" || provider === "openai") {
    credential = await loginOpenAICodex();
  } else if (provider === "anthropic" || provider === "claude") {
    credential = await loginAnthropic();
  } else {
    emit({
      type: "error",
      message: `OAuth provider not wired yet: ${provider}. Supported: openai-codex, anthropic`,
    });
    process.exitCode = 2;
    return;
  }

  const authKey = provider === "openai" ? "openai-codex" : provider === "claude" ? "anthropic" : provider;
  const data = readAuth(args.authPath);
  data[authKey] = credential;
  writeAuth(args.authPath, data);
  emit({ type: "success", provider: authKey, authPath: args.authPath });
}

main().catch((error) => {
  emit({ type: "error", message: error?.message || String(error) });
  process.exitCode = 1;
});
