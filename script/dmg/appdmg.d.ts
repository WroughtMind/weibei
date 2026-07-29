declare module "appdmg" {
  interface ProgressEvent {
    type?: string;
    status?: string;
    title?: string;
  }

  interface Emitter {
    on(event: "progress", listener: (event: ProgressEvent) => void): Emitter;
    on(event: "finish", listener: () => void): Emitter;
    on(event: "error", listener: (error: Error) => void): Emitter;
  }

  interface Configuration {
    target: string;
    basepath: string;
    specification: {
      title: string;
      icon: string;
      background: string;
      "icon-size": number;
      format: string;
      filesystem: string;
      window: {
        position: { x: number; y: number };
        size: { width: number; height: number };
      };
      contents: Array<{
        x: number;
        y: number;
        type: "file" | "link";
        path: string;
        name: string;
      }>;
    };
  }

  export default function appdmg(configuration: Configuration): Emitter;
}
