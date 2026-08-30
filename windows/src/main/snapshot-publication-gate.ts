/**
 * Prevents a full AppSnapshot which started before a mutation from being
 * published after that mutation. Mutations may overlap; publication resumes
 * only once every mutation lease has ended.
 */
export class SnapshotPublicationGate {
  private generation = 0;
  private activeMutations = 0;
  private readonly idleWaiters: Array<(generation: number) => void> = [];

  beginMutation(): () => void {
    this.generation += 1;
    this.activeMutations += 1;
    let ended = false;
    return () => {
      if (ended) return;
      ended = true;
      this.activeMutations = Math.max(0, this.activeMutations - 1);
      if (this.activeMutations !== 0) return;
      const generation = this.generation;
      for (const resolve of this.idleWaiters.splice(0)) resolve(generation);
    };
  }

  /** Invalidates in-flight snapshots for mutations completed by another owner. */
  invalidate(): void {
    this.generation += 1;
  }

  captureWhenIdle(): Promise<number> {
    if (this.activeMutations === 0) return Promise.resolve(this.generation);
    return new Promise((resolve) => this.idleWaiters.push(resolve));
  }

  /** Capture an epoch even inside the caller's own active mutation lease. */
  captureGeneration(): number {
    return this.generation;
  }

  /** Compare epochs without requiring all mutation leases to have ended. */
  isGenerationCurrent(generation: number): boolean {
    return generation === this.generation;
  }

  isCurrent(generation: number): boolean {
    return this.activeMutations === 0 && this.isGenerationCurrent(generation);
  }
}
