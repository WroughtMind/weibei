import assert from "node:assert/strict";
import test from "node:test";
import { SnapshotPublicationGate } from "../src/main/snapshot-publication-gate";

test("a snapshot captured before a mutation cannot publish after the mutation", async () => {
  const gate = new SnapshotPublicationGate();
  const watcherGeneration = await gate.captureWhenIdle();
  const finishMutation = gate.beginMutation();

  finishMutation();
  assert.equal(gate.isCurrent(watcherGeneration), false);
  assert.equal(gate.isCurrent(await gate.captureWhenIdle()), true);
});

test("watcher capture waits for every overlapping mutation", async () => {
  const gate = new SnapshotPublicationGate();
  const finishFirst = gate.beginMutation();
  const capture = gate.captureWhenIdle();
  let captured = false;
  void capture.then(() => { captured = true; });

  const finishSecond = gate.beginMutation();
  finishFirst();
  await Promise.resolve();
  assert.equal(captured, false, "one remaining mutation must keep publication paused");

  finishSecond();
  const generation = await capture;
  assert.equal(captured, true);
  assert.equal(gate.isCurrent(generation), true);
});

test("a mutation beginning after an idle waiter resolves still invalidates its ticket", async () => {
  const gate = new SnapshotPublicationGate();
  const finishFirst = gate.beginMutation();
  const capture = gate.captureWhenIdle();
  finishFirst();

  const finishSecond = gate.beginMutation();
  const generation = await capture;
  assert.equal(gate.isCurrent(generation), false);
  finishSecond();
  assert.equal(gate.isCurrent(await gate.captureWhenIdle()), true);
});

test("agent-owned persisted events invalidate an in-flight watcher snapshot", async () => {
  const gate = new SnapshotPublicationGate();
  const watcherGeneration = await gate.captureWhenIdle();

  gate.invalidate();
  assert.equal(gate.isCurrent(watcherGeneration), false);
});

test("ending a mutation lease is idempotent", async () => {
  const gate = new SnapshotPublicationGate();
  const finish = gate.beginMutation();
  const capture = gate.captureWhenIdle();

  finish();
  finish();
  assert.equal(gate.isCurrent(await capture), true);
});

test("a delayed watcher read retries and returns post-mutation state", async () => {
  const gate = new SnapshotPublicationGate();
  const firstReadStarted = deferred<void>();
  const releaseFirstRead = deferred<void>();
  let state = "old selection";
  let reads = 0;

  const published = readFresh(gate, async () => {
    reads += 1;
    const captured = state;
    if (reads === 1) {
      firstReadStarted.resolve();
      await releaseFirstRead.promise;
    }
    return captured;
  });
  await firstReadStarted.promise;

  const finishMutation = gate.beginMutation();
  state = "new selection";
  finishMutation();
  releaseFirstRead.resolve();

  assert.equal(await published, "new selection");
  assert.equal(reads, 2, "the pre-mutation snapshot must be rebuilt, not published");
});

test("an explicit snapshot retries a terminal event while holding its own mutation lease", async () => {
  const gate = new SnapshotPublicationGate();
  const finishOwnMutation = gate.beginMutation();
  const firstReadStarted = deferred<void>();
  const releaseFirstRead = deferred<void>();
  let sessionState = "generating";
  let reads = 0;

  const snapshot = readGenerationStable(gate, async () => {
    reads += 1;
    const captured = sessionState;
    if (reads === 1) {
      firstReadStarted.resolve();
      await releaseFirstRead.promise;
    }
    return captured;
  });
  await firstReadStarted.promise;

  sessionState = "completed";
  gate.invalidate();
  releaseFirstRead.resolve();

  assert.equal(await snapshot, "completed");
  assert.equal(reads, 2);
  finishOwnMutation();
});

async function readFresh<T>(gate: SnapshotPublicationGate, read: () => Promise<T>): Promise<T> {
  for (;;) {
    const generation = await gate.captureWhenIdle();
    const value = await read();
    if (gate.isCurrent(generation)) return value;
  }
}

async function readGenerationStable<T>(
  gate: SnapshotPublicationGate,
  read: () => Promise<T>,
): Promise<T> {
  for (;;) {
    const generation = gate.captureGeneration();
    const value = await read();
    if (gate.isGenerationCurrent(generation)) return value;
  }
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((next) => { resolve = next; });
  return { promise, resolve };
}
