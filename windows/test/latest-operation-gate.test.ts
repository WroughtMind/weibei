import assert from "node:assert/strict";
import test from "node:test";
import { ExclusiveOperationGate, LatestOperationGate } from "../src/shared/latest-operation-gate";

test("a stale openItem completion cannot replace the latest active item", () => {
  const gate = new LatestOperationGate();
  const firstTicket = gate.begin();
  const latestTicket = gate.begin();
  let activeItemId: string | null = null;

  // The second read finishes first and becomes active.
  if (gate.isLatest(latestTicket)) activeItemId = "note:b";
  // The first read arrives late and must not restore the previous selection.
  if (gate.isLatest(firstTicket)) activeItemId = "note:a";

  assert.equal(activeItemId, "note:b");
});

test("intent tickets are issued before async flush so an older slow flush cannot become latest", async () => {
  const gate = new LatestOperationGate();
  const firstFlush = deferred<void>();
  const latestFlush = deferred<void>();
  const mutations: string[] = [];

  const navigate = async (itemId: string, flush: Promise<void>) => {
    const ticket = gate.begin();
    await flush;
    if (gate.isLatest(ticket)) mutations.push(itemId);
  };
  const first = navigate("note:b", firstFlush.promise);
  const latest = navigate("note:c", latestFlush.promise);
  latestFlush.resolve();
  await latest;
  firstFlush.resolve();
  await first;

  assert.deepEqual(mutations, ["note:c"]);
});

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((next) => { resolve = next; });
  return { promise, resolve };
}

test("side-effectful snapshot mutations cannot overlap", () => {
  const gate = new ExclusiveOperationGate();
  const release = gate.tryBegin();
  assert.ok(release);
  assert.equal(gate.tryBegin(), null, "a second create/select/import cannot start its API side effect");
  release();
  const nextRelease = gate.tryBegin();
  assert.ok(nextRelease);
  nextRelease();
});
