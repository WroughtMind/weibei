import assert from "node:assert/strict";
import test from "node:test";
import {
  editorBridgeMessageNames,
  editorHostTransportVersion,
  type EditorBridgeEvent,
} from "../../shared/editor-contracts";
import {
  DeferredEditorEventBridge,
  DeferredEditorRequestQueue,
  type EditorMessagePortWriter,
} from "./bridge-queue";

class RecordingPort implements EditorMessagePortWriter {
  readonly messages: unknown[] = [];
  starts = 0;

  postMessage(message: EditorBridgeEvent): void {
    this.messages.push(message);
  }

  start(): void {
    this.starts += 1;
  }
}

test("prebuilds and freezes every WebKit-compatible handler", () => {
  const bridge = new DeferredEditorEventBridge("instance-one");
  assert.deepEqual(Object.keys(bridge.handlers), [...editorBridgeMessageNames]);
  assert.equal(Object.isFrozen(bridge.handlers), true);
  for (const handler of Object.values(bridge.handlers)) {
    assert.equal(Object.isFrozen(handler), true);
    assert.equal(typeof handler.postMessage, "function");
  }
});

test("queues events before port handoff and drains them once in order", () => {
  const bridge = new DeferredEditorEventBridge("instance-two");
  bridge.handlers.editorFailure.postMessage({
    documentID: "note-1",
    message: "early failure",
  });
  bridge.handlers.editorReady.postMessage({
    protocolVersion: 2,
    documentID: "note-1",
    documentGeneration: 3,
    revision: 0,
  });

  const port = new RecordingPort();
  bridge.attach(port);
  bridge.handlers.dirtyChanged.postMessage({
    protocolVersion: 2,
    documentID: "note-1",
    documentGeneration: 3,
    revision: 1,
    dirty: true,
  });

  assert.equal(port.starts, 1);
  assert.deepEqual(
    port.messages.map((message) => {
      const event = message as { name: string };
      return event.name;
    }),
    ["editorFailure", "editorReady", "dirtyChanged"],
  );
  for (const message of port.messages) {
    assert.equal(
      (message as { transportVersion: number }).transportVersion,
      editorHostTransportVersion,
    );
    assert.equal((message as { instanceId: string }).instanceId, "instance-two");
  }
});

test("rejects a second port so an old and new host cannot share one frame", () => {
  const bridge = new DeferredEditorEventBridge("instance-three");
  bridge.attach(new RecordingPort());
  assert.throws(
    () => bridge.attach(new RecordingPort()),
    /already attached/,
  );
});

test("does not execute early host calls until the editorReady boundary", () => {
  const executed: string[] = [];
  const queue = new DeferredEditorRequestQueue<string>((request) => {
    executed.push(request);
  });

  queue.enqueue("load-document");
  queue.enqueue("set-theme");
  assert.deepEqual(executed, []);

  queue.markReady();
  assert.deepEqual(executed, ["load-document", "set-theme"]);

  queue.enqueue("focus");
  assert.deepEqual(executed, ["load-document", "set-theme", "focus"]);
});

test("publishes editorReady before its callback can flush queued calls", () => {
  const order: string[] = [];
  class OrderedPort extends RecordingPort {
    override postMessage(message: EditorBridgeEvent): void {
      order.push(`post:${message.name}`);
      super.postMessage(message);
    }
  }
  const bridge = new DeferredEditorEventBridge("instance-four", (name) => {
    order.push(`callback:${name}`);
  });
  bridge.attach(new OrderedPort());
  bridge.handlers.editorReady.postMessage({
    protocolVersion: 2,
    documentID: "note-2",
    documentGeneration: 1,
    revision: 0,
  });
  assert.deepEqual(order, ["post:editorReady", "callback:editorReady"]);
});
