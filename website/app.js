import './motion.js';
import { chooseDownloadId, downloadTargets, matchDownloadAssets, preferredDownloadIds } from './download-selection.mjs';

const chapters = [...document.querySelectorAll('.chapter')];
const railButtons = [...document.querySelectorAll('.scene-rail button')];
const experienceLayer = document.querySelector('.experience-layer');
const themePreviews = [...document.querySelectorAll('.theme-preview')];
const themesLayer = document.querySelector('.themes-layer');
const downloadLink = document.querySelector('[data-download-link]');
const downloadTitle = document.querySelector('[data-download-title]');
const downloadLabel = document.querySelector('[data-download-label]');
const downloadControl = document.querySelector('[data-download-control]');
const downloadOptions = [...document.querySelectorAll('[data-download-target]')];
const copyStatus = document.querySelector('[data-copy-status]');
document.querySelectorAll('[data-copy-command]').forEach(button => button.addEventListener('click', async () => {
  const english = document.documentElement.lang === 'en';
  const command = button.closest('.download-command').querySelector('code').textContent.trim();
  button.disabled = true;
  copyStatus.hidden = true;
  try {
    await navigator.clipboard.writeText(command);
    button.textContent = english ? 'Copied' : '已复制';
    copyStatus.textContent = english ? 'Command copied. Paste it into Terminal to run.' : '命令已复制，可粘贴到「终端」运行。';
  } catch {
    button.textContent = english ? 'Copy command' : '复制命令';
    copyStatus.textContent = english ? 'Could not copy. Select and copy the command manually.' : '复制失败，请手动选择并复制上方命令。';
  } finally {
    button.disabled = false;
    copyStatus.hidden = false;
  }
}));
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const mobileLayout = matchMedia('(max-width: 760px)');
let activeThemePreview;
let themePointer;
let dismissedTheme;
let lastThemePointer;
let themeGesture;
let suppressThemeClick = false;
let matchedDownloads = matchDownloadAssets([]);
let selectedDownloadId = 'mac-arm64';
let downloadSelected = false;
const releasesURL = downloadLink?.href;

renderDownloadControl();

const detectDownloadEnvironment = async () => {
  const platform = navigator.userAgentData?.platform || navigator.platform || navigator.userAgent || '';
  let architecture = '';
  if (navigator.userAgentData?.getHighEntropyValues) {
    try {
      ({ architecture = '' } = await navigator.userAgentData.getHighEntropyValues(['architecture']));
    } catch {}
  }
  return { platform, architecture };
};

function renderDownloadControl() {
  if (!downloadLink || !downloadTitle || !downloadLabel) return;
  const english = document.documentElement.lang === 'en';
  const target = downloadTargets.find(item => item.id === selectedDownloadId) || downloadTargets[0];
  const asset = matchedDownloads[target.id];

  downloadTitle.textContent = asset?.download_url
    ? (english ? 'Download installer' : '下载安装包')
    : (english ? 'View releases' : '查看发布版本');
  downloadLabel.textContent = target.label[english ? 'en' : 'zh'];
  if (asset?.download_url) {
    downloadLink.href = new URL(asset.download_url, document.baseURI).href;
    downloadLink.download = asset.name;
  } else {
    downloadLink.href = releasesURL;
    downloadLink.removeAttribute('download');
  }

  downloadOptions.forEach(option => {
    const optionTarget = downloadTargets.find(item => item.id === option.dataset.downloadTarget);
    option.querySelector('span').textContent = optionTarget.label[english ? 'en' : 'zh'];
    option.setAttribute('aria-pressed', String(option.dataset.downloadTarget === selectedDownloadId));
  });
}

const closeDownloadPaper = () => {
  if (!downloadControl?.open) return;
  const focusInside = downloadControl.contains(document.activeElement);
  downloadControl.open = false;
  if (focusInside) downloadControl.querySelector('summary').focus({ preventScroll: true });
};

downloadOptions.forEach(option => option.addEventListener('click', () => {
  downloadSelected = true;
  selectedDownloadId = option.dataset.downloadTarget;
  renderDownloadControl();
}));

document.addEventListener('keydown', event => {
  if (event.key === 'Escape') closeDownloadPaper();
});

detectDownloadEnvironment().then(async environment => {
  const preferredIds = preferredDownloadIds(environment);
  if (!downloadSelected) selectedDownloadId = preferredIds[0];
  try {
    const response = await fetch(new URL('./release.json', import.meta.url), { cache: 'no-store' });
    if (!response.ok) throw new Error('Download information unavailable');
    const release = await response.json();
    matchedDownloads = matchDownloadAssets(release.available && Array.isArray(release.assets) ? release.assets : []);
  } catch {}
  if (!downloadSelected) selectedDownloadId = chooseDownloadId(matchedDownloads, preferredIds);
  renderDownloadControl();
});

const themeMotions = new Map();

function changeTheme(preview, update) {
  if (!preview || reducedMotion.matches) { update(); return; }
  const motion = getComputedStyle(document.documentElement);
  const options = {
    duration: parseFloat(motion.getPropertyValue('--duration-lg')),
    easing: motion.getPropertyValue('--ease-in-out').trim(),
  };
  if (!options.duration || !CSS.supports('animation-timing-function', options.easing)) {
    update();
    return;
  }
  const screenshot = preview.querySelector('.theme-window');
  const before = preview.getBoundingClientRect();
  const beforeShot = themePictureBounds(preview) ?? screenshot.getBoundingClientRect();
  themeMotions.get(preview)?.forEach(animation => animation.cancel());

  const desktop = !mobileLayout.matches;
  if (desktop) preview.dataset.morphing = '';
  screenshot.dataset.morphing = '';
  update();

  const after = preview.getBoundingClientRect();
  const shotBox = screenshot.getBoundingClientRect();
  const afterShot = themePictureBounds(preview) ?? shotBox;
  const scaleX = after.width / preview.offsetWidth;
  const scaleY = after.height / preview.offsetHeight;
  const ratioX = desktop ? before.width / after.width : 1;
  const ratioY = desktop ? before.height / after.height : 1;
  const animations = [];
  const transform = (x, y, sx, sy) => `translate(${x}px, ${y}px) scale(${sx}, ${sy})`;
  if (desktop) {
    // Layout has already taken the final size. Ease the painted box from its
    // last visible rectangle, including when a close interrupts an open.
    animations.push(preview.animate([
      { transform: transform((before.left - after.left) / scaleX, (before.top - after.top) / scaleY, ratioX, ratioY) },
      { transform: 'none' },
    ], options));
  }
  // Align the fitted image inside the window. The clip box's aspect ratio
  // changes across states, but the screenshot should keep its proportions.
  const shotScaleX = beforeShot.width / (afterShot.width * ratioX);
  const shotScaleY = beforeShot.height / (afterShot.height * ratioY);
  const shotX = ((beforeShot.left - before.left) / ratioX - (shotBox.left - after.left)
    - (afterShot.left - shotBox.left) * shotScaleX) / scaleX;
  const shotY = ((beforeShot.top - before.top) / ratioY - (shotBox.top - after.top)
    - (afterShot.top - shotBox.top) * shotScaleY) / scaleY;
  animations.push(screenshot.animate([
    { transform: 'translate(-50%, -50%) ' + transform(shotX, shotY, shotScaleX, shotScaleY) },
    { transform: 'translate(-50%, -50%)' },
  ], options));
  themeMotions.set(preview, animations);
  Promise.allSettled(animations.map(animation => animation.finished)).then(() => {
    if (themeMotions.get(preview) !== animations) return;
    themeMotions.delete(preview);
    delete preview.dataset.morphing;
    delete screenshot.dataset.morphing;
    if (!activeThemePreview && lastThemePointer) updateThemeHover(lastThemePointer);
  });
}
reducedMotion.addEventListener('change', () => {
  if (reducedMotion.matches) {
    for (const animations of themeMotions.values()) {
      animations.forEach(animation => animation.cancel());
    }
  }
});

const activateThemePreview = preview => {
  if (document.documentElement.dataset.scene !== '3' || (!mobileLayout.matches && enteringSceneFour())) return;
  if (activeThemePreview === preview) return;
  changeTheme(preview, () => { document.documentElement.dataset.theme = preview.dataset.theme; });
  activeThemePreview = preview;
};

const resetThemePreview = () => {
  if (activeThemePreview) delete activeThemePreview.dataset.swipe;
  if (activeThemePreview?.dataset.defaultVariant) activeThemePreview.dataset.variant = activeThemePreview.dataset.defaultVariant;
  else if (activeThemePreview) delete activeThemePreview.dataset.variant;
  changeTheme(activeThemePreview, () => { delete document.documentElement.dataset.theme; });
  activeThemePreview = undefined;
  themePointer = undefined;
  dismissedTheme = undefined;
  themesLayer.style.cursor = '';
};
const enteringSceneFour = () => scrollY + innerHeight >= chapters[3].offsetTop;

// object-fit 的图片盒子含留白；只有实际截图算作悬停区域。
const themePictureBounds = preview => {
  const frame = preview.querySelector('.theme-window');
  const box = frame.getBoundingClientRect();
  const img = preview.querySelector('.theme-track img');
  if (!img.naturalWidth || !img.naturalHeight || !frame.offsetWidth || !frame.offsetHeight) return;
  const scale = Math.min(frame.offsetWidth / img.naturalWidth, frame.offsetHeight / img.naturalHeight);
  const width = img.naturalWidth * scale * box.width / frame.offsetWidth;
  const height = img.naturalHeight * scale * box.height / frame.offsetHeight;
  return { left: box.left + (box.width - width) / 2, top: box.top + (box.height - height) / 2, width, height };
};
const containsPointer = (bounds, event) => bounds && event.clientX >= bounds.left && event.clientX <= bounds.left + bounds.width && event.clientY >= bounds.top && event.clientY <= bounds.top + bounds.height;
const themeResizing = preview => themeMotions.get(preview)?.some(animation => animation.playState === 'running');

const updateThemeHover = event => {
  if (mobileLayout.matches || event.pointerType === 'touch' || document.documentElement.dataset.scene !== '3' || enteringSceneFour()) return;
  lastThemePointer = event;
  if (activeThemePreview) {
    // 放大过程中分界线会移动；不把它误判成用户切换主题或离开截图。
    if (themeResizing(activeThemePreview)) {
      if (!containsPointer(themesLayer.getBoundingClientRect(), event)) resetThemePreview();
      return;
    }
    if (themePointer && Math.hypot(event.clientX - themePointer.x, event.clientY - themePointer.y) < 12) return;
    const bounds = themePictureBounds(activeThemePreview);
    if (!containsPointer(bounds, event)) {
      const dismissed = themePointer && { preview: activeThemePreview, bounds: themePointer.entryBounds };
      resetThemePreview();
      dismissedTheme = dismissed;
      return;
    }
    themesLayer.style.cursor = 'ew-resize';
    if (!themePointer) { themePointer = { x: event.clientX, y: event.clientY, entryBounds: bounds }; return; }
    // 进入时保留原来的浅/深色；微小手抖不触发横向切换。
    if (Math.abs(event.clientX - themePointer.x) < 12) return;
    const middle = bounds.left + bounds.width / 2;
    const deadZone = bounds.width * .06;
    if (event.clientX < middle - deadZone) activeThemePreview.dataset.variant = 'light';
    if (event.clientX > middle + deadZone) activeThemePreview.dataset.variant = 'dark';
    return;
  }
  // 缩回后必须重新进入截图，避免同一个指针位置把卡片反复打开。
  if (dismissedTheme) {
    if (containsPointer(dismissedTheme.bounds, event)) return;
    dismissedTheme = undefined;
  }
  if (themePreviews.some(themeResizing)) return;
  const preview = themePreviews.find(preview => containsPointer(themePictureBounds(preview), event));
  themesLayer.style.cursor = preview ? 'zoom-in' : '';
  if (!preview) return;
  const entryBounds = themePictureBounds(preview);
  activateThemePreview(preview);
  themePointer = { x: event.clientX, y: event.clientY, entryBounds };
};
document.addEventListener('pointermove', updateThemeHover);
document.addEventListener('pointerout', event => {
  if (!mobileLayout.matches && !event.relatedTarget) { lastThemePointer = undefined; resetThemePreview(); }
});

themePreviews.forEach(preview => {
  preview.addEventListener('focus', () => {
    if (mobileLayout.matches) return;
    if (!activeThemePreview || activeThemePreview === preview) activateThemePreview(preview);
  });
  preview.addEventListener('pointerdown', event => {
    if (mobileLayout.matches && activeThemePreview === preview) themeGesture = { x: event.clientX, y: event.clientY };
  });
  preview.addEventListener('pointerup', event => {
    if (!themeGesture || !mobileLayout.matches || activeThemePreview !== preview) return;
    const deltaX = event.clientX - themeGesture.x;
    const deltaY = event.clientY - themeGesture.y;
    themeGesture = undefined;
    if (Math.abs(deltaX) < 36 || Math.abs(deltaX) <= Math.abs(deltaY) * 1.2) return;
    const variant = deltaX < 0 ? 'dark' : 'light';
    if (preview.dataset.variant !== variant && !reducedMotion.matches) preview.dataset.swipe = '';
    preview.dataset.variant = variant;
    suppressThemeClick = true;
  });
  const clearSwipeTiming = event => {
    if (event.target.matches('.theme-track') && event.propertyName === 'transform') delete preview.dataset.swipe;
  };
  preview.addEventListener('transitionend', clearSwipeTiming);
  preview.addEventListener('transitioncancel', clearSwipeTiming);
  preview.addEventListener('pointercancel', () => { themeGesture = undefined; });
  preview.addEventListener('click', () => {
    if (!mobileLayout.matches) return;
    if (suppressThemeClick) {
      suppressThemeClick = false;
      return;
    }
    if (activeThemePreview !== preview) {
      activateThemePreview(preview);
      return;
    }
    resetThemePreview();
  });
  preview.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      delete preview.dataset.swipe;
      preview.dataset.variant = event.key === 'ArrowLeft' ? 'light' : 'dark';
    }
    if (event.key === 'Escape') resetThemePreview();
  });
});
themesLayer.addEventListener('focusout', event => {
  if (document.documentElement.dataset.scene === '3' && !enteringSceneFour() && !themesLayer.contains(event.relatedTarget)) resetThemePreview();
});

document.querySelectorAll('[data-jump], a[href^="#scene-"]').forEach(control => {
  control.addEventListener('click', event => {
    if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    const hash = control.getAttribute('href');
    if (hash && hash !== location.hash) history.pushState(null, '', hash);
    const target = document.getElementById(control.dataset.jump || hash.slice(1));
    window.WeiBeiMotion.scrollIntoView(target, { duration: 'lg' });
  });
});

const ratios = new Map(chapters.map(chapter => [chapter, 0]));
// Fixed, overlapping scene layers are all near the viewport: native lazy loading
// cannot distinguish them. Request each scene's images as its chapter approaches.
const imageObserver = new IntersectionObserver(entries => {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    document.querySelectorAll(`img[data-image-scene="${entry.target.dataset.scene}"]`).forEach(img => {
      img.loading = 'eager';
      img.decoding = 'async';
      if (img.dataset.srcset) img.srcset = img.dataset.srcset;
      img.src = img.dataset.src;
      delete img.dataset.src;
      delete img.dataset.srcset;
      delete img.dataset.imageScene;
    });
    imageObserver.unobserve(entry.target);
  }
}, { rootMargin: '25% 0px' });
chapters.forEach(chapter => imageObserver.observe(chapter));
const observer = new IntersectionObserver(entries => {
  entries.forEach(entry => ratios.set(entry.target, entry.intersectionRatio));
  const activeChapter = chapters.reduce((best, chapter) => ratios.get(chapter) > ratios.get(best) ? chapter : best);
  const activeIndex = chapters.indexOf(activeChapter);
  document.documentElement.dataset.scene = String(activeIndex + 1);
  document.querySelector('[data-language-toggle]').hash = activeChapter.id;
  document.querySelector('.hero-tagline').inert = activeIndex !== 0;
  experienceLayer.inert = activeIndex !== 1;
  themesLayer.inert = activeIndex !== 2;
  document.querySelector('.release-layer').inert = activeIndex !== 3;
  if (activeIndex !== 2) resetThemePreview();
  if (activeIndex !== 3) closeDownloadPaper();
  railButtons.forEach((button, index) => {
    button.classList.toggle('is-active', index === activeIndex);
    if (index === activeIndex) button.setAttribute('aria-current', 'step');
    else button.removeAttribute('aria-current');
  });
}, { threshold: [.25, .5, .75] });

chapters.forEach(chapter => observer.observe(chapter));
window.addEventListener('pagehide', () => {
  try {
    sessionStorage.setItem('weibei-home-position', JSON.stringify({
      scene: `scene-${document.documentElement.dataset.scene}`,
      progress: scrollY / Math.max(1, document.documentElement.scrollHeight - innerHeight)
    }));
  } catch {}
});
window.addEventListener('pageshow', event => {
  if (event.persisted || performance.getEntriesByType('navigation')[0]?.type === 'back_forward') return;
  const initialChapter = chapters.find(chapter => `#${chapter.id}` === location.hash);
  if (!initialChapter) return;
  let top = initialChapter.offsetTop;
  try {
    const saved = JSON.parse(sessionStorage.getItem('weibei-home-position'));
    if (saved?.scene === initialChapter.id && Number.isFinite(saved.progress) && saved.progress >= 0 && saved.progress <= 1) {
      top = saved.progress * (document.documentElement.scrollHeight - innerHeight);
    }
  } catch {}
  scrollTo({ top, behavior: 'instant' });
});
