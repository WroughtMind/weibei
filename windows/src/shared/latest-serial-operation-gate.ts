/** Serializes async work while tracking which user intent is still current. */
export class LatestSerialOperationGate {
  private sequence = 0;
  private tail: Promise<void> = Promise.resolve();

  begin(): number {
    this.sequence += 1;
    return this.sequence;
  }

  capture(): number {
    return this.sequence;
  }

  isLatest(ticket: number): boolean {
    return ticket === this.sequence;
  }

  run<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.tail.then(operation, operation);
    this.tail = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }
}
