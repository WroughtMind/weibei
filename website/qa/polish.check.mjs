// 本地首页控制台：await (await import('/qa/polish.check.mjs')).checkWebsitePolish()
// 保护手动选择、手机点击范围、跨幕焦点与下载链接；不检查文案措辞。
import { matchDownloadAssets } from '../download-selection.mjs';
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const waitFor = async predicate => {
  const deadline = performance.now() + 3000;
  while (!predicate()) {
    assert(performance.now() < deadline, '页面没有进入预期状态');
    await new Promise(requestAnimationFrame);
  }
  await new Promise(requestAnimationFrame);
};
const enter = async scene => {
  await waitFor(() => document.readyState === 'complete');
  document.getElementById(`scene-${scene}`).scrollIntoView({ behavior: 'instant' });
  await waitFor(() => document.documentElement.dataset.scene === String(scene));
  assert(new URL(document.querySelector('[data-language-toggle]').href).hash === `#scene-${scene}`, '切换语言会丢失当前场景');
};

// 切换语言或点击详情页标志返回后，传入离开前的场景与滚动进度。
export async function checkHomePosition(scene, progress) {
  await waitFor(() => document.readyState === 'complete' && document.documentElement.dataset.scene === String(scene));
  const expected = progress * (document.documentElement.scrollHeight - innerHeight);
  assert(Math.abs(scrollY - expected) <= 1, '返回后丢失原来的浏览位置');
  return { scene, position: 'passed' };
}

export async function checkDownloads(assets = []) {
  await enter(4);
  const link = document.querySelector('[data-download-link]');
  const toggle = document.querySelector('[data-download-toggle]');
  const menu = document.querySelector('[data-download-menu]');
  const matched = matchDownloadAssets(assets);
  assert(!toggle.hidden && getComputedStyle(toggle).display !== 'none', '版本选择入口消失了');
  // 先选非默认版本；延迟版本请求时，也能发现手动选择被异步结果覆盖。
  for (const option of [...document.querySelectorAll('[data-download-target]')].reverse()) {
    assert(!option.disabled, '无法选择芯片版本');
    toggle.click();
    assert(!menu.hidden, '版本菜单没有打开');
    option.click();
    assert(option.classList.contains('is-selected') && menu.hidden, '版本选择没有生效');
    const asset = matched[option.dataset.downloadTarget];
    if (asset?.download_url) {
      await waitFor(() => link.href === new URL(asset.download_url, document.baseURI).href);
      assert(link.href === new URL(asset.download_url, document.baseURI).href && link.download === asset.name, '下载链接与已选安装包不一致');
    } else {
      assert(!link.hasAttribute('download') && new URL(link.href).pathname.endsWith('/releases'), '无安装包时没有准确指向发布页');
    }
  }
  return { downloads: 'passed' };
}

export async function checkWebsitePolish() {
  const detail = document.querySelector('.experience-tabs');
  const themes = document.querySelector('.themes-layer');
  const release = document.querySelector('.release-layer');
  await enter(1);
  assert(detail.inert && themes.inert && release.inert, '隐藏的场景仍能接收操作');
  if (innerWidth <= 760) assert(document.querySelector('.hero-tagline').getBoundingClientRect().bottom <= document.querySelector('.blank-layer').getBoundingClientRect().top, '首屏截图遮住了产品介绍');
  await enter(2);
  assert(!detail.inert && themes.inert && release.inert, '第二幕操作边界不正确');
  for (const button of document.querySelectorAll('[data-mode-target]')) {
    button.click();
    const mode = button.dataset.modeTarget;
    assert(document.querySelector('.experience-page.is-active').dataset.mode === mode, '切换按钮没有打开对应截图');
    assert(document.querySelectorAll('[data-mode-target][aria-pressed="true"]').length === 1, '选中状态不唯一');
    if (innerWidth <= 760) assert(button.getBoundingClientRect().height >= 44, '手机点击区域过小');
  }
  const selected = document.querySelector('.experience-page.is-active').dataset.mode;
  await new Promise(resolve => setTimeout(resolve, 4600));
  assert(document.querySelector('.experience-page.is-active').dataset.mode === selected, '手动选中的内容仍被自动轮换打断');
  assert(detail.getBoundingClientRect().top >= document.querySelector('.experience-layer').getBoundingClientRect().bottom, '操作区遮住截图');
  await enter(3);
  assert(detail.inert && !themes.inert && release.inert, '第三幕操作边界不正确');
  await enter(4);
  assert(detail.inert && themes.inert && !release.inert, '第四幕操作边界不正确');
  const bounds = document.querySelector('.download-control').getBoundingClientRect();
  assert(bounds.top >= 0 && bounds.bottom <= innerHeight, '下载按钮超出屏幕');
  assert(document.documentElement.scrollWidth <= innerWidth, '页面出现横向溢出');
  return { manualSelection: 'passed', sceneBoundaries: 'passed', viewport: [innerWidth, innerHeight] };
}
