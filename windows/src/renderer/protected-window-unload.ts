export interface BeforeUnloadEventLike {
  returnValue: string;
  preventDefault(): void;
}

interface Options {
  hasEditorToProtect(): boolean;
  flushRecovery(): Promise<{ ok: boolean; release(): void }>;
  closeWindow(): void;
  scheduleCloseFallback(callback: () => void): void;
}

/** Keeps the window alive until the exact editor snapshot is durably recovered. */
export class ProtectedWindowUnloadGuard {
  private allowUnload = false;
  private flushPending = false;

  constructor(private readonly options: Options) {}

  handle(event: BeforeUnloadEventLike): void {
    if (this.allowUnload || !this.options.hasEditorToProtect()) return;
    event.preventDefault();
    event.returnValue = "";
    if (this.flushPending) return;
    this.flushPending = true;
    void this.options.flushRecovery().then((protection) => {
      this.flushPending = false;
      if (!protection.ok) {
        protection.release();
        return;
      }
      this.allowUnload = true;
      try {
        this.options.closeWindow();
      } catch {
        this.allowUnload = false;
        protection.release();
        return;
      }
      this.options.scheduleCloseFallback(() => {
        // A successfully closed renderer never runs this task. If close was
        // refused, restore editing and re-arm the guard instead of freezing it.
        this.allowUnload = false;
        protection.release();
      });
    }, () => {
      this.flushPending = false;
    });
  }
}
