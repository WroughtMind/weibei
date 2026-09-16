export const webiActions = ['hi', 'talk', 'point', 'wait', 'idle', 'celebrate', 'think', 'surprise'] as const;
export type WebiAction = typeof webiActions[number];
export type WebiCue = { start: number; end: number; phoneme?: string };
const labels = ['打招呼', '讲解', '指重点', '等回答', '眨眼待机', '收尾庆祝', '思考', '惊讶'];
const sheets = ['课堂动作.webp', '情绪动作.webp'];
const sequence = [0, 1, 2, 3, 2, 1, 0];
const delays = [650, 180, 220, 550, 220, 180, 650];

export function webiFrame(action: WebiAction, milliseconds: number) {
  const times = action === 'idle' ? [2000, 100, 130, 1500]
    : action === 'hi' ? [420, 150, 190, 190, 190, 150, 650]
    : action === 'talk' ? [180, 170, 180, 210, 180, 170, 220] : delays;
  const duration = times.reduce((sum, value) => sum + value, 0);
  const looping = ['idle', 'talk', 'wait', 'think'].includes(action);
  let time = Math.max(0, milliseconds);
  if (!looping && time >= duration) return { col: 0, remaining: Infinity };
  time %= duration;
  let index = 0;
  while (time >= times[index]) time -= times[index++];
  return { col: action === 'idle' ? index : sequence[index], remaining: times[index] - time };
}

export function webiMouthForPinyin(phoneme: string, progress = 1): number {
  const syllable = phoneme.toLowerCase().replace(/[0-5]/g, '').replace(/ü/g, 'v');
  if (!/^[a-z]+$/.test(syllable)) return 0;
  const p = Math.max(0, Math.min(1, progress));
  if (p < 0.18 && /^[bpm]/.test(syllable)) return 1;
  if (p < 0.18 && /^f/.test(syllable)) return 7;
  const vowels = syllable.match(/[aeiouv]/g);
  if (!vowels) return 0;
  // ponytail: syllable timing is exact; vowel proportions are illustrative, not phoneme alignment.
  const vowel = vowels[Math.min(vowels.length - 1, Math.floor(p * vowels.length))];
  return ({ a: 2, e: 3, i: 4, o: 5, u: 6, v: 6 } as Record<string, number>)[vowel];
}

export function webiMouthAt(cues: readonly WebiCue[], seconds: number): number {
  if (!Number.isFinite(seconds) || seconds < 0) return 0;
  let low = 0, high = cues.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (cues[middle].start <= seconds) low = middle + 1; else high = middle;
  }
  const cue = cues[low - 1];
  return cue?.phoneme && seconds < cue.end
    ? webiMouthForPinyin(cue.phoneme, (seconds - cue.start) / (cue.end - cue.start)) : 0;
}

/** The host owns placement. This view observes playback; it never starts or acknowledges speech. */
export function createWebiCompanion(host: HTMLElement) {
  const element = document.createElement('div'), canvas = document.createElement('canvas');
  const toggle = document.createElement('button'), status = document.createElement('span');
  element.className = 'webi-companion';
  element.style.cssText = 'position:relative;width:144px;max-width:100%;';
  canvas.width = canvas.height = 384;
  canvas.style.cssText = 'display:block;width:100%;height:auto;pointer-events:none;filter:drop-shadow(0 0 .75px currentColor)';
  canvas.setAttribute('role', 'img');
  toggle.type = 'button';
  toggle.style.cssText = 'display:block;margin-left:auto;min-height:28px;padding:2px 8px;border:0;border-radius:6px;background:var(--paper,transparent);color:inherit;font:inherit;font-size:11px;cursor:pointer';
  status.setAttribute('role', 'status');status.style.cssText = 'font-size:12px';
  element.append(canvas, toggle, status);host.append(element);
  const context = canvas.getContext('2d');
  if (!context) { element.remove(); throw new Error('Webi 画布不可用'); }
  const ctx = context;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let action: WebiAction = 'idle', elapsed = 0, lastTime = performance.now(), manualMouth = 0;
  let collapsed = false, intersecting = false, paused = false, destroyed = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let body: HTMLImageElement | undefined, mouth: HTMLImageElement | undefined, bodySheet = '';
  let binding: { audio: HTMLAudioElement; cues: readonly WebiCue[] } | undefined;
  let detachAudio: (() => void) | undefined, lastPaint = '';
  const visible = () => !destroyed && !collapsed && !document.hidden && intersecting;
  const stopped = () => paused || !!binding && (binding.audio.paused || binding.audio.ended);
  const advance = () => {
    const now = performance.now();
    if (visible() && !stopped()) elapsed += now - lastTime;
    lastTime = now;
  };
  const discard = (image?: HTMLImageElement) => {
    if (!image) return;
    image.onload = image.onerror = null;image.removeAttribute('src');
  };
  const release = () => {
    discard(body);discard(mouth);body = mouth = undefined;bodySheet = '';lastPaint = '';
    canvas.width = canvas.height = 1;
    element.dataset.loaded = 'false';
  };
  function load(name: string) {
    const image = new Image();
    image.onload = () => { if (visible()) refresh(); };
    image.onerror = () => {
      if (!visible()) return;
      status.textContent = 'Webi 素材加载失败';element.dataset.error = name;
      clearTimeout(timer);
    };
    image.src = new URL(name, document.baseURI).href;
    return image;
  }
  function refresh() {
    clearTimeout(timer);advance();
    if (!visible()) { release();return; }
    const index = webiActions.indexOf(action), sheet = sheets[Math.floor(index / 4)];
    if (bodySheet !== sheet) {
      discard(body);bodySheet = sheet;body = load(sheet);lastPaint = '';
    }
    mouth ??= load('独立口型.png');
    if (!body?.naturalWidth || !mouth.naturalWidth) return;
    status.textContent = '';delete element.dataset.error;
    if (canvas.width !== 384) canvas.width = canvas.height = 384;
    const frame = webiFrame(action, reduced.matches ? 0 : elapsed);
    const mouthIndex = stopped() ? 0 : binding ? webiMouthAt(binding.cues, binding.audio.currentTime) : manualMouth;
    const paint = [action, frame.col, mouthIndex].join(':');
    if (paint !== lastPaint) {
      ctx.clearRect(0, 0, 384, 384);
      ctx.drawImage(body, frame.col * 384, (index % 4) * 384, 384, 384, 0, 0, 384, 384);
      ctx.drawImage(mouth, (mouthIndex % 4) * 64, Math.floor(mouthIndex / 4) * 64, 64, 64, 160, 136, 64, 64);
      lastPaint = paint;
    }
    canvas.setAttribute('aria-label', 'Webi · ' + labels[index]);
    element.dataset.action = action;element.dataset.mouth = String(mouthIndex);element.dataset.loaded = 'true';
    const delay = binding && !stopped() ? Math.min(1000 / 30, frame.remaining)
      : reduced.matches || stopped() ? Infinity : frame.remaining;
    if (Number.isFinite(delay)) timer = setTimeout(refresh, Math.max(10, delay));
  }
  const observer = new IntersectionObserver(([entry]) => {
    advance();intersecting = entry.isIntersecting;refresh();
  });
  observer.observe(element);
  const visibilityChanged = () => { lastTime = performance.now();refresh(); };
  document.addEventListener('visibilitychange', visibilityChanged);
  reduced.addEventListener('change', refresh);
  const api = {
    element,
    setAction(value: WebiAction) {
      if (destroyed || action === value) return;
      if (!webiActions.includes(value)) throw new Error('不支持的 Webi 动作');
      action = value;elapsed = 0;lastTime = performance.now();refresh();
    },
    setMouth(value: number) {
      if (!Number.isInteger(value) || value < 0 || value > 7) throw new Error('不支持的 Webi 口型');
      manualMouth = value;refresh();
    },
    setPaused(value: boolean) { advance();paused = value;refresh(); },
    setCollapsed(value: boolean) {
      advance();collapsed = value;canvas.hidden = value;canvas.style.display = value ? 'none' : 'block';
      status.hidden = value;toggle.textContent = value ? '显示 Webi' : '收起';
      toggle.setAttribute('aria-label', value ? '显示 Webi' : '收起 Webi');
      toggle.setAttribute('aria-expanded', String(!value));refresh();
    },
    followAudio(audio: HTMLAudioElement, cues: readonly WebiCue[]) {
      if (destroyed) return () => {};
      detachAudio?.();
      if (cues.some((cue, i) => !Number.isFinite(cue.start) || !Number.isFinite(cue.end)
        || cue.start < 0 || cue.end <= cue.start || i > 0 && cue.start < cues[i - 1].end)) {
        throw new Error('Webi 语音时序无效');
      }
      binding = { audio, cues };api.setAction('talk');
      const update = () => { lastTime = performance.now();refresh(); };
      const finish = (event: Event) => {
        // Replacing src also queues emptied; it must not detach the new paragraph.
        if (event.type === 'emptied' ? !audio.getAttribute('src')
          : event.type === 'ended' ? audio.ended : !!audio.error) cleanup();
        else update();
      };
      const events = ['playing', 'pause', 'seeking', 'seeked', 'timeupdate', 'ratechange'] as const;
      events.forEach(event => audio.addEventListener(event, update));
      ['ended', 'emptied', 'error'].forEach(event => audio.addEventListener(event, finish));
      let attached = true;
      const cleanup = () => {
        if (!attached) return;attached = false;
        events.forEach(event => audio.removeEventListener(event, update));
        ['ended', 'emptied', 'error'].forEach(event => audio.removeEventListener(event, finish));
        binding = undefined;detachAudio = undefined;manualMouth = 0;api.setAction('idle');refresh();
      };
      detachAudio = cleanup;refresh();return cleanup;
    },
    destroy() {
      if (destroyed) return;destroyed = true;detachAudio?.();clearTimeout(timer);
      observer.disconnect();document.removeEventListener('visibilitychange', visibilityChanged);
      reduced.removeEventListener('change', refresh);release();element.remove();
    },
  };
  toggle.onclick = () => api.setCollapsed(!collapsed);
  api.setCollapsed(false);
  return api;
}
