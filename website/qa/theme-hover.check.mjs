// 本地首页控制台：await (await import('/qa/theme-hover.check.mjs')).checkThemeHover()
const frame = () => new Promise(requestAnimationFrame);
const settle = async () => {
  await frame();
  await Promise.all(document.getAnimations().filter(a => a instanceof CSSTransition).map(a => a.finished.catch(() => {})));
  await frame();
};
const move = (x, y) => document.elementFromPoint(x, y)?.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, pointerType: 'mouse', clientX: x, clientY: y }));
const picture = preview => {
  const box = preview.querySelector('.theme-window').getBoundingClientRect();
  const img = preview.querySelector('.theme-track img');
  const scale = Math.min(box.width / img.naturalWidth, box.height / img.naturalHeight);
  const width = img.naturalWidth * scale, height = img.naturalHeight * scale;
  return { left: box.x + (box.width - width) / 2, top: box.y + (box.height - height) / 2, width, height };
};
export async function checkThemeHover() {
  if (innerWidth <= 760) throw new Error('请在桌面宽度检查鼠标悬停');
  document.activeElement.blur();
  document.querySelector('.theme-preview').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
  scrollTo({ top: (document.documentElement.scrollHeight - innerHeight) * .68, behavior: 'instant' });
  await settle();
  await Promise.all([...document.querySelectorAll('.themes-layer img')].map(img => { img.loading = 'eager'; return img.decode(); }));
  const checked = [];
  for (const preview of document.querySelectorAll('.theme-preview')) {
    move(10, 100);
    const small = picture(preview);
    move(small.left - 8, small.top + small.height / 2);
    if (document.documentElement.dataset.theme) throw new Error('截图外的留白触发了放大');
    const x = small.left + small.width * .85, y = small.top + small.height / 2;
    const variant = preview.dataset.variant;
    move(x, y);
    if (document.documentElement.dataset.theme !== preview.dataset.theme) throw new Error('进入截图没有放大');
    await settle();
    move(x + 1, y);
    if (document.documentElement.dataset.theme !== preview.dataset.theme) throw new Error('轻微移动让放大状态闪退');
    if (preview.dataset.variant !== variant) throw new Error('仅移动一像素就闪切了浅深主题');
    const large = picture(preview);
    move(large.left + 16, large.top + large.height / 2);
    if (preview.dataset.variant !== 'light') throw new Error('放大后向左移动没有切换浅色');
    move(large.left + large.width - 16, large.top + large.height / 2);
    if (preview.dataset.variant !== 'dark') throw new Error('放大后向右移动没有切换深色');
    move(large.left - 8, large.top + large.height / 2);
    if (document.documentElement.dataset.theme) throw new Error('离开截图后仍需移出整块舞台才缩回');
    await settle();
    move(large.left - 9, large.top + large.height / 2);
    if (document.documentElement.dataset.theme) throw new Error('缩回后原位置抖动又触发放大');
    move(10, 100);
    move(x, y);
    if (document.documentElement.dataset.theme !== preview.dataset.theme) throw new Error('重新进入截图无法再次放大');
    await settle();
    move(10, 100);
    await settle();
    checked.push(preview.dataset.theme);
  }
  const first = document.querySelector('.theme-paper'), next = document.querySelector('.theme-sand');
  const firstBox = picture(first), nextBox = picture(next);
  move(firstBox.left + firstBox.width / 2, firstBox.top + firstBox.height / 2);
  await settle();
  move(10, 100);
  move(nextBox.left + nextBox.width / 2, nextBox.top + nextBox.height / 2);
  await settle();
  await settle();
  if (document.documentElement.dataset.theme !== next.dataset.theme) throw new Error('缩回途中进入另一张截图后还得再移动才能打开');
  move(10, 100);
  await settle();
  first.focus();
  if (document.documentElement.dataset.theme !== first.dataset.theme) throw new Error('键盘聚焦无法打开截图');
  first.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
  if (document.documentElement.dataset.theme) throw new Error('Escape 无法退出截图');
  first.blur();
  await settle();
  return { status: 'passed', themes: checked, cases: ['picture entry', 'no padding trigger', 'no one-pixel flash', 'light/dark movement', 'picture edge exit', 'stable close and reentry', 'entry during collapse', 'keyboard focus/Escape'] };
}
