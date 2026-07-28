import { describe, expect, it } from "vitest";

import {
  base64url,
  buildProviderStatuses,
  isMainModule,
  normalizeProvider,
  parseArgs,
} from "../../tooling/pi-oauth-login.js";

describe("Pi OAuth CLI 参数", () => {
  it("解析 provider、认证路径和状态模式", () => {
    expect(
      parseArgs([
        "node",
        "pi-oauth-login.mjs",
        "--provider",
        "openai-codex",
        "--auth-path",
        "/tmp/weibei-auth.json",
        "--status",
      ]),
    ).toEqual({
      provider: "openai-codex",
      authPath: "/tmp/weibei-auth.json",
      status: true,
    });
  });

  it("保留缺失参数值时的空字符串语义", () => {
    const args = parseArgs(["node", "pi-oauth-login.mjs", "--provider"]);

    expect(args.provider).toBe("");
    expect(args.authPath).toMatch(/\.pi\/agent\/auth\.json$/);
  });
});

describe("Pi OAuth 纯逻辑", () => {
  it("生成无填充的 URL-safe Base64", () => {
    expect(base64url(Uint8Array.from([251, 255, 239]))).toBe("-__v");
  });

  it("规范支持的 provider 别名", () => {
    expect(normalizeProvider("openai")).toBe("openai-codex");
    expect(normalizeProvider("claude")).toBe("anthropic");
    expect(normalizeProvider("unsupported")).toBeUndefined();
  });

  it("生成不暴露访问凭据的状态摘要", () => {
    expect(
      buildProviderStatuses({
        "openai-codex": { type: "oauth", access: "secret", expires: 123 },
        anthropic: { type: "oauth", refresh: "refresh-only" },
        malformed: "value",
      }),
    ).toEqual([
      { id: "openai-codex", type: "oauth", expires: 123, hasAccess: true },
      { id: "anthropic", type: "oauth", expires: null, hasAccess: false },
      { id: "malformed", type: "unknown", expires: null, hasAccess: false },
    ]);
  });

  it("被测试导入时不会判定为 CLI 入口", () => {
    expect(isMainModule(import.meta.url, "/tmp/pi-oauth-login.mjs")).toBe(
      false,
    );
  });
});
