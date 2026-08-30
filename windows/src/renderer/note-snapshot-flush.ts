export interface NoteEditorSnapshot {
  requestID: string;
  documentID: string;
  documentGeneration: number;
  revision: number;
  markdown: string;
}

interface Options {
  createRequestID(): string;
  requestSnapshot(requestID: string): {
    commandID: string;
    documentID: string;
    documentGeneration: number;
    minimumRevision: number;
  };
  onSnapshot(snapshot: NoteEditorSnapshot): void;
}

type PendingSnapshot = ReturnType<Options["requestSnapshot"]> & { requestID: string };

/** Reference-counted so overlapping transitions cannot unfreeze each other. */
export class NoteEditorFreezeGate {
  private depth = 0;

  constructor(private readonly setEditable: (editable: boolean) => void) {}

  get isFrozen(): boolean {
    return this.depth > 0;
  }

  acquire(): () => void {
    this.depth += 1;
    if (this.depth === 1) {
      try {
        this.setEditable(false);
      } catch (error) {
        this.depth = 0;
        throw error;
      }
    }
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.depth = Math.max(0, this.depth - 1);
      if (this.depth === 0) this.setEditable(true);
    };
  }

  dispose(): void {
    this.depth = 0;
  }
}

/** Releases frozen editors only after React has committed the unmount. */
export class PostCommitReleaseQueue {
  private readonly releases: Array<() => void> = [];

  enqueue(release: () => void): void {
    this.releases.push(release);
  }

  drain(): void {
    for (const release of this.releases.splice(0)) release();
  }
}

/**
 * Coalesces normal dirty snapshots, while making an explicit flush wait for a
 * request issued after any snapshot which was already in flight.
 */
export class NoteSnapshotFlushCoordinator {
  private pending: PendingSnapshot | null = null;
  private requestAfterPending = false;
  private readonly waiters: Array<{
    resolve(snapshot: NoteEditorSnapshot): void;
    reject(error: Error): void;
  }> = [];

  constructor(private readonly options: Options) {}

  markDirty(): void {
    if (this.pending) {
      this.requestAfterPending = true;
      return;
    }
    this.startRequest();
  }

  flush(): Promise<NoteEditorSnapshot> {
    const promise = new Promise<NoteEditorSnapshot>((resolve, reject) => {
      this.waiters.push({ resolve, reject });
    });
    if (this.pending) {
      // The in-flight request may have been dispatched before the latest
      // keystroke. Always follow it with one more ordered snapshot.
      this.requestAfterPending = true;
    } else {
      this.startRequest();
    }
    return promise;
  }

  accept(snapshot: NoteEditorSnapshot): boolean {
    const pending = this.pending;
    if (!pending || snapshot.requestID !== pending.requestID) return false;
    if (snapshot.documentID !== pending.documentID
        || snapshot.documentGeneration !== pending.documentGeneration
        || snapshot.revision < pending.minimumRevision) {
      this.pending = null;
      this.requestAfterPending = false;
      this.startRequest();
      return false;
    }
    this.pending = null;
    this.options.onSnapshot(snapshot);
    if (this.requestAfterPending) {
      this.requestAfterPending = false;
      this.startRequest();
      return true;
    }
    for (const waiter of this.waiters.splice(0)) waiter.resolve(snapshot);
    return true;
  }

  rejectPending(error: Error): void {
    this.pending = null;
    this.requestAfterPending = false;
    for (const waiter of this.waiters.splice(0)) waiter.reject(error);
  }

  rejectCommand(commandID: string, error: Error): boolean {
    if (!this.pending || this.pending.commandID !== commandID) return false;
    this.rejectPending(error);
    return true;
  }

  private startRequest(): void {
    const requestID = this.options.createRequestID();
    try {
      this.pending = { requestID, ...this.options.requestSnapshot(requestID) };
    } catch (error) {
      this.rejectPending(error instanceof Error ? error : new Error(String(error)));
    }
  }
}
