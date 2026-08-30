import { chooseDownloadId, downloadTargets, matchDownloadAssets, preferredDownloadIds } from './download-selection.mjs';

const chapters = [...document.querySelectorAll('.chapter')];
const railButtons = [...document.querySelectorAll('.scene-rail button')];
const experiencePages = [...document.querySelectorAll('.experience-page')];
const experienceLabel = document.querySelector('.experience-mode-label');
const experienceLayer = document.querySelector('.experience-layer');
const experiencePager = document.querySelector('.window-pager');
const themePreviews = [...document.querySelectorAll('.theme-preview')];
const themesLayer = document.querySelector('.themes-layer');
const languageToggle = document.querySelector('[data-language-toggle]');
const downloadLink = document.querySelector('[data-download-link]');
const downloadTitle = document.querySelector('[data-download-title]');
const downloadCaption = document.querySelector('[data-download-caption]');
const downloadLabel = document.querySelector('[data-download-label]');
const downloadControl = document.querySelector('[data-download-control]');
const downloadToggle = document.querySelector('[data-download-toggle]');
const downloadMenu = document.querySelector('[data-download-menu]');
const downloadOptions = [...document.querySelectorAll('[data-download-target]')];
const translatable = [...document.querySelectorAll('[data-en]')];
const labelled = [...document.querySelectorAll('[data-en-label]')];
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const mobileLayout = matchMedia('(max-width: 760px)');
let activeMode = 0;
let experiencePaused = false;
let experienceTimer;
let activeThemePreview;
let matchedDownloads = matchDownloadAssets([]);
let selectedDownloadId = 'mac-arm64';
const downloadFallback = downloadLink?.href;

translatable.forEach(element => { element.dataset.zh = element.textContent; });
labelled.forEach(element => { element.dataset.zhLabel = element.getAttribute('aria-label'); });

const setLanguage = language => {
  const english = language === 'en';
  document.documentElement.lang = english ? 'en' : 'zh-CN';
  document.title = english ? 'WeiBei · Read, ask, and write in one workspace' : '魏碑 · 把读、问、写放回同一张桌面';
  translatable.forEach(element => { element.textContent = english ? element.dataset.en : element.dataset.zh; });
  labelled.forEach(element => { element.setAttribute('aria-label', english ? element.dataset.enLabel : element.dataset.zhLabel); });
  languageToggle.setAttribute('aria-label', english ? '切换为中文' : 'Switch to English');
  languageToggle.setAttribute('aria-pressed', String(english));
  localStorage.setItem('weibei-language', language);
  renderDownloadControl();
};

languageToggle.addEventListener('click', () => setLanguage(document.documentElement.lang === 'en' ? 'zh-CN' : 'en'));
setLanguage(localStorage.getItem('weibei-language') === 'en' ? 'en' : 'zh-CN');

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
    downloadLink.href = downloadFallback;
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
  selectedDownloadId = preferredIds[0];
  try {
    const response = await fetch('./release.json', { cache: 'no-store' });
    const release = response.ok ? await response.json() : { assets: [] };
    matchedDownloads = matchDownloadAssets(release.available && Array.isArray(release.assets) ? release.assets : []);
  } catch {}
  selectedDownloadId = chooseDownloadId(matchedDownloads, preferredIds);
  renderDownloadControl();
});

const setExperienceMode = nextMode => {
  activeMode = (nextMode + experiencePages.length) % experiencePages.length;
  experiencePages.forEach((page, index) => {
    const active = index === activeMode;
    page.classList.toggle('is-active', active);
    page.setAttribute('aria-hidden', String(!active));
  });
  experienceLabel.dataset.mode = experiencePages[activeMode].dataset.mode;
};

const startExperienceRotation = () => {
  clearInterval(experienceTimer);
  experienceTimer = setInterval(() => {
    if (!experiencePaused && !reducedMotion && !document.hidden && document.documentElement.dataset.scene === '2') setExperienceMode(activeMode + 1);
  }, 4400);
};

document.querySelectorAll('.window-pager button').forEach(button => {
  button.addEventListener('click', () => {
    setExperienceMode(activeMode + Number(button.dataset.direction));
    startExperienceRotation();
  });
});

[experienceLayer, experiencePager].forEach(element => {
  element.addEventListener('pointerenter', () => { experiencePaused = true; });
  element.addEventListener('pointerleave', () => { experiencePaused = false; startExperienceRotation(); });
});
setExperienceMode(0);
startExperienceRotation();

const activateThemePreview = preview => {
  if (activeThemePreview === preview) return;
  document.documentElement.dataset.theme = preview.dataset.theme;
  activeThemePreview = preview;
};

const resetThemePreview = () => {
  if (activeThemePreview?.dataset.defaultVariant) activeThemePreview.dataset.variant = activeThemePreview.dataset.defaultVariant;
  else if (activeThemePreview) delete activeThemePreview.dataset.variant;
  delete document.documentElement.dataset.theme;
  activeThemePreview = undefined;
};
const enteringSceneFour = () => scrollY + innerHeight >= chapters[3].offsetTop;

themePreviews.forEach(preview => {
  preview.addEventListener('pointerenter', () => {
    if (!mobileLayout.matches && !activeThemePreview) activateThemePreview(preview);
  });
  preview.addEventListener('focus', () => {
    if (mobileLayout.matches) return;
    if (!activeThemePreview || activeThemePreview === preview) activateThemePreview(preview);
  });
  preview.addEventListener('pointermove', event => {
    if (mobileLayout.matches || activeThemePreview !== preview) return;
    const bounds = preview.getBoundingClientRect();
    const middle = bounds.left + bounds.width / 2;
    const deadZone = bounds.width * .06;
    if (event.clientX < middle - deadZone) preview.dataset.variant = 'light';
    if (event.clientX > middle + deadZone) preview.dataset.variant = 'dark';
  });
  preview.addEventListener('mouseleave', () => {
    if (mobileLayout.matches) return;
    if (preview.dataset.defaultVariant) preview.dataset.variant = preview.dataset.defaultVariant;
    else delete preview.dataset.variant;
  });
  preview.addEventListener('click', () => {
    if (!mobileLayout.matches) return;
    if (activeThemePreview !== preview) {
      activateThemePreview(preview);
      return;
    }
    preview.dataset.variant = preview.dataset.variant === 'dark' ? 'light' : 'dark';
  });
  preview.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft') preview.dataset.variant = 'light';
    if (event.key === 'ArrowRight') preview.dataset.variant = 'dark';
    if (event.key === 'Escape') resetThemePreview();
  });
});
themesLayer.addEventListener('pointerleave', () => { if (!mobileLayout.matches && document.documentElement.dataset.scene === '3' && !enteringSceneFour()) resetThemePreview(); });
themesLayer.addEventListener('focusout', event => {
  if (document.documentElement.dataset.scene === '3' && !enteringSceneFour() && !themesLayer.contains(event.relatedTarget)) resetThemePreview();
});

railButtons.forEach(button => {
  button.addEventListener('click', () => {
    document.getElementById(button.dataset.jump).scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth' });
  });
});

const ratios = new Map(chapters.map(chapter => [chapter, 0]));
const observer = new IntersectionObserver(entries => {
  entries.forEach(entry => ratios.set(entry.target, entry.intersectionRatio));
  const activeChapter = chapters.reduce((best, chapter) => ratios.get(chapter) > ratios.get(best) ? chapter : best);
  const activeIndex = chapters.indexOf(activeChapter);
  document.documentElement.dataset.scene = String(activeIndex + 1);
  if (activeIndex !== 2) resetThemePreview();
  railButtons.forEach((button, index) => button.classList.toggle('is-active', index === activeIndex));
}, { threshold: [.25, .5, .75] });

chapters.forEach(chapter => observer.observe(chapter));
