/** Issues monotonically increasing tickets and rejects stale async completions. */
export class LatestOperationGate {
  private sequence = 0;

  begin(): number {
    this.sequence += 1;
    return this.sequence;
  }

  isLatest(ticket: number): boolean {
    return ticket === this.sequence;
  }
}

/** Rejects overlapping side-effectful operations until the owner releases. */
export class ExclusiveOperationGate {
  private active = false;

  tryBegin(): (() => void) | null {
    if (this.active) return null;
    this.active = true;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.active = false;
    };
  }
}
