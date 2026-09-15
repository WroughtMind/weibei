declare module 'rtf.js/dist/WMFJS.bundle.js' {
  export function loggingEnabled(enabled: boolean): void;
  export class Renderer {
    constructor(bytes: Uint8Array);
    render(options: {width: string; height: string; xExt: number; yExt: number; mapMode: number}): SVGElement;
  }
}
