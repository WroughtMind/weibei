const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
const PAPER = '#ece7dd';
const SEAL = '#c23a2e';

/* ---------- Language ---------- */

const copy = {
  zh: {
    title: '魏碑 WeiBei · 读、问、记，在同一个窗口',
    description: '魏碑是原生 macOS 阅读与笔记工作台。资料留在本机，AI 只在你需要时接入。',
    checking: '正在查询最新版本…',
    noRelease: '正式安装包还在路上。现在可以用这几行命令从源码运行。',
    latest: version => `最新版本 ${version}`,
    arm: '下载 Apple 芯片版',
    intel: '下载 Intel 版',
    copied: '已复制',
    copyFailed: '复制失败',
    copyLabel: '复制',
    paragraph: n => `第 ${n} 段`,
    tryTarget: '清风徐来，水波不兴'
  },
  en: {
    title: 'WeiBei · Read, ask, and write in one window',
    description: 'A native macOS workbench for reading and notes. Your files stay on your Mac. AI joins only when you call it.',
    checking: 'Checking for the latest release…',
    noRelease: 'The installer is on its way. For now, run WeiBei from source with these commands.',
    latest: version => `Latest release ${version}`,
    arm: 'Download for Apple silicon',
    intel: 'Download for Intel',
    copied: 'Copied',
    copyFailed: 'Copy failed',
    copyLabel: 'Copy',
    paragraph: n => `paragraph ${n}`,
    tryTarget: 'to live deliberately'
  }
};

let lang = 'zh';
const langListeners = [];
const t = () => copy[lang];

function swapAttribute(el, attribute, key) {
  const zhKey = `zh${key}`;
  const enKey = `en${key}`;
  if (el.dataset[zhKey] === undefined) el.dataset[zhKey] = el.getAttribute(attribute) ?? '';
  el.setAttribute(attribute, lang === 'en' ? el.dataset[enKey] : el.dataset[zhKey]);
}

function applyLanguage(next) {
  lang = next === 'en' ? 'en' : 'zh';
  document.documentElement.lang = lang === 'en' ? 'en' : 'zh-CN';
  for (const el of $$('[data-en]')) {
    if (el.dataset.zh === undefined) el.dataset.zh = el.textContent;
    el.textContent = lang === 'en' ? el.dataset.en : el.dataset.zh;
  }
  for (const el of $$('[data-en-alt]')) swapAttribute(el, 'alt', 'Alt');
  for (const el of $$('[data-en-aria-label]')) swapAttribute(el, 'aria-label', 'AriaLabel');
  document.title = t().title;
  $('meta[name="description"]').setAttribute('content', t().description);
  try { localStorage.setItem('wb-lang', lang); } catch {}
  langListeners.forEach(fn => fn(lang));
}

function initialLanguage() {
  const fromQuery = new URLSearchParams(location.search).get('lang');
  if (fromQuery === 'en' || fromQuery === 'zh') return fromQuery;
  try {
    const saved = localStorage.getItem('wb-lang');
    if (saved === 'en' || saved === 'zh') return saved;
  } catch {}
  return (navigator.language || '').toLowerCase().startsWith('zh') ? 'zh' : 'en';
}

/* ---------- Shared stone texture ---------- */

function noiseTile(size, threshold, strength) {
  const tile = document.createElement('canvas');
  tile.width = tile.height = size;
  const tctx = tile.getContext('2d');
  const image = tctx.createImageData(size, size);
  for (let i = 0; i < image.data.length; i += 4) {
    const v = Math.random();
    image.data[i + 3] = v > threshold ? ((v - threshold) / (1 - threshold)) * strength : 0;
  }
  tctx.putImageData(image, 0, 0);
  return tile;
}

function pitStone(ctx, width, height, unit) {
  ctx.save();
  ctx.globalCompositeOperation = 'destination-out';
  const area = (width * height) / (unit * unit);
  ctx.fillStyle = '#000';
  for (let i = 0; i < area / 420; i += 1) {
    ctx.globalAlpha = 0.015 + Math.random() * 0.055;
    ctx.beginPath();
    ctx.ellipse(Math.random() * width, Math.random() * height, (2 + Math.random() ** 2 * 18) * unit, (2 + Math.random() ** 2 * 10) * unit, Math.random() * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;
  ctx.fillStyle = ctx.createPattern(noiseTile(256, 0.84, 190), 'repeat');
  ctx.fillRect(0, 0, width, height);
  ctx.fillStyle = '#000';
  const pits = Math.round(area / 6500);
  for (let i = 0; i < pits; i += 1) {
    ctx.globalAlpha = 0.35 + Math.random() * 0.6;
    ctx.beginPath();
    ctx.arc(Math.random() * width, Math.random() * height, (0.4 + Math.random() ** 3 * 3.2) * unit, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 0.1;
  ctx.lineWidth = 0.7 * unit;
  ctx.strokeStyle = '#000';
  for (let i = 0; i < pits / 14; i += 1) {
    const x = Math.random() * width;
    const y = Math.random() * height;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + (Math.random() - 0.5) * 40 * unit, y + (Math.random() - 0.3) * 120 * unit);
    ctx.stroke();
  }
  ctx.restore();
}

/* ---------- Hero rubbing ---------- */

function initRubbing() {
  const canvas = $('[data-rubbing]');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const texture = document.createElement('canvas');
  const mask = document.createElement('canvas');
  const layer = document.createElement('canvas');
  const tctx = texture.getContext('2d');
  const mctx = mask.getContext('2d');
  const lctx = layer.getContext('2d');
  const box = { x: 120, y: 140, w: 1010, h: 970 };
  const markPaths = $$('#w-mark path').map(path => ({
    shape: new Path2D(path.getAttribute('d')),
    seal: path.hasAttribute('fill')
  }));
  const FLOOR = 0.58;
  const INTRO_MS = 2300;

  let width = 0;
  let height = 0;
  let dpr = 1;
  let scale = 1;
  let ox = 0;
  let oy = 0;
  let base = 0;
  let sealT = 0;
  let introStart = 0;
  let introProgress = 0;
  let introDone = false;
  let lastInput = 0;
  let last = null;
  let raf = 0;

  const toCanvas = (x, y) => [ox + x * scale, oy + y * scale];

  function buildTexture() {
    tctx.clearRect(0, 0, width, height);
    tctx.setTransform(scale, 0, 0, scale, ox, oy);
    tctx.fillStyle = PAPER;
    markPaths.filter(p => !p.seal).forEach(p => tctx.fill(p.shape));
    tctx.setTransform(1, 0, 0, 1, 0, 0);
    pitStone(tctx, width, height, dpr);
  }

  function layout() {
    const rect = canvas.getBoundingClientRect();
    if (!rect.width) return;
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = Math.round(rect.width * dpr);
    height = Math.round(rect.height * dpr);
    for (const c of [canvas, texture, mask, layer]) {
      c.width = width;
      c.height = height;
    }
    scale = Math.min(width / box.w, height / box.h);
    ox = (width - box.w * scale) / 2 - box.x * scale;
    oy = (height - box.h * scale) / 2 - box.y * scale;
    buildTexture();
    draw();
  }

  function dab(x, y, radius, alpha) {
    const g = mctx.createRadialGradient(x, y, 0, x, y, radius);
    g.addColorStop(0, `rgba(255,255,255,${alpha})`);
    g.addColorStop(0.6, `rgba(255,255,255,${alpha * 0.55})`);
    g.addColorStop(1, 'rgba(255,255,255,0)');
    mctx.fillStyle = g;
    mctx.beginPath();
    mctx.arc(x, y, radius, 0, Math.PI * 2);
    mctx.fill();
  }

  function introPoint(p) {
    const rows = 5;
    const [x0, y0] = toCanvas(170, 190);
    const [x1, y1] = toCanvas(1090, 1060);
    const row = Math.min(rows - 1, Math.floor(p * rows));
    const along = p * rows - row;
    const x = row % 2 === 0 ? x0 + (x1 - x0) * along : x1 - (x1 - x0) * along;
    const y = y0 + ((y1 - y0) * (row + 0.5)) / rows + Math.sin(along * Math.PI * 6) * 8 * dpr;
    return [x, y];
  }

  function draw() {
    ctx.clearRect(0, 0, width, height);
    ctx.globalAlpha = base;
    ctx.drawImage(texture, 0, 0);
    ctx.globalAlpha = 1;
    lctx.globalCompositeOperation = 'source-over';
    lctx.clearRect(0, 0, width, height);
    lctx.drawImage(texture, 0, 0);
    lctx.globalCompositeOperation = 'destination-in';
    lctx.drawImage(mask, 0, 0);
    ctx.drawImage(layer, 0, 0);
    if (sealT > 0) {
      const s = 1 + Math.sin(Math.min(sealT, 1) * Math.PI) * 0.35;
      const cx = 1075;
      const cy = 1053;
      ctx.save();
      ctx.setTransform(scale * s, 0, 0, scale * s, ox + cx * scale * (1 - s), oy + cy * scale * (1 - s));
      ctx.globalAlpha = Math.min(sealT * 2, 1);
      ctx.fillStyle = SEAL;
      markPaths.filter(p => p.seal).forEach(p => ctx.fill(p.shape));
      ctx.restore();
    }
  }

  function frame(now) {
    if (!introDone) {
      if (!introStart) introStart = now;
      const next = Math.min((now - introStart) / INTRO_MS, 1);
      const radius = Math.min(width, height) * 0.13;
      for (let p = introProgress; p < next; p += 0.004) {
        const [x, y] = introPoint(p);
        dab(x, y, radius * (0.8 + Math.random() * 0.4), 0.28);
      }
      introProgress = next;
      base = FLOOR * (1 - (1 - next) ** 3);
      if (next >= 1) {
        introDone = true;
        lastInput = now;
      }
    } else {
      mctx.globalCompositeOperation = 'destination-out';
      mctx.fillStyle = 'rgba(0,0,0,0.02)';
      mctx.fillRect(0, 0, width, height);
      mctx.globalCompositeOperation = 'source-over';
    }
    if (introProgress > 0.82 && sealT < 1) sealT = Math.min(1, sealT + 0.045);
    draw();
    raf = !introDone || now - lastInput < 4500 || sealT < 1 ? requestAnimationFrame(frame) : 0;
  }

  const wake = () => { if (!raf) raf = requestAnimationFrame(frame); };

  canvas.addEventListener('pointermove', event => {
    if (reduceMotion.matches || !introDone) return;
    const rect = canvas.getBoundingClientRect();
    const x = (event.clientX - rect.left) * dpr;
    const y = (event.clientY - rect.top) * dpr;
    const radius = Math.min(width, height) * 0.085;
    if (last) {
      const dist = Math.hypot(x - last[0], y - last[1]);
      const steps = Math.max(1, Math.ceil(dist / (radius * 0.3)));
      for (let i = 1; i <= steps; i += 1) {
        dab(last[0] + ((x - last[0]) * i) / steps, last[1] + ((y - last[1]) * i) / steps, radius, 0.2);
      }
    } else {
      dab(x, y, radius, 0.2);
    }
    last = [x, y];
    lastInput = performance.now();
    wake();
  });
  canvas.addEventListener('pointerleave', () => { last = null; });

  new ResizeObserver(() => layout()).observe(canvas);
  layout();

  if (reduceMotion.matches) {
    introDone = true;
    base = 1;
    sealT = 1;
    draw();
  } else {
    wake();
  }
}

/* ---------- Footer texture ---------- */

function initFooterTexture() {
  const word = $('.foot__word');
  if (!word) return;
  const size = 360;
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const cctx = c.getContext('2d');
  cctx.fillStyle = 'rgba(236,231,221,0.2)';
  cctx.fillRect(0, 0, size, size);
  pitStone(cctx, size, size, 1);
  word.style.setProperty('--rub', `url(${c.toDataURL('image/png')})`);
  word.classList.add('has-texture');
}

/* ---------- Page chrome ---------- */

function initNav() {
  const nav = $('[data-nav]');
  new IntersectionObserver(([entry]) => {
    nav.classList.toggle('is-scrolled', !entry.isIntersecting);
  }).observe($('.top-sentinel'));
}

function initRise() {
  const groups = [
    '.reveal__caption',
    '.verb > *',
    '.demo__head > *',
    '.demo__stage > *',
    '.themes__list > *',
    '.themes__stage',
    '.local__title',
    '.bento > .tile',
    '.models__head > *',
    '.webi__head > *',
    '.start__copy > *',
    '.terminal'
  ];
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-in');
      observer.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
  for (const selector of groups) {
    $$(selector).forEach((el, i) => {
      el.dataset.rise = '';
      el.style.setProperty('--i', String(i % 6));
      observer.observe(el);
    });
  }
}

function initVerbs() {
  const glyphs = $$('.verbs__glyphs span');
  const ticks = $$('.verbs__ticks li');
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      const index = Number(entry.target.dataset.verb);
      glyphs.forEach((g, i) => g.classList.toggle('is-active', i === index));
      ticks.forEach((tick, i) => tick.classList.toggle('is-active', i === index));
    }
  }, { rootMargin: '-50% 0px -50% 0px' });
  $$('[data-verb]').forEach(el => observer.observe(el));
}

/* ---------- Selection demo ---------- */

function initDemo() {
  const page = $('.demo__page');
  const text = $('[data-demo-text]');
  const capsule = $('[data-capsule]');
  const capsuleQuote = $('[data-capsule-quote]');
  const empty = $('[data-demo-empty]');
  const answer = $('[data-demo-answer]');
  const answerQuote = $('[data-answer-quote]');
  const notes = $('[data-demo-notes]');
  const source = $('[data-demo-source]');
  const cite = $('[data-cite]');
  const canHighlight = typeof CSS !== 'undefined' && 'highlights' in CSS && typeof Highlight !== 'undefined';
  let current = null;
  let citeRange = null;
  let noteRanges = [];
  let pending = 0;

  const clip = (value, max) => (value.length > max ? `${value.slice(0, max)}…` : value);

  function hideCapsule() {
    capsule.hidden = true;
  }

  function placeCapsule(range) {
    const rects = [...range.getClientRects()].filter(r => r.width > 1);
    const first = rects[0] ?? range.getBoundingClientRect();
    const lastRect = rects[rects.length - 1] ?? first;
    const box = page.getBoundingClientRect();
    capsule.hidden = false;
    const cw = capsule.offsetWidth;
    const ch = capsule.offsetHeight;
    const left = Math.min(Math.max(first.left + first.width / 2 - cw / 2 - box.left, 12), box.width - cw - 12);
    let top = first.top - box.top - ch - 10;
    if (top < 8) top = lastRect.bottom - box.top + 10;
    capsule.style.left = `${left}px`;
    capsule.style.top = `${top}px`;
  }

  function readSelection() {
    pending = 0;
    const selection = getSelection();
    if (!selection || !selection.rangeCount || selection.isCollapsed) return hideCapsule();
    const range = selection.getRangeAt(0);
    if (!text.contains(range.commonAncestorContainer)) return hideCapsule();
    const value = selection.toString().replace(/\s+/g, ' ').trim();
    if (!value) return hideCapsule();
    current = { range: range.cloneRange(), value };
    capsuleQuote.textContent = clip(value, 28);
    placeCapsule(range);
  }

  document.addEventListener('selectionchange', () => {
    if (!pending) pending = requestAnimationFrame(readSelection);
  });

  capsule.addEventListener('pointerdown', event => event.preventDefault());

  function paragraphIndex(range) {
    const node = range.startContainer.nodeType === 1 ? range.startContainer : range.startContainer.parentElement;
    return $$('p', text).indexOf(node.closest('p')) + 1;
  }

  function paintNotes() {
    if (canHighlight) CSS.highlights.set('wb-note', new Highlight(...noteRanges));
  }

  $('[data-capsule-ask]').addEventListener('click', () => {
    if (!current) return;
    citeRange = current.range;
    answerQuote.textContent = clip(current.value, 40);
    empty.hidden = true;
    answer.hidden = false;
    answer.style.animation = 'none';
    void answer.offsetWidth;
    answer.style.animation = '';
    getSelection().removeAllRanges();
    hideCapsule();
  });

  $('[data-capsule-note]').addEventListener('click', () => {
    if (!current) return;
    const item = document.createElement('li');
    const quote = document.createElement('span');
    const where = document.createElement('small');
    quote.textContent = clip(current.value, 60);
    where.textContent = `${source.textContent} · ${t().paragraph(paragraphIndex(current.range))}`;
    item.append(quote, where);
    notes.prepend(item);
    while (notes.children.length > 3) notes.lastElementChild.remove();
    noteRanges = [current.range, ...noteRanges].slice(0, 3);
    paintNotes();
    empty.hidden = true;
    notes.hidden = false;
    getSelection().removeAllRanges();
    hideCapsule();
  });

  const lightCite = on => {
    if (!canHighlight) return;
    if (on && citeRange) CSS.highlights.set('wb-cite', new Highlight(citeRange));
    else CSS.highlights.delete('wb-cite');
  };
  cite.addEventListener('pointerenter', () => lightCite(true));
  cite.addEventListener('pointerleave', () => lightCite(false));
  cite.addEventListener('focus', () => lightCite(true));
  cite.addEventListener('blur', () => lightCite(false));
  cite.addEventListener('click', () => {
    lightCite(true);
    setTimeout(() => lightCite(false), 1600);
  });

  $('[data-demo-try]').addEventListener('click', () => {
    const target = t().tryTarget;
    for (const p of $$('p', text)) {
      const node = p.firstChild;
      const at = node?.textContent.indexOf(target) ?? -1;
      if (at < 0) continue;
      const range = document.createRange();
      range.setStart(node, at);
      range.setEnd(node, at + target.length);
      const selection = getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      page.scrollIntoView({ behavior: reduceMotion.matches ? 'auto' : 'smooth', block: 'nearest' });
      return;
    }
  });

  langListeners.push(next => {
    source.textContent = next === 'en' ? source.dataset.enSource : source.dataset.zhSource;
    current = null;
    citeRange = null;
    noteRanges = [];
    if (canHighlight) {
      CSS.highlights.delete('wb-note');
      CSS.highlights.delete('wb-cite');
    }
    notes.replaceChildren();
    notes.hidden = true;
    answer.hidden = true;
    empty.hidden = false;
    hideCapsule();
  });
}

/* ---------- Themes ---------- */

function initThemes() {
  const section = $('[data-themes]');
  const frame = $('[data-theme-frame]');
  const buttons = $$('button[data-src]', section);
  const altFor = button => (lang === 'en' ? button.dataset.altEn : button.dataset.alt);

  buttons.forEach(button => {
    button.addEventListener('pointerenter', () => { new Image().src = button.dataset.src; }, { once: true });
    button.addEventListener('click', async () => {
      if (button.getAttribute('aria-pressed') === 'true') return;
      buttons.forEach(b => b.setAttribute('aria-pressed', String(b === button)));
      section.style.setProperty('--tint', button.dataset.tint);
      const img = new Image(2242, 1596);
      img.src = button.dataset.src;
      img.alt = altFor(button);
      img.decoding = 'async';
      try { await img.decode(); } catch {}
      if (button.getAttribute('aria-pressed') !== 'true') return;
      img.className = reduceMotion.matches ? 'is-current' : 'is-entering';
      frame.append(img);
      const settle = () => {
        img.className = 'is-current';
        [...frame.children].forEach(child => { if (child !== img) child.remove(); });
      };
      if (reduceMotion.matches) settle();
      else img.addEventListener('animationend', settle, { once: true });
    });
  });

  langListeners.push(() => {
    const active = buttons.find(b => b.getAttribute('aria-pressed') === 'true');
    const img = frame.lastElementChild;
    if (active && img) img.alt = altFor(active);
  });
}

/* ---------- Webi rail ---------- */

function initWebi() {
  const rail = $('[data-webi-rail]');
  const prev = $('[data-webi-prev]');
  const next = $('[data-webi-next]');
  const step = () => {
    const item = rail.firstElementChild;
    return item ? item.getBoundingClientRect().width + 14 : 300;
  };
  const behavior = () => (reduceMotion.matches ? 'auto' : 'smooth');
  prev.addEventListener('click', () => rail.scrollBy({ left: -step(), behavior: behavior() }));
  next.addEventListener('click', () => rail.scrollBy({ left: step(), behavior: behavior() }));

  let ticking = false;
  const sync = () => {
    ticking = false;
    prev.disabled = rail.scrollLeft < 4;
    next.disabled = rail.scrollLeft + rail.clientWidth > rail.scrollWidth - 4;
  };
  rail.addEventListener('scroll', () => {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(sync);
    }
  }, { passive: true });
  sync();

  let drag = null;
  rail.addEventListener('pointerdown', event => {
    if (event.pointerType !== 'mouse' || event.button !== 0) return;
    drag = { x: event.clientX, left: rail.scrollLeft, moved: false };
  });
  window.addEventListener('pointermove', event => {
    if (!drag) return;
    const dx = event.clientX - drag.x;
    if (!drag.moved && Math.abs(dx) > 4) {
      drag.moved = true;
      rail.style.scrollSnapType = 'none';
      rail.style.cursor = 'grabbing';
    }
    if (drag.moved) rail.scrollLeft = drag.left - dx;
  });
  window.addEventListener('pointerup', () => {
    if (!drag) return;
    const moved = drag.moved;
    drag = null;
    if (!moved) return;
    const snapTo = Math.round(rail.scrollLeft / step()) * step();
    rail.scrollTo({ left: snapTo, behavior: behavior() });
    setTimeout(() => {
      rail.style.scrollSnapType = '';
      rail.style.cursor = '';
    }, 450);
  });
  rail.addEventListener('dragstart', event => event.preventDefault());
}

/* ---------- Manifesto ink fill ---------- */

function splitManifesto() {
  const p = $('.manifesto p');
  if (!p) return;
  const value = p.textContent;
  const parts = lang === 'en' ? value.split(/(\s+)/) : [...value];
  const total = parts.filter(part => part.trim()).length;
  let index = 0;
  p.replaceChildren(...parts.map(part => {
    if (!part.trim()) return document.createTextNode(part);
    const span = document.createElement('span');
    span.className = 'ch';
    span.textContent = part;
    const start = 18 + (index / total) * 40;
    span.style.setProperty('--a', `cover ${start.toFixed(1)}%`);
    span.style.setProperty('--b', `cover ${(start + 6).toFixed(1)}%`);
    index += 1;
    return span;
  }));
  p.setAttribute('aria-label', value);
}

/* ---------- Get started ---------- */

function initCopy() {
  const button = $('[data-copy]');
  const label = $('[data-copy-label]');
  const icon = $('use', button);
  const commands = $('[data-copy-source]').textContent
    .split('\n')
    .map(line => line.replace(/^\$\s*/, '').trim())
    .filter(Boolean)
    .join('\n');
  let timer = 0;
  button.addEventListener('click', async () => {
    clearTimeout(timer);
    try {
      await navigator.clipboard.writeText(commands);
      label.textContent = t().copied;
      button.classList.add('is-done');
      icon.setAttribute('href', 'assets/icons.svg#check');
    } catch {
      label.textContent = t().copyFailed;
    }
    timer = setTimeout(() => {
      label.textContent = t().copyLabel;
      button.classList.remove('is-done');
      icon.setAttribute('href', 'assets/icons.svg#copy');
    }, 1800);
  });
}

async function preferredArch() {
  try {
    const data = await navigator.userAgentData?.getHighEntropyValues?.(['architecture']);
    if (data?.architecture === 'x86') return 'intel';
  } catch {}
  return 'arm';
}

function initDownload() {
  const status = $('[data-download-status]');
  const holder = $('[data-download-buttons]');
  let release = null;
  let arch = 'arm';

  function render() {
    if (release === null) {
      status.textContent = t().checking;
      return;
    }
    if (!release) {
      status.textContent = t().noRelease;
      holder.hidden = true;
      return;
    }
    status.textContent = t().latest(release.version);
    const order = arch === 'intel' ? ['intel', 'arm'] : ['arm', 'intel'];
    holder.replaceChildren(...order.filter(id => release.assets[id]).map((id, i) => {
      const a = document.createElement('a');
      a.className = `btn ${i === 0 ? 'btn--seal' : 'btn--ghost'}`;
      a.href = release.assets[id].download_url;
      a.innerHTML = '<svg class="icon" aria-hidden="true"><use href="assets/icons.svg#download"/></svg>';
      a.append(document.createTextNode(t()[id]));
      return a;
    }));
    holder.hidden = false;
  }

  langListeners.push(render);
  render();

  Promise.all([
    fetch('release.json', { cache: 'no-store' }).then(r => (r.ok ? r.json() : null)).catch(() => null),
    preferredArch()
  ]).then(([data, detected]) => {
    arch = detected;
    const assets = Array.isArray(data?.assets) ? data.assets : [];
    const find = test => assets.find(asset => {
      const name = String(asset.name || '').toLowerCase();
      return name.endsWith('.dmg') && test(name);
    });
    const universal = find(name => name.includes('universal'));
    const matched = {
      arm: find(name => /(arm64|aarch64|apple[-_. ]?silicon)/.test(name) && !name.includes('universal')) || universal,
      intel: find(name => /(x86_64|x64|intel)/.test(name) && !name.includes('universal')) || universal
    };
    release = data?.available && (matched.arm || matched.intel)
      ? { version: data.version, assets: matched }
      : false;
    render();
  });
}

/* ---------- Boot ---------- */

function boot() {
  const toggle = $('[data-lang-toggle]');
  langListeners.push(splitManifesto);
  initDemo();
  initThemes();
  initDownload();
  applyLanguage(initialLanguage());
  toggle.addEventListener('click', () => applyLanguage(lang === 'en' ? 'zh' : 'en'));

  initNav();
  initRise();
  initVerbs();
  initWebi();
  initCopy();
  initFooterTexture();

  const ready = document.fonts?.ready ?? Promise.resolve();
  Promise.race([ready, new Promise(resolve => setTimeout(resolve, 700))]).then(() => {
    requestAnimationFrame(() => {
      document.documentElement.classList.add('is-loaded');
      initRubbing();
    });
  });
}

boot();
