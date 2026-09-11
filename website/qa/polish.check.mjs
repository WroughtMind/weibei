// 本地首页控制台：await (await import('/qa/polish.check.mjs')).checkWebsitePolish()
// 保护手动选择、手机点击范围、跨幕焦点与真实下载状态；不检查文案措辞。
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
  document.getElementById(`scene-${scene}`).scrollIntoView({ behavior: 'instant' });
  await waitFor(() => document.documentElement.dataset.scene === String(scene));
};

export async function checkDownloadState(expected, assets = []) {
  await enter(4);
  const control = document.querySelector('[data-download-control]');
  await waitFor(() => control.dataset.state !== 'loading');
  assert(control.dataset.state === expected, '下载区没有区分可用、未发布和查询失败');
  const link = document.querySelector('[data-download-link]');
  const toggle = document.querySelector('[data-download-toggle]');
  if (expected === 'ready') {
    assert(!toggle.hidden, '有安装包时无法选择芯片');
    toggle.click();
    for (const option of document.querySelectorAll('[data-download-target]')) {
      if (option.disabled) continue;
      option.click();
      assert(assets.some(asset => asset.download_url === link.href && asset.name === link.download), '下载链接与已选安装包不一致');
    }
  } else {
    assert(toggle.hidden && getComputedStyle(toggle).display === 'none', '无安装包时仍显示芯片选择');
    assert(!link.hasAttribute('download') && new URL(link.href).pathname.endsWith('/releases'), '无安装包时没有准确指向发布页');
  }
  assert(document.querySelector('[data-download-status]').textContent.trim(), '没有展示下载状态');
  return { downloads: expected };
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
  const bounds = document.querySelector('.download-status').getBoundingClientRect();
  assert(bounds.top >= 0 && bounds.bottom <= innerHeight, '下载说明超出屏幕');
  assert(document.querySelector('.download-control').getBoundingClientRect().bottom <= bounds.top, '下载纸签遮住版本状态');
  assert(document.documentElement.scrollWidth <= innerWidth, '页面出现横向溢出');
  return { manualSelection: 'passed', sceneBoundaries: 'passed', viewport: [innerWidth, innerHeight] };
}
