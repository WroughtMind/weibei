import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile, readdir, stat } from 'node:fs/promises';
import { createWebiCompanion, webiActions, webiFrame, webiMouthAt, webiMouthForPinyin } from '../src/webiCompanion';

test('Webi preserves every frame and mouth within its 500 KiB offline resource budget', async () => {
  const path = 'Sources/WeiBei/Resources/Editor/Webi/';
  const names = (await readdir(path)).sort();
  assert.deepEqual(names, ['情绪动作.webp', '独立口型.png', '素材清单.json', '课堂动作.webp'].sort());
  const sizes = await Promise.all(names.map(async name => (await stat(path + name)).size));
  assert.ok(sizes.reduce((sum, size) => sum + size, 0) <= 500 * 1024);
  const manifest = JSON.parse(await readFile(path + '素材清单.json', 'utf8'));
  assert.deepEqual(manifest.actions.map((action: { id: string }) => action.id), webiActions);
  assert.equal(manifest.mouths.length, 8);
  for (const action of manifest.actions) {
    let time = 0;
    action.delays.forEach((delay: number, i: number) => {
      assert.equal(webiFrame(action.id, time).col, action.sequence[i]);
      assert.equal(webiFrame(action.id, time + delay - 1).col, action.sequence[i]);
      time += delay;
    });
    assert.equal(webiFrame(action.id, time).col, 0);
  }
  assert.equal(webiFrame('hi', 10000).remaining, Infinity);
  assert.equal(webiFrame('idle', 5730).col, 1);
  assert.deepEqual(['ma1', 'fa1', 'a1', 'e1', 'i1', 'o1', 'u1', 'ü4'].map(p => webiMouthForPinyin(p, 0)), [1, 7, 2, 3, 4, 5, 6, 6]);
  const cues = [{ start: 0.2, end: 0.5, phoneme: 'ma1' }, { start: 0.5, end: 0.8 }, { start: 1, end: 1.4, phoneme: 'o1' }];
  assert.deepEqual([0, 0.2, 0.4, 0.5, 0.9, 1.2, 1.4, NaN].map(t => webiMouthAt(cues, t)), [0, 1, 2, 0, 0, 5, 0, 0]);
  assert.equal(webiMouthAt([], 1), 0);
});

test('Replacing an audio paragraph retains mouth tracking; stop and stale cleanup stay isolated', t => {
  // Keep this event-lifecycle check hidden; it requires no image decoder or browser dependency.
  const element = () => ({ style: {}, dataset: {}, append() {}, remove() {},
    setAttribute() {}, getContext: () => ({}) });
  const doc = Object.assign(new EventTarget(), { hidden: true, createElement: element });
  const globals = {
    document: doc,
    matchMedia: () => Object.assign(new EventTarget(), { matches: false }),
    IntersectionObserver: class { observe() {} disconnect() {} },
  };
  const originals = Object.fromEntries(Object.keys(globals).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  Object.assign(globalThis, globals);
  const audio = Object.assign(new EventTarget(), { src: 'paragraph-1', paused: false, ended: false, error: null,
    currentTime: 0, getAttribute() { return this.src; } });
  const removals = t.mock.method(audio, 'removeEventListener');
  const companion = createWebiCompanion(element() as unknown as HTMLElement);
  try {
    const first = companion.followAudio(audio as unknown as HTMLAudioElement, []);
    audio.src = 'paragraph-2';
    const second = companion.followAudio(audio as unknown as HTMLAudioElement, []);
    const before = removals.mock.callCount();
    first();
    for (const name of ['emptied', 'ended', 'error']) audio.dispatchEvent(new Event(name));
    assert.equal(removals.mock.callCount(), before, 'queued old media events must retain the new binding');
    audio.src = '';audio.dispatchEvent(new Event('emptied'));
    assert.equal(removals.mock.callCount(), before + 9, 'stopping releases every media listener');
    second();
    assert.equal(removals.mock.callCount(), before + 9, 'cleanup is idempotent');
  } finally {
    companion.destroy();
    for (const [key, descriptor] of Object.entries(originals)) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);else Reflect.deleteProperty(globalThis, key);
    }
  }
});
