export const STREAM_FIRST_DISPLAY_MILLISECONDS = 80;
export const STREAM_TICK_MILLISECONDS = 33;
export const STREAM_GRAPHEMES_PER_TICK = 4;
export const STREAM_CATCH_UP_GRAPHEMES_PER_TICK = 6;
export const STREAM_CATCH_UP_BACKLOG_THRESHOLD = 120;
export const STREAM_NORMAL_BACKLOG_THRESHOLD = 40;
export const STREAM_FINALIZE_SETTLE_MILLISECONDS = 560;

export interface StreamDisplayScheduler {
  schedule(callback: () => void, delayMilliseconds: number): unknown;
  cancel(handle: unknown): void;
}

export interface StreamDisplayClock {
  now(): number;
}

export interface StreamSettleSignal {
  readonly delayMilliseconds: typeof STREAM_FINALIZE_SETTLE_MILLISECONDS;
  readonly scheduledAtMilliseconds: number;
  readonly dueAtMilliseconds: number;
}

export interface StreamDisplayPumpHooks {
  /** Append only complete grapheme clusters. */
  append(chunk: string): void;
  /** Used for an authoritative non-prefix rewrite. */
  replace(text: string): void;
  /** Lets the renderer retain its fade/caret state for exactly 560ms. */
  settleScheduled?(signal: StreamSettleSignal): void;
  /** Fired after the settle window unless the pump was cancelled/restarted. */
  settled?(signal: StreamSettleSignal): void;
}

export interface StreamDisplayPumpOptions {
  hooks: StreamDisplayPumpHooks;
  scheduler?: StreamDisplayScheduler;
  clock?: StreamDisplayClock;
  locale?: string | string[];
}

const hostScheduler: StreamDisplayScheduler = {
  schedule: (callback, delayMilliseconds) =>
    globalThis.setTimeout(callback, delayMilliseconds),
  cancel: (handle) =>
    globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>),
};

const monotonicClock: StreamDisplayClock = {
  now: () =>
    typeof globalThis.performance?.now === "function"
      ? globalThis.performance.now()
      : Date.now(),
};

/**
 * The canonical visual cadence for a cumulative Agent reply.
 *
 * The model/session owns the complete text. This pump owns only the suffix that
 * has not yet become visible. A provider rewrite never mixes old and new
 * queues: it cancels pacing and lands the new authoritative snapshot at once.
 */
export class AgentStreamDisplayPump {
  static readonly firstDisplayMilliseconds =
    STREAM_FIRST_DISPLAY_MILLISECONDS;
  static readonly tickMilliseconds = STREAM_TICK_MILLISECONDS;
  static readonly graphemesPerTick = STREAM_GRAPHEMES_PER_TICK;
  static readonly catchUpGraphemesPerTick =
    STREAM_CATCH_UP_GRAPHEMES_PER_TICK;
  static readonly catchUpBacklogThreshold =
    STREAM_CATCH_UP_BACKLOG_THRESHOLD;
  static readonly normalBacklogThreshold =
    STREAM_NORMAL_BACKLOG_THRESHOLD;
  static readonly finalizeSettleMilliseconds =
    STREAM_FINALIZE_SETTLE_MILLISECONDS;

  private readonly hooks: StreamDisplayPumpHooks;
  private readonly scheduler: StreamDisplayScheduler;
  private readonly clock: StreamDisplayClock;
  private readonly segmenter: Intl.Segmenter;

  private receivedText = "";
  private visibleText = "";
  private pending: string[] = [];
  private pendingOffset = 0;
  private catchingUp = false;
  private pacingHandle: unknown | null = null;
  private pacingGeneration = 0;
  private settleHandle: unknown | null = null;
  private settleGeneration = 0;

  constructor(options: StreamDisplayPumpOptions) {
    this.hooks = options.hooks;
    this.scheduler = options.scheduler ?? hostScheduler;
    this.clock = options.clock ?? monotonicClock;
    this.segmenter = new Intl.Segmenter(options.locale, {
      granularity: "grapheme",
    });
  }

  get isRunning(): boolean {
    return this.pacingHandle !== null;
  }

  get hasPendingSettle(): boolean {
    return this.settleHandle !== null;
  }

  get pendingGraphemeCount(): number {
    return this.pending.length - this.pendingOffset;
  }

  get cumulativeText(): string {
    return this.receivedText;
  }

  get displayedText(): string {
    return this.visibleText;
  }

  get isCatchingUp(): boolean {
    return this.catchingUp;
  }

  /** Accept a cumulative provider snapshot and enqueue only its new suffix. */
  enqueue(cumulativeText: string): void {
    if (cumulativeText === this.receivedText) return;
    this.cancelSettleTimer();

    if (!cumulativeText.startsWith(this.receivedText)) {
      this.landRewrite(cumulativeText);
      return;
    }

    const suffix = cumulativeText.slice(this.receivedText.length);
    this.receivedText = cumulativeText;
    this.pending.push(...segmentGraphemes(this.segmenter, suffix));
    this.schedulePacingIfNeeded(STREAM_FIRST_DISPLAY_MILLISECONDS);
  }

  /**
   * Synchronously lands the authoritative final body, clears pacing backlog,
   * and returns/schedules the 560ms visual-settle signal.
   */
  finalize(cumulativeText: string = this.receivedText): StreamSettleSignal {
    if (cumulativeText !== this.receivedText) this.enqueue(cumulativeText);
    this.cancelPacingTimer();

    if (this.visibleText !== cumulativeText) {
      if (cumulativeText.startsWith(this.visibleText)) {
        const suffix = cumulativeText.slice(this.visibleText.length);
        if (suffix) this.hooks.append(suffix);
      } else {
        this.hooks.replace(cumulativeText);
      }
      this.visibleText = cumulativeText;
    }
    this.receivedText = cumulativeText;
    this.clearBacklog();
    this.catchingUp = false;
    return this.scheduleSettle();
  }

  /** Immediate landing used for reduced-motion/hidden-surface paths. */
  replaceImmediately(cumulativeText: string): void {
    this.cancelPacingTimer();
    this.cancelSettleTimer();
    this.receivedText = cumulativeText;
    this.visibleText = cumulativeText;
    this.clearBacklog();
    this.catchingUp = false;
    this.hooks.replace(cumulativeText);
  }

  /**
   * Consume exactly one canonical batch. Public for deterministic state tests;
   * production cadence is driven by the injected scheduler.
   */
  stepOnce(): void {
    const backlog = this.pendingGraphemeCount;
    if (backlog === 0) return;

    if (this.catchingUp) {
      if (backlog < STREAM_NORMAL_BACKLOG_THRESHOLD) {
        this.catchingUp = false;
      }
    } else if (backlog > STREAM_CATCH_UP_BACKLOG_THRESHOLD) {
      this.catchingUp = true;
    }

    const batchSize = this.catchingUp
      ? STREAM_CATCH_UP_GRAPHEMES_PER_TICK
      : STREAM_GRAPHEMES_PER_TICK;
    const end = Math.min(this.pending.length, this.pendingOffset + batchSize);
    const chunk = this.pending.slice(this.pendingOffset, end).join("");
    this.pendingOffset = end;
    this.visibleText += chunk;
    this.hooks.append(chunk);

    if (this.pendingOffset === this.pending.length) {
      this.clearBacklog();
      // A direct test/reduced-motion step can drain while the 80/33ms callback
      // is still armed. Retire that handle just as Swift cancels its Task.
      if (this.pacingHandle !== null) this.cancelPacingTimer();
    }
  }

  /** Retire this run without emitting replacement or settle callbacks. */
  cancel(): void {
    this.cancelPacingTimer();
    this.cancelSettleTimer();
    this.receivedText = "";
    this.visibleText = "";
    this.clearBacklog();
    this.catchingUp = false;
  }

  stopAndReset(): void {
    this.cancel();
  }

  private landRewrite(cumulativeText: string): void {
    this.cancelPacingTimer();
    this.receivedText = cumulativeText;
    this.visibleText = cumulativeText;
    this.clearBacklog();
    this.catchingUp = false;
    this.hooks.replace(cumulativeText);
  }

  private schedulePacingIfNeeded(delayMilliseconds: number): void {
    if (this.pendingGraphemeCount === 0 || this.pacingHandle !== null) return;
    const generation = ++this.pacingGeneration;
    this.pacingHandle = this.scheduler.schedule(() => {
      if (generation !== this.pacingGeneration) return;
      this.pacingHandle = null;
      this.stepOnce();
      if (this.pendingGraphemeCount > 0) {
        this.schedulePacingIfNeeded(STREAM_TICK_MILLISECONDS);
      }
    }, delayMilliseconds);
  }

  private scheduleSettle(): StreamSettleSignal {
    this.cancelSettleTimer();
    const scheduledAtMilliseconds = this.clock.now();
    if (!Number.isFinite(scheduledAtMilliseconds)) {
      throw new RangeError("Stream display clock returned a non-finite value");
    }
    const signal: StreamSettleSignal = Object.freeze({
      delayMilliseconds: STREAM_FINALIZE_SETTLE_MILLISECONDS,
      scheduledAtMilliseconds,
      dueAtMilliseconds:
        scheduledAtMilliseconds + STREAM_FINALIZE_SETTLE_MILLISECONDS,
    });
    const generation = ++this.settleGeneration;
    this.settleHandle = this.scheduler.schedule(() => {
      if (generation !== this.settleGeneration) return;
      this.settleHandle = null;
      this.hooks.settled?.(signal);
    }, STREAM_FINALIZE_SETTLE_MILLISECONDS);
    this.hooks.settleScheduled?.(signal);
    return signal;
  }

  private cancelPacingTimer(): void {
    this.pacingGeneration += 1;
    if (this.pacingHandle === null) return;
    this.scheduler.cancel(this.pacingHandle);
    this.pacingHandle = null;
  }

  private cancelSettleTimer(): void {
    this.settleGeneration += 1;
    if (this.settleHandle === null) return;
    this.scheduler.cancel(this.settleHandle);
    this.settleHandle = null;
  }

  private clearBacklog(): void {
    this.pending = [];
    this.pendingOffset = 0;
  }
}

/** Short alias for consumers which are already scoped to Agent streaming. */
export { AgentStreamDisplayPump as StreamDisplayPump };

function segmentGraphemes(
  segmenter: Intl.Segmenter,
  text: string,
): string[] {
  if (!text) return [];
  return Array.from(segmenter.segment(text), (part) => part.segment);
}
