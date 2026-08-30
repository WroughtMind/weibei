import assert from "node:assert/strict";
import test from "node:test";
import {
  NoteEditorFreezeGate,
  NoteSnapshotFlushCoordinator,
  PostCommitReleaseQueue,
  type NoteEditorSnapshot,
} from "../src/renderer/note-snapshot-flush";

test("flush waits past an already pending snapshot and returns the latest editor body", async () => {
  const requests: string[] = [];
  const observed: string[] = [];
  let nextID = 0;
  const coordinator = new NoteSnapshotFlushCoordinator({
    createRequestID: () => `request-${++nextID}`,
    requestSnapshot: (requestID) => {
      requests.push(requestID);
      return expectation(requestID, 1);
    },
    onSnapshot: (snapshot) => observed.push(snapshot.markdown),
  });

  coordinator.markDirty();
  assert.deepEqual(requests, ["request-1"]);
  const flush = coordinator.flush();
  let settled = false;
  void flush.then(() => { settled = true; });

  coordinator.accept(receipt("request-1", "first snapshot may predate the last keystroke"));
  await Promise.resolve();
  assert.equal(settled, false);
  assert.deepEqual(requests, ["request-1", "request-2"]);

  coordinator.accept(receipt("request-2", "latest text typed before navigation"));
  assert.equal((await flush).markdown, "latest text typed before navigation");
  assert.deepEqual(observed, [
    "first snapshot may predate the last keystroke",
    "latest text typed before navigation",
  ]);
});

test("the editor stays frozen through recovery and overlapping transitions", () => {
  const editableStates: boolean[] = [];
  const freezeGate = new NoteEditorFreezeGate((editable) => editableStates.push(editable));
  const releaseFirst = freezeGate.acquire();
  const releaseSecond = freezeGate.acquire();
  assert.equal(freezeGate.isFrozen, true);
  assert.deepEqual(editableStates, [false]);

  // The first recovery IPC completed, but a newer transition still owns a
  // lease, so the older completion cannot reopen the editor.
  releaseFirst();
  assert.equal(freezeGate.isFrozen, true);
  assert.deepEqual(editableStates, [false]);
  releaseSecond();
  assert.equal(freezeGate.isFrozen, false);
  assert.deepEqual(editableStates, [false, true]);
});

test("a navigation release runs only at the post-commit boundary", () => {
  const queue = new PostCommitReleaseQueue();
  let released = false;
  queue.enqueue(() => { released = true; });
  assert.equal(released, false, "setSnapshot must not reopen the old editor before React unmounts it");
  queue.drain();
  assert.equal(released, true);
});

test("a mismatched response cannot release navigation", async () => {
  const requests: string[] = [];
  const coordinator = new NoteSnapshotFlushCoordinator({
    createRequestID: () => "expected-request",
    requestSnapshot: (requestID) => {
      requests.push(requestID);
      return expectation(requestID, 1);
    },
    onSnapshot: () => undefined,
  });
  const flush = coordinator.flush();
  let settled = false;
  void flush.then(() => { settled = true; });
  assert.equal(coordinator.accept(receipt("wrong-request", "wrong body")), false);
  await Promise.resolve();
  assert.equal(settled, false);
  assert.equal(coordinator.accept(receipt("expected-request", "exact body")), true);
  assert.equal((await flush).markdown, "exact body");
  assert.deepEqual(requests, ["expected-request"]);
});

test("a rejected pending snapshot fails closed instead of releasing navigation", async () => {
  let navigationRan = false;
  const coordinator = new NoteSnapshotFlushCoordinator({
    createRequestID: () => "request-1",
    requestSnapshot: (requestID) => expectation(requestID, 1),
    onSnapshot: () => undefined,
  });
  const flush = coordinator.flush().then(() => { navigationRan = true; });
  coordinator.rejectPending(new Error("frame unavailable"));
  await assert.rejects(flush, /frame unavailable/u);
  assert.equal(navigationRan, false);
});

test("a matching response below minimumRevision is retried and cannot release flush", async () => {
  let nextID = 0;
  const requests: string[] = [];
  const coordinator = new NoteSnapshotFlushCoordinator({
    createRequestID: () => `request-${++nextID}`,
    requestSnapshot: (requestID) => {
      requests.push(requestID);
      return expectation(requestID, 3);
    },
    onSnapshot: () => undefined,
  });
  const flush = coordinator.flush();
  assert.equal(coordinator.accept({ ...receipt("request-1", "stale"), revision: 2 }), false);
  assert.deepEqual(requests, ["request-1", "request-2"]);
  assert.equal(coordinator.accept({ ...receipt("request-2", "current"), revision: 3 }), true);
  assert.equal((await flush).markdown, "current");
});

test("matching request IDs with the wrong document or generation are retried", async () => {
  let nextID = 0;
  const coordinator = new NoteSnapshotFlushCoordinator({
    createRequestID: () => `request-${++nextID}`,
    requestSnapshot: (requestID) => expectation(requestID, 1),
    onSnapshot: () => undefined,
  });
  const flush = coordinator.flush();
  assert.equal(coordinator.accept({
    ...receipt("request-1", "wrong note"),
    documentID: "note:b",
  }), false);
  assert.equal(coordinator.accept({
    ...receipt("request-2", "old frame"),
    documentGeneration: 3,
  }), false);
  coordinator.accept(receipt("request-3", "exact frame"));
  assert.equal((await flush).markdown, "exact frame");
});

test("an unrelated command rejection does not kill a pending snapshot", async () => {
  const coordinator = new NoteSnapshotFlushCoordinator({
    createRequestID: () => "request-1",
    requestSnapshot: (requestID) => expectation(requestID, 1),
    onSnapshot: () => undefined,
  });
  const flush = coordinator.flush();
  assert.equal(coordinator.rejectCommand("theme-command", new Error("unrelated")), false);
  coordinator.accept(receipt("request-1", "survives"));
  assert.equal((await flush).markdown, "survives");
});

function receipt(requestID: string, markdown: string): NoteEditorSnapshot {
  return {
    requestID,
    documentID: "note:a",
    documentGeneration: 4,
    revision: 2,
    markdown,
  };
}

function expectation(requestID: string, minimumRevision: number) {
  return {
    commandID: `command-for-${requestID}`,
    documentID: "note:a",
    documentGeneration: 4,
    minimumRevision,
  };
}
