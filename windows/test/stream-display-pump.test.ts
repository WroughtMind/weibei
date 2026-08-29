import assert from "node:assert/strict";
import test from "node:test";
import {
  AgentStreamDisplayPump,
  STREAM_CATCH_UP_BACKLOG_THRESHOLD,
  STREAM_CATCH_UP_GRAPHEMES_PER_TICK,
  STREAM_FINALIZE_SETTLE_MILLISECONDS,
  STREAM_FIRST_DISPLAY_MILLISECONDS,
  STREAM_GRAPHEMES_PER_TICK,
  STREAM_NORMAL_BACKLOG_THRESHOLD,
  STREAM_TICK_MILLISECONDS,
  type StreamDisplayClock,
  type StreamDisplayPumpHooks,
  type StreamDisplayScheduler,
  type StreamSettleSignal,
} from "../src/renderer/stream-display-pump";

test("first display waits 80ms and subsequent batches tick every 33ms", () => {
  const rig = new PumpRig();
  rig.pump.enqueue("abcdefghij");

  assert.equal(rig.pump.pendingGraphemeCount, 10);
  assert.equal(rig.scheduler.pendingTaskCount, 1);
  rig.scheduler.advanceBy(79);
  assert.deepEqual(rig.chunks, []);
  rig.scheduler.advanceBy(1);
  assert.deepEqual(rig.chunks, ["abcd"]);

  rig.scheduler.advanceBy(32);
  assert.deepEqual(rig.chunks, ["abcd"]);
  rig.scheduler.advanceBy(1);
  assert.deepEqual(rig.chunks, ["abcd", "efgh"]);
  rig.scheduler.advanceBy(33);
  assert.deepEqual(rig.chunks, ["abcd", "efgh", "ij"]);
  assert.equal(rig.scheduler.pendingTaskCount, 0);

  // A refill after the queue has drained receives the same initial buffer.
  rig.pump.enqueue("abcdefghijKLMN");
  rig.scheduler.advanceBy(79);
  assert.deepEqual(rig.chunks, ["abcd", "efgh", "ij"]);
  rig.scheduler.advanceBy(1);
  assert.deepEqual(rig.chunks, ["abcd", "efgh", "ij", "KLMN"]);

  assert.equal(STREAM_FIRST_DISPLAY_MILLISECONDS, 80);
  assert.equal(STREAM_TICK_MILLISECONDS, 33);
});

test("Intl.Segmenter never splits emoji, flags, or combining characters", () => {
  const rig = new PumpRig();
  const text = "👨‍👩‍👧‍👦e\u0301中🇨🇳";
  rig.pump.enqueue(text);
  assert.equal(rig.pump.pendingGraphemeCount, 4);

  rig.scheduler.advanceBy(80);
  assert.deepEqual(rig.chunks, [text]);
  assert.equal(rig.displayed, text);
  assert.equal(rig.pump.pendingGraphemeCount, 0);
});

test("normal speed is four at 120; catch-up is six only above 120", () => {
  const normal = new PumpRig();
  normal.pump.enqueue("甲".repeat(120));
  normal.pump.stepOnce();
  assert.equal(graphemeCount(normal.chunks[0]), 4);
  assert.equal(normal.pump.isCatchingUp, false);
  normal.pump.cancel();

  const catchUp = new PumpRig();
  catchUp.pump.enqueue("长".repeat(121));
  catchUp.pump.stepOnce();
  assert.equal(graphemeCount(catchUp.chunks[0]), 6);
  assert.equal(catchUp.pump.isCatchingUp, true);

  assert.equal(STREAM_GRAPHEMES_PER_TICK, 4);
  assert.equal(STREAM_CATCH_UP_GRAPHEMES_PER_TICK, 6);
  assert.equal(STREAM_CATCH_UP_BACKLOG_THRESHOLD, 120);
});

test("catch-up remains six through 40 and returns to four below 40", () => {
  const rig = new PumpRig();
  rig.pump.enqueue("长".repeat(121));

  while (rig.pump.pendingGraphemeCount >= STREAM_NORMAL_BACKLOG_THRESHOLD) {
    rig.pump.stepOnce();
  }
  assert.equal(rig.pump.pendingGraphemeCount, 37);
  assert.equal(graphemeCount(rig.chunks.at(-1)!), 6);
  assert.equal(rig.pump.isCatchingUp, true);

  rig.pump.stepOnce();
  assert.equal(graphemeCount(rig.chunks.at(-1)!), 4);
  assert.equal(rig.pump.isCatchingUp, false);
  assert.equal(STREAM_NORMAL_BACKLOG_THRESHOLD, 40);
  rig.pump.cancel();
});

test("a non-prefix provider rewrite replaces immediately and cancels pacing", () => {
  const rig = new PumpRig();
  rig.pump.enqueue("旧内容仍在排队");
  rig.scheduler.advanceBy(80);
  assert.equal(rig.chunks.length, 1);
  assert.equal(rig.scheduler.pendingTaskCount, 1);

  rig.pump.enqueue("新👩🏽‍💻内容");
  assert.deepEqual(rig.replacements, ["新👩🏽‍💻内容"]);
  assert.equal(rig.displayed, "新👩🏽‍💻内容");
  assert.equal(rig.pump.pendingGraphemeCount, 0);
  assert.equal(rig.pump.isRunning, false);
  assert.equal(rig.scheduler.pendingTaskCount, 0);

  rig.scheduler.advanceBy(10_000);
  assert.equal(rig.displayed, "新👩🏽‍💻内容");
  assert.equal(rig.chunks.length, 1);
});

test("finalize synchronously clears backlog and exposes the 560ms settle signal", () => {
  const rig = new PumpRig();
  const streamed = "甲".repeat(20);
  const finalText = `${streamed}终`;
  rig.pump.enqueue(streamed);
  rig.scheduler.advanceBy(80);
  assert.equal(rig.displayed, "甲".repeat(4));
  assert.equal(rig.pump.pendingGraphemeCount, 16);

  const signal = rig.pump.finalize(finalText);
  assert.equal(rig.displayed, finalText);
  assert.equal(rig.pump.pendingGraphemeCount, 0);
  assert.equal(rig.pump.isRunning, false);
  assert.equal(rig.pump.hasPendingSettle, true);
  assert.equal(rig.scheduler.pendingTaskCount, 1);
  assert.equal(Object.isFrozen(signal), true);
  assert.deepEqual(signal, {
    delayMilliseconds: 560,
    scheduledAtMilliseconds: 80,
    dueAtMilliseconds: 640,
  });
  assert.deepEqual(rig.scheduledSettles, [signal]);

  rig.scheduler.advanceBy(559);
  assert.deepEqual(rig.completedSettles, []);
  rig.scheduler.advanceBy(1);
  assert.deepEqual(rig.completedSettles, [signal]);
  assert.equal(rig.pump.hasPendingSettle, false);
  assert.equal(rig.scheduler.pendingTaskCount, 0);
  assert.equal(STREAM_FINALIZE_SETTLE_MILLISECONDS, 560);
});

test("finalize uses replacement when its authoritative body is a rewrite", () => {
  const rig = new PumpRig();
  rig.pump.enqueue("旧答案");
  rig.scheduler.advanceBy(80);

  rig.pump.finalize("最终答案");
  assert.equal(rig.displayed, "最终答案");
  assert.deepEqual(rig.replacements, ["最终答案"]);
  assert.equal(rig.pump.pendingGraphemeCount, 0);
  assert.equal(rig.scheduler.pendingTaskCount, 1);
});

test("cancel clears pacing and settle timers without late callbacks", () => {
  const rig = new PumpRig();
  rig.pump.enqueue("不会显示的排队文本");
  assert.equal(rig.scheduler.pendingTaskCount, 1);
  rig.pump.cancel();
  assert.equal(rig.scheduler.pendingTaskCount, 0);
  assert.equal(rig.pump.pendingGraphemeCount, 0);
  assert.equal(rig.pump.isRunning, false);
  rig.scheduler.advanceBy(1_000);
  assert.deepEqual(rig.chunks, []);

  rig.pump.enqueue("完成前正文");
  rig.pump.finalize();
  assert.equal(rig.scheduler.pendingTaskCount, 1);
  assert.equal(rig.pump.hasPendingSettle, true);
  rig.pump.cancel();
  assert.equal(rig.scheduler.pendingTaskCount, 0);
  assert.equal(rig.pump.hasPendingSettle, false);
  rig.scheduler.advanceBy(1_000);
  assert.deepEqual(rig.completedSettles, []);

  // Cancellation is idempotent and does not leave stale handles behind.
  rig.pump.cancel();
  assert.equal(rig.scheduler.pendingTaskCount, 0);
});

class PumpRig {
  readonly scheduler = new ManualScheduler();
  readonly chunks: string[] = [];
  readonly replacements: string[] = [];
  readonly scheduledSettles: StreamSettleSignal[] = [];
  readonly completedSettles: StreamSettleSignal[] = [];
  displayed = "";
  readonly pump: AgentStreamDisplayPump;

  constructor() {
    const hooks: StreamDisplayPumpHooks = {
      append: (chunk) => {
        this.chunks.push(chunk);
        this.displayed += chunk;
      },
      replace: (text) => {
        this.replacements.push(text);
        this.displayed = text;
      },
      settleScheduled: (signal) => this.scheduledSettles.push(signal),
      settled: (signal) => this.completedSettles.push(signal),
    };
    this.pump = new AgentStreamDisplayPump({
      hooks,
      scheduler: this.scheduler,
      clock: this.scheduler,
      locale: "zh-Hans",
    });
  }
}

interface ScheduledTask {
  id: number;
  dueAt: number;
  callback: () => void;
}

class ManualScheduler implements StreamDisplayScheduler, StreamDisplayClock {
  private currentTime = 0;
  private nextID = 1;
  private readonly tasks = new Map<number, ScheduledTask>();

  get pendingTaskCount(): number {
    return this.tasks.size;
  }

  now(): number {
    return this.currentTime;
  }

  schedule(callback: () => void, delayMilliseconds: number): unknown {
    assert.ok(Number.isFinite(delayMilliseconds));
    assert.ok(delayMilliseconds >= 0);
    const id = this.nextID++;
    this.tasks.set(id, {
      id,
      dueAt: this.currentTime + delayMilliseconds,
      callback,
    });
    return id;
  }

  cancel(handle: unknown): void {
    assert.equal(typeof handle, "number");
    this.tasks.delete(handle as number);
  }

  advanceBy(milliseconds: number): void {
    assert.ok(milliseconds >= 0);
    const target = this.currentTime + milliseconds;
    while (true) {
      const next = [...this.tasks.values()]
        .filter((task) => task.dueAt <= target)
        .sort((left, right) => left.dueAt - right.dueAt || left.id - right.id)[0];
      if (!next) break;
      this.currentTime = next.dueAt;
      this.tasks.delete(next.id);
      next.callback();
    }
    this.currentTime = target;
  }
}

const testSegmenter = new Intl.Segmenter("zh-Hans", {
  granularity: "grapheme",
});

function graphemeCount(text: string): number {
  return Array.from(testSegmenter.segment(text)).length;
}
