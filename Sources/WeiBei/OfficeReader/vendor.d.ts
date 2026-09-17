declare module 'rtf.js/dist/WMFJS.bundle.js' {
  export function loggingEnabled(enabled: boolean): void;
  export class Renderer {
    constructor(bytes: Uint8Array);
    render(options: {width: string; height: string; xExt: number; yExt: number; mapMode: number}): SVGElement;
  }
}

// Version-pinned entry points exposed by vendor-patches.mjs, shared with the PPT reader.
declare module 'weibei-pptx-drawing' {
  export const officeDrawing: {
    xml(source: string): any;
    rels(source: string): Map<string, {type: string; target: string; targetMode?: string}>;
    theme(xml: any): any;
    context(presentation: any, slide: any, mediaURLs: Map<string, string>, charts: Set<any>): any;
    node(xml: any, context: any): any;
    render(node: any, context: any): HTMLElement;
  };
}
declare module 'weibei-office-chart-parser' {
  import type { ChartModel } from '@silurus/ooxml/docx';
  export function parseOfficeCharts(bytes: Uint8Array): { slides: { elements: { type: string; id?: string; chart?: ChartModel }[] }[] };
}
