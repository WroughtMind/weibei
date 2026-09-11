import { chooseDownloadId, downloadTargets, matchDownloadAssets, preferredDownloadIds } from './download-selection.mjs';

const chapters = [...document.querySelectorAll('.chapter')];
const railButtons = [...document.querySelectorAll('.scene-rail button')];
const experiencePages = [...document.querySelectorAll('.experience-page')];
const experienceLabel = document.querySelector('.experience-mode-label');
const experienceLayer = document.querySelector('.experience-layer');
const experiencePager = document.querySelector('.window-pager');
const experienceTabsContainer = document.querySelector('.experience-tabs');
const experienceTabs = [...document.querySelectorAll('[data-mode-target]')];
const themePreviews = [...document.querySelectorAll('.theme-preview')];
const themesLayer = document.querySelector('.themes-layer');
const downloadLink = document.querySelector('[data-download-link]');
const downloadTitle = document.querySelector('[data-download-title]');
const downloadCaption = document.querySelector('[data-download-caption]');
const downloadLabel = document.querySelector('[data-download-label]');
const downloadControl = document.querySelector('[data-download-control]');
const downloadToggle = document.querySelector('[data-download-toggle]');
const downloadMenu = document.querySelector('[data-download-menu]');
const downloadOptions = [...document.querySelectorAll('[data-download-target]')];
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const mobileLayout = matchMedia('(max-width: 760px)');
let activeMode = 0;
let experiencePaused = false;
let experienceSelected = false;
let experienceTimer;
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
  if (!downloadLink || !downloadTitle || !downloadCaption || !downloadLabel) return;
  const english = document.documentElement.lang === 'en';
  const target = downloadTargets.find(item => item.id === selectedDownloadId) || downloadTargets[0];
  const asset = matchedDownloads[target.id];

  downloadTitle.textContent = english ? 'Download WeiBei' : '下载 WeiBei';
  downloadCaption.textContent = english ? 'Version' : '版本';
  downloadLabel.textContent = target.label[english ? 'en' : 'zh'];
  downloadToggle.setAttribute('aria-label', english ? 'Choose download version' : '选择下载版本');
  if (asset?.download_url) {
    downloadLink.href = new URL(asset.download_url, document.baseURI).href;
    downloadLink.download = asset.name;
  } else {
    downloadLink.href = releasesURL;
    downloadLink.removeAttribute('download');
  }

  downloadOptions.forEach(option => {
    const optionTarget = downloadTargets.find(item => item.id === option.dataset.downloadTarget);
    option.querySelector('span').textContent = optionTarget.menuLabel[english ? 'en' : 'zh'];
    option.classList.toggle('is-selected', option.dataset.downloadTarget === selectedDownloadId);
  });
}

const closeDownloadMenu = () => {
  if (!downloadMenu || !downloadToggle) return;
  downloadMenu.hidden = true;
  downloadToggle.setAttribute('aria-expanded', 'false');
};

downloadToggle?.addEventListener('click', () => {
  const opening = downloadMenu.hidden;
  downloadMenu.hidden = !opening;
  downloadToggle.setAttribute('aria-expanded', String(opening));
});

downloadOptions.forEach(option => option.addEventListener('click', () => {
  downloadSelected = true;
  selectedDownloadId = option.dataset.downloadTarget;
  renderDownloadControl();
  closeDownloadMenu();
}));

document.addEventListener('pointerdown', event => {
  if (!downloadControl?.contains(event.target)) closeDownloadMenu();
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') closeDownloadMenu();
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

const setExperienceMode = nextMode => {
  activeMode = (nextMode + experiencePages.length) % experiencePages.length;
  experiencePages.forEach((page, index) => {
    const active = index === activeMode;
    page.classList.toggle('is-active', active);
    page.setAttribute('aria-hidden', String(!active));
  });
  const mode = experiencePages[activeMode].dataset.mode;
  experienceLabel.dataset.mode = mode;
  experienceTabs.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.modeTarget === mode)));
};

const startExperienceRotation = () => {
  clearInterval(experienceTimer);
  experienceTimer = setInterval(() => {
    if (!experiencePaused && !experienceSelected && !reducedMotion && !document.hidden && document.documentElement.dataset.scene === '2') setExperienceMode(activeMode + 1);
  }, 4400);
};

document.querySelectorAll('.window-pager button').forEach(button => {
  button.addEventListener('click', () => {
    experienceSelected = true;
    setExperienceMode(activeMode + Number(button.dataset.direction));
  });
});

experienceTabs.forEach(button => button.addEventListener('click', () => {
  experienceSelected = true;
  setExperienceMode(experiencePages.findIndex(page => page.dataset.mode === button.dataset.modeTarget));
}));

[experienceLayer, experiencePager, experienceTabsContainer].forEach(element => {
  element.addEventListener('pointerenter', () => { experiencePaused = true; });
  element.addEventListener('pointerleave', () => { experiencePaused = false; startExperienceRotation(); });
});
setExperienceMode(0);
startExperienceRotation();

const activateThemePreview = preview => {
  if (document.documentElement.dataset.scene !== '3' || (!mobileLayout.matches && enteringSceneFour())) return;
  if (activeThemePreview === preview) return;
  document.documentElement.dataset.theme = preview.dataset.theme;
  activeThemePreview = preview;
};

const resetThemePreview = () => {
  if (activeThemePreview?.dataset.defaultVariant) activeThemePreview.dataset.variant = activeThemePreview.dataset.defaultVariant;
  else if (activeThemePreview) delete activeThemePreview.dataset.variant;
  delete document.documentElement.dataset.theme;
  activeThemePreview = undefined;
  themePointer = undefined;
  dismissedTheme = undefined;
  themesLayer.style.cursor = '';
};
const enteringSceneFour = () => scrollY + innerHeight >= chapters[3].offsetTop;

// object-fit 的图片盒子含留白；只有实际截图算作悬停区域。
const themePictureBounds = preview => {
  const box = preview.querySelector('.theme-window').getBoundingClientRect();
  const img = preview.querySelector('.theme-track img');
  if (!img.naturalWidth || !img.naturalHeight) return;
  const scale = Math.min(box.width / img.naturalWidth, box.height / img.naturalHeight);
  const width = img.naturalWidth * scale, height = img.naturalHeight * scale;
  return { left: box.left + (box.width - width) / 2, top: box.top + (box.height - height) / 2, width, height };
};
const containsPointer = (bounds, event) => bounds && event.clientX >= bounds.left && event.clientX <= bounds.left + bounds.width && event.clientY >= bounds.top && event.clientY <= bounds.top + bounds.height;
const themeResizing = preview => preview.getAnimations().some(animation => animation instanceof CSSTransition && ['left', 'top', 'width', 'height'].includes(animation.transitionProperty) && animation.playState === 'running');

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
themesLayer.addEventListener('transitionend', event => {
  // 缩回途中已经移到另一张截图时，动画结束后接上这次进入，不要求再晃一下鼠标。
  if (event.propertyName === 'width' && event.target.matches('.theme-preview') && !activeThemePreview && lastThemePointer) updateThemeHover(lastThemePointer);
});
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
    preview.dataset.variant = deltaX < 0 ? 'dark' : 'light';
    suppressThemeClick = true;
  });
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
    if (event.key === 'ArrowLeft') preview.dataset.variant = 'light';
    if (event.key === 'ArrowRight') preview.dataset.variant = 'dark';
    if (event.key === 'Escape') resetThemePreview();
  });
});
themesLayer.addEventListener('focusout', event => {
  if (document.documentElement.dataset.scene === '3' && !enteringSceneFour() && !themesLayer.contains(event.relatedTarget)) resetThemePreview();
});

railButtons.forEach(button => {
  button.addEventListener('click', () => {
    document.getElementById(button.dataset.jump).scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth' });
  });
});

const ratios = new Map(chapters.map(chapter => [chapter, 0]));
let sceneFourPreloaded = false;
const preloadSceneFour = () => {
  if (sceneFourPreloaded) return;
  sceneFourPreloaded = true;
  // Decode the displayed elements (including their selected srcset), not detached copies.
  document.querySelectorAll('.release-layer img').forEach(img => {
    img.loading = 'eager';
    img.decoding = 'async';
    img.decode().catch(() => {});
  });
};
const observer = new IntersectionObserver(entries => {
  entries.forEach(entry => ratios.set(entry.target, entry.intersectionRatio));
  const activeChapter = chapters.reduce((best, chapter) => ratios.get(chapter) > ratios.get(best) ? chapter : best);
  const activeIndex = chapters.indexOf(activeChapter);
  document.documentElement.dataset.scene = String(activeIndex + 1);
  document.querySelector('[data-language-toggle]').hash = activeChapter.id;
  document.querySelector('.hero-tagline').inert = activeIndex !== 0;
  [experienceLayer, experiencePager, experienceTabsContainer].forEach(element => { element.inert = activeIndex !== 1; });
  themesLayer.inert = activeIndex !== 2;
  document.querySelector('.release-layer').inert = activeIndex !== 3;
  if (activeIndex !== 2) resetThemePreview();
  if (activeIndex !== 3) closeDownloadMenu();
  if (activeIndex >= 1) preloadSceneFour();
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
  if (event.persisted) return;
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
