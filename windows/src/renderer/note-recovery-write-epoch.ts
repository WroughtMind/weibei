/**
 * Invalidates delayed recovery work when an exact editor flush takes ownership.
 * A callback admitted before invalidation may finish, but the exact flush is
 * invoked afterwards and therefore remains the final serialized write.
 */
export class NoteRecoveryWriteEpochGate {
  private epoch = 0;

  capture(): number {
    return this.epoch;
  }

  invalidate(): number {
    this.epoch += 1;
    return this.epoch;
  }

  isCurrent(ticket: number): boolean {
    return ticket === this.epoch;
  }

  async runIfCurrent(ticket: number, operation: () => Promise<void>): Promise<boolean> {
    if (!this.isCurrent(ticket)) return false;
    await operation();
    return this.isCurrent(ticket);
  }
}
