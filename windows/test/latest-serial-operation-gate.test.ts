import assert from "node:assert/strict";
import test from "node:test";
import { LatestSerialOperationGate } from "../src/shared/latest-serial-operation-gate";

test("a newer library intent wins while root mutations stay serialized", async () => {
  const gate = new LatestSerialOperationGate();
  const firstStarted = deferred<void>();
  const releaseFirst = deferred<void>();
  const entered: string[] = [];
  let libraryRoot = "original";

  const firstTicket = gate.begin();
  const first = gate.run(async () => {
    entered.push("first");
    firstStarted.resolve();
    await releaseFirst.promise;
    if (gate.isLatest(firstTicket)) libraryRoot = "first";
  });
  await firstStarted.promise;

  const latestTicket = gate.begin();
  const latest = gate.run(async () => {
    entered.push("latest");
    if (gate.isLatest(latestTicket)) libraryRoot = "latest";
  });

  assert.deepEqual(entered, ["first"]);
  releaseFirst.resolve();
  await Promise.all([first, latest]);

  assert.deepEqual(entered, ["first", "latest"]);
  assert.equal(libraryRoot, "latest");
});

test("an old watcher snapshot is discarded after a newer course selection", async () => {
  const gate = new LatestSerialOperationGate();
  const watcherStarted = deferred<void>();
  const releaseWatcher = deferred<void>();
  const published: string[] = [];
  let activeCourse = "course:old";

  const watcherTicket = gate.capture();
  const watcher = gate.run(async () => {
    watcherStarted.resolve();
    await releaseWatcher.promise;
    if (gate.isLatest(watcherTicket)) published.push(activeCourse);
  });
  await watcherStarted.promise;

  const selectionTicket = gate.begin();
  const selection = gate.run(async () => {
    if (gate.isLatest(selectionTicket)) activeCourse = "course:new";
  });

  releaseWatcher.resolve();
  await Promise.all([watcher, selection]);

  assert.deepEqual(published, []);
  assert.equal(activeCourse, "course:new");
});

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((next) => {
    resolve = next;
  });
  return { promise, resolve };
}
