import assert from "node:assert/strict";
import test from "node:test";
import { NoteRecoveryWriteEpochGate } from "../src/renderer/note-recovery-write-epoch";

test("an exact flush invalidates an older delayed recovery before it invokes IPC", async () => {
  const gate = new NoteRecoveryWriteEpochGate();
  const delayedTicket = gate.capture();
  const calls: string[] = [];

  gate.invalidate();
  calls.push("exact-B");
  const current = await gate.runIfCurrent(delayedTicket, async () => {
    calls.push("stale-A");
  });

  assert.equal(current, false);
  assert.deepEqual(calls, ["exact-B"]);
});

test("a delayed write already invoked before invalidation stays ordered before the exact flush", async () => {
  const gate = new NoteRecoveryWriteEpochGate();
  const delayedTicket = gate.capture();
  const calls: string[] = [];
  let finishDelayed!: () => void;
  const delayedCompletion = new Promise<void>((resolve) => { finishDelayed = resolve; });

  const delayed = gate.runIfCurrent(delayedTicket, async () => {
    calls.push("invoke-A");
    await delayedCompletion;
  });
  await Promise.resolve();

  gate.invalidate();
  calls.push("invoke-exact-B");
  finishDelayed();

  assert.equal(await delayed, false);
  assert.deepEqual(calls, ["invoke-A", "invoke-exact-B"]);
});

test("current background recovery work still runs normally", async () => {
  const gate = new NoteRecoveryWriteEpochGate();
  let calls = 0;
  const current = await gate.runIfCurrent(gate.capture(), async () => { calls += 1; });

  assert.equal(current, true);
  assert.equal(calls, 1);
});
