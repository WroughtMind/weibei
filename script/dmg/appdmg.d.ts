declare module "appdmg" {
  interface AppDMGEmitter {
    on(event: string, listener: (...args: any[]) => void): this;
  }
  interface AppDMGOptions {
    target: string;
    basepath: string;
    specification: Record<string, any>;
  }
  const appdmg: (options: AppDMGOptions) => AppDMGEmitter;
  export default appdmg;
}
