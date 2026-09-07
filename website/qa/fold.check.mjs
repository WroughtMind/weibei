// 在本地首页控制台运行：await (await import('/qa/fold.check.mjs')).checkFold()
// 同时记录页面真实动画帧间隔和展开几何；帧间隔不是显示器呈现帧率。
const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
const seek = async progress => {
  scrollTo({ top: (document.documentElement.scrollHeight - innerHeight) * progress, behavior: 'instant' });
  await frame();
  await frame();
};

export async function checkFold() {
  await document.fonts.ready;
  await seek(.7);
  await Promise.all([...document.querySelectorAll('.release-layer img, .themes-layer img')].map(img => { img.loading = 'eager'; return img.decode(); }));
  const faces = [...document.querySelectorAll('.paper-face')];
  if (faces.length !== 4) throw new Error('四块纸面未加载');
  await seek(.7);
  const control = document.querySelector('.download-control').getBoundingClientRect();
  if (document.elementFromPoint(control.x + control.width / 2, control.y + control.height / 2)?.closest('.release-layer')) {
    throw new Error('隐藏的下载入口挡住第三幕');
  }
  document.activeElement.blur();
  document.querySelector('.theme-paper').focus();
  await frame();
  if (getComputedStyle(document.querySelector('.world-paper-ink')).visibility !== 'visible') {
    throw new Error('展开主题时背景没有出现');
  }
  await seek(.97);
  for (let i = 0; i < 30; i++) await frame();
  // 第四幕的固定背景附着会让原生滚动反复重画整页，rAF 间隔检查抓不到它。
  for (const element of [document.documentElement, document.body, document.querySelector('.scene-four')]) {
    if (getComputedStyle(element).backgroundAttachment.split(',').some(value => value.trim() === 'fixed')) {
      throw new Error('第四幕仍使用导致整页滚动重绘的固定背景附着');
    }
  }
  if ([...document.querySelectorAll('.theme-world')].some(world => getComputedStyle(world).visibility !== 'hidden')) {
    throw new Error('离开第三幕后隐藏的背景仍参与绘制');
  }
  document.activeElement.blur();
  const widths = [];
  for (let step = 0; step <= 26; step++) {
    await seek(.79 + step * .005);
    const bounds = faces.map(face => face.getBoundingClientRect());
    widths.push(Math.max(...bounds.map(b => b.right)) - Math.min(...bounds.map(b => b.left)));
  }
  const deltas = widths.slice(1).map((width, i) => width - widths[i]);
  if (deltas.some(delta => delta < -1)) throw new Error('向前滚动时纸张反向收缩');
  if (deltas.some((delta, i) => i > 0 && deltas[i - 1] > 30 && delta < deltas[i - 1] * .3)) {
    throw new Error('折页展开速度突然下降');
  }
  if (widths.at(-1) < widths[0] * 3) throw new Error('折页没有实际展开');
  const { runs } = await measureFoldScroll();
  await seek(.97);
  const toggle = document.querySelector('[data-download-toggle]');
  toggle.click();
  if (document.querySelector('[data-download-menu]').hidden) throw new Error('第四幕下载菜单无法展开');
  toggle.click();
  const result = { viewport: [innerWidth, innerHeight, devicePixelRatio], unfolds: true, hiddenHitArea: 'passed', downloadMenu: 'passed', runs };
  if (runs.some(run => run.over50)) throw new Error(`跨幕仍有超过 50 毫秒的长帧：${JSON.stringify(result)}`);
  return result;
}

export async function measureFoldScroll() {
  await document.fonts.ready;
  await seek(.7);
  await Promise.all([...document.querySelectorAll('.release-layer img, .themes-layer img')].map(img => { img.loading = 'eager'; return img.decode(); }));
  const viewport = [innerWidth, innerHeight, devicePixelRatio];
  const runs = [];
  for (let run = 0; run < 3; run++) {
    await seek(.7);
    const start = scrollY;
    const end = document.documentElement.scrollHeight - innerHeight;
    const intervals = [];
    const slow = [];
    let previous = await frame();
    for (let step = 0; step <= 240; step++) {
      const progress = step <= 120 ? step / 120 : (240 - step) / 120;
      scrollTo({ top: start + (end - start) * progress, behavior: 'instant' });
      const now = await frame();
      const ms = now - previous;
      intervals.push(ms);
      if (ms > 50) slow.push({ ms, progress: scrollY / end, direction: step <= 120 ? 'forward' : 'backward' });
      previous = now;
    }
    runs.push({ max: Math.max(...intervals), over50: slow.length, slow });
  }
  if (viewport.some((value, index) => value !== [innerWidth, innerHeight, devicePixelRatio][index])) {
    throw new Error('测量期间窗口尺寸或缩放改变，本轮数据无效');
  }
  return { viewport, runs };
}
