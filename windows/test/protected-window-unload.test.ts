import assert from "node:assert/strict";
import test from "node:test";
import { ProtectedWindowUnloadGuard } from "../src/renderer/protected-window-unload";

test("beforeunload remains cancelled until recovery flush succeeds, then closes once", async () => {
  let resolveFlush!: (value: { ok: boolean; release(): void }) => void;
  let flushCalls = 0;
  let closeCalls = 0;
  let releaseCalls = 0;
  let closeFallback: (() => void) | null = null;
  const guard = new ProtectedWindowUnloadGuard({
    hasEditorToProtect: () => true,
    flushRecovery: () => {
      flushCalls += 1;
      return new Promise((resolve) => { resolveFlush = resolve; });
    },
    closeWindow: () => { closeCalls += 1; },
    scheduleCloseFallback: (callback) => { closeFallback = callback; },
  });
  const first = eventRig();
  guard.handle(first.event);
  guard.handle(eventRig().event);
  assert.equal(first.prevented(), true);
  assert.equal(flushCalls, 1, "a repeated close gesture must share the pending flush");
  assert.equal(closeCalls, 0);

  resolveFlush({ ok: true, release: () => { releaseCalls += 1; } });
  await Promise.resolve();
  assert.equal(closeCalls, 1);
  const allowed = eventRig();
  guard.handle(allowed.event);
  assert.equal(allowed.prevented(), false, "the guarded second close is allowed after durable recovery");
  assert.equal(releaseCalls, 0, "the editor remains frozen while close is being attempted");
  assert.ok(closeFallback);
  (closeFallback as () => void)();
  assert.equal(releaseCalls, 1, "a refused close restores editing instead of freezing forever");
});

test("a failed recovery keeps unload blocked and permits a later retry", async () => {
  let attempt = 0;
  let closeCalls = 0;
  const guard = new ProtectedWindowUnloadGuard({
    hasEditorToProtect: () => true,
    flushRecovery: async () => ({ ok: ++attempt > 1, release: () => undefined }),
    closeWindow: () => { closeCalls += 1; },
    scheduleCloseFallback: () => undefined,
  });
  const first = eventRig();
  guard.handle(first.event);
  await Promise.resolve();
  assert.equal(first.prevented(), true);
  assert.equal(closeCalls, 0);

  guard.handle(eventRig().event);
  await Promise.resolve();
  assert.equal(attempt, 2);
  assert.equal(closeCalls, 1);
});

function eventRig() {
  let wasPrevented = false;
  return {
    event: {
      returnValue: "unchanged",
      preventDefault: () => { wasPrevented = true; },
    },
    prevented: () => wasPrevented,
  };
}
