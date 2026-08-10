declare module "@earendil-works/pi-coding-agent" {
  export interface ExtensionAPI {
    registerTool(tool: any): void;
    on(event: string, handler: (event: any, context: any) => any): void;
  }
}

declare module "@earendil-works/pi-ai" {
  export const Type: any;
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
