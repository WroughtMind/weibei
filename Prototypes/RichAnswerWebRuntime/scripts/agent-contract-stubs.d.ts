// AgentResources 的本地类型声明（回退线）。
// Pi runtime（Bun 编译产物）不携带 .d.ts 类型文件；此处补齐 extension.ts /
// management-extension.ts / session-title.ts 实际引用的全部外部 API 签名，
// 供 tsconfig.agent.json（strict-lite：noImplicitAny 起步）做完整 tsc 检查。
// 签名保持宽松（any/unknown 为主），只覆盖引用面，不承担运行语义。

declare module "@earendil-works/pi-coding-agent" {
  export interface ExtensionAPI {
    registerTool(tool: any): void;
    on(event: string, handler: (event: any, context: any) => any): void;
    getSessionName(): string | undefined;
    setSessionName(name: string): void;
    registerCommand(
      name: string,
      command: {
        description: string;
        handler: (args: string, ctx: ExtensionCommandContext) => any;
      },
    ): void;
  }

  export interface ExtensionCommandContext {
    ui: {
      select(
        title: string,
        labels: string[],
        options?: { signal?: AbortSignal },
      ): Promise<string | undefined>;
      input(
        title: string,
        placeholder?: string,
        options?: { signal?: AbortSignal },
      ): Promise<string | undefined>;
      notify(payload: unknown, level?: string): void;
    };
  }

  export interface ExtensionContext {
    model: any;
    modelRegistry: {
      getApiKeyAndHeaders(model: any): Promise<{
        ok: boolean;
        apiKey?: string;
        headers?: Record<string, string>;
        env?: Record<string, string>;
      }>;
    };
  }
}

declare module "@earendil-works/pi-ai" {
  export const Type: any;
  export function uuidv7(): string;
  export type AuthType = string;
  export interface AuthPrompt {
    type: string;
    message?: string;
    options?: { label: string; id: string }[];
    placeholder?: string;
    signal?: AbortSignal;
  }
  export interface AuthEvent {
    [key: string]: any;
  }
  export interface AuthInteraction {
    prompt(prompt: AuthPrompt): Promise<string>;
    notify(event: AuthEvent): void;
  }
}

declare module "@earendil-works/pi-ai/compat" {
  export function completeSimple(...args: any[]): Promise<any>;
}

declare module "node:child_process" {
  export const spawn: any;
}

declare module "node:crypto" {
  export const createHash: any;
}

declare module "node:fs" {
  export const constants: any;
  export const realpathSync: any;
}

declare module "node:fs/promises" {
  export const lstat: any;
  export const open: any;
  export const readFile: any;
  export const realpath: any;
  export const unlink: any;
}

declare module "node:path" {
  export const isAbsolute: any;
  export const resolve: any;
}

declare module "node:timers/promises" {
  export const setTimeout: any;
}

declare module "node:url" {
  export const fileURLToPath: any;
}

type Buffer = any;
declare const Buffer: any;
declare const process: any;

declare namespace NodeJS {
  interface ErrnoException extends Error {
    code?: string;
  }
}
