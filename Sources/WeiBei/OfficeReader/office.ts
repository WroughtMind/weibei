import JSZip from 'jszip';
import { renderAsync } from 'docx-preview';
import { PptxViewer, RECOMMENDED_ZIP_LIMITS } from '@aiden0z/pptx-renderer/browser';
import { renderOmml } from './math';
import { prepareGraphics, mountWordGraphics, renderGraphic, graphicRelations, has3DChart, render3DChart, disposeGraphics } from './graphics';
import { drawWMFText, renderWMF, renderEMF } from './metafile';

const mathNS = 'http://schemas.openxmlformats.org/officeDocument/2006/math';
const drawingNS = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const pptNS = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const serialize = (e: Node) => new XMLSerializer().serializeToString(e);
const post = (name: string, payload: unknown) => {
  const tagged = payload && typeof payload === 'object' && !Array.isArray(payload)
    ? { ...(payload as Record<string, unknown>), loadToken: document.body?.dataset.weibeiReaderLoadToken || '' }
    : payload;
  (window as any).webkit?.messageHandlers?.[name]?.postMessage(tagged);
};
const parse = (xml: string) => {
  const doc = new DOMParser().parseFromString(xml, 'application/xml');
  if (doc.querySelector('parsererror')) throw new Error(t('文稿内容损坏，无法读取', 'This document is damaged and cannot be read'));
  return doc;
};
const math = (xml: string) => renderOmml(parse(xml).documentElement);
let viewer: PptxViewer | undefined;
let pageSizing: ResizeObserver | undefined;
let root: HTMLElement;
let kind: string;
const notes = new Map<string, Element[]>();
const noteParts = new Map<string, string>();
const equations = new Map<string, string[]>();
let mainPart = '';
let loadError = '';
let searchQuery = '';
let searchResult = -1;
let pptSearchHits: ReturnType<PptxViewer['searchText']> = [];
let pptNoteSearchHits: { slideIndex: number; location: string; text: string; start: number; end: number }[] = [];
let pptSearchOrder: { note: boolean; index: number }[] = [];
const clean = (text?: string | null) => (text ?? '').replace(/\s+/g, ' ').trim();
let english = false;
const t = (zh: string, en: string) => (english ? en : zh);
const pageLabel = (page: number) => t(`第 ${page} 页`, `Page ${page}`);

function fail(error: unknown) {
  loadError = error instanceof Error ? error.message : String(error);
  viewer?.destroy(); disposeGraphics();
  const message = document.createElement('p');
  message.setAttribute('role', 'alert');
  message.style.cssText = 'font:15px/1.8 -apple-system;padding:24px;white-space:pre-wrap';
  message.textContent = t(`这份文稿暂时无法完整显示。\n${loadError}\n原文件已保留。`, `This document cannot be shown in full.\n${loadError}\nThe original file is unchanged.`);
  root.replaceChildren(message);
  post('officeReady', { error: loadError });
}

// Only the in-memory display package is adapted. Original file bytes are never written back.
async function prepare(bytes: ArrayBuffer, format: string) {
  if (bytes.byteLength > RECOMMENDED_ZIP_LIMITS.maxTotalUncompressedBytes) throw new Error(t('文稿大小超过阅读组件容量', 'This document is larger than the reader can open'));
  const zip = await JSZip.loadAsync(bytes);
  const entries = Object.values(zip.files).filter(f => !f.dir);
  const limits = RECOMMENDED_ZIP_LIMITS;
  if (entries.length > limits.maxEntries) throw new Error(t('文稿包含的内容超过阅读组件容量', 'This document contains more than the reader can open'));
  let total = 0;
  for (const file of entries) {
    const size = (file as any)._data?.uncompressedSize ?? 0;
    total += size;
    if (size > limits.maxEntryUncompressedBytes || total > limits.maxTotalUncompressedBytes) throw new Error(t('文稿解压后的内容超过阅读组件容量', 'The unpacked document is larger than the reader can open'));
  }
  const renamed = new Map<string, string>();
  for (const file of entries.filter(f => /\.(wmf|emf)$/i.test(f.name))) {
    const emf = /\.emf$/i.test(file.name);
    const name = `${file.name}.${emf ? 'png' : 'svg'}`;
    const data = await file.async('uint8array');
    zip.file(name, emf ? await renderEMF(data) : renderWMF(data));
    renamed.set(file.name, name); zip.remove(file.name);
  }
  for (const file of entries.filter(f => /\.(xml|rels)$/i.test(f.name))) {
    const doc = parse(await file.async('string'));
    for (const relation of Array.from(doc.getElementsByTagName('Relationship'))) {
      const target = relation.getAttribute('Target');
      if (file.name === '_rels/.rels' && target && relation.getAttribute('Type')?.endsWith('/officeDocument')) mainPart = target.replace(/^\//, '');
      if (target && relation.getAttribute('Type')?.endsWith('/notesSlide')) {
        const slidePart = file.name.replace('/_rels/', '/').replace(/\.rels$/, '');
        noteParts.set(slidePart, new URL(target, `https://office.invalid/${slidePart}`).pathname.slice(1));
      }
      if (target && relation.getAttribute('TargetMode') !== 'External') {
        const part = file.name.replace('/_rels/', '/').replace(/\.rels$/, '');
        const resolved = new URL(target, `https://office.invalid/${part}`).pathname.slice(1);
        const replacement = renamed.get(resolved);
        if (replacement) relation.setAttribute('Target', `/${replacement}`);
      }
    }
    if (file.name === '[Content_Types].xml' && renamed.size) {
      for (const [extension, mime] of [['svg', 'image/svg+xml'], ['png', 'image/png']]) {
        if (Array.from(doc.documentElement.children).some(e => e.getAttribute('Extension') === extension)) continue;
        const type = doc.createElementNS(doc.documentElement.namespaceURI, 'Default');
        type.setAttribute('Extension', extension); type.setAttribute('ContentType', mime); doc.documentElement.append(type);
      }
    }
    // OOXML stores alternate representations of the same object; render exactly one.
    for (const alternate of Array.from(doc.getElementsByTagNameNS('*', 'AlternateContent')).reverse()) {
      const variants = Array.from(alternate.children);
      const chosen = variants.find(c => c.localName === 'Choice' && c.getElementsByTagNameNS(mathNS, 'oMath').length > 0)
        ?? variants.find(c => c.localName === 'Fallback');
      if (!chosen) throw new Error(t('文稿包含尚未支持的绘图对象', 'This document contains a drawing the reader cannot show'));
      alternate.replaceWith(...Array.from(chosen.childNodes));
    }
    const ns = format === 'docx' ? 'http://schemas.openxmlformats.org/wordprocessingml/2006/main' : drawingNS;
    Array.from(doc.getElementsByTagNameNS(ns, 'p')).forEach((p, index) => p.setAttribute('data-weibei-location', `${file.name}#p${index}`));
    const formulas = Array.from(doc.getElementsByTagNameNS(mathNS, 'oMath')).filter(e => !e.closest('del'));
    equations.set(file.name, formulas.map((formula, index) => {
      const id = `${file.name}#math${index}`;
      formula.setAttribute('data-weibei-equation', id); renderOmml(formula);
      return id;
    }));
    if (format === 'pptx') {
      for (const wrapper of Array.from(doc.getElementsByTagNameNS('http://schemas.microsoft.com/office/drawing/2010/main', 'm'))) {
        const formula = Array.from(wrapper.children).find(c => c.namespaceURI === mathNS);
        if (!formula) throw new Error(t('幻灯片公式缺少数学内容', 'A slide formula has no math content'));
        const run = doc.createElementNS(drawingNS, 'a:r');
        run.setAttribute('data-weibei-math', serialize(formula));
        const text = doc.createElementNS(drawingNS, 'a:t');
        text.textContent = Array.from(formula.getElementsByTagNameNS(mathNS, 't')).map(t => t.textContent).join('');
        const properties = formula.getElementsByTagNameNS(drawingNS, 'rPr')[0];
        if (properties) run.append(properties.cloneNode(true));
        run.append(text); wrapper.replaceWith(run);
      }
      if (/^ppt\/notesSlides\/notesSlide\d+\.xml$/.test(file.name)) {
        const blocks = Array.from(doc.getElementsByTagNameNS(pptNS, 'sp')).filter(sp => !['sldImg', 'sldNum', 'dt', 'hdr', 'ftr'].includes(sp.getElementsByTagNameNS(pptNS, 'ph')[0]?.getAttribute('type') ?? ''));
        notes.set(file.name, blocks.flatMap(sp => Array.from(sp.getElementsByTagNameNS(drawingNS, 'p'))));
      }
    }
    zip.file(file.name, serialize(doc));
  }
  await prepareGraphics(zip, format);
  return zip;
}

function verifyEquations(element: Element, part: string) {
  const expected = equations.get(part) ?? [];
  const rendered = new Set(Array.from(element.querySelectorAll('math[data-weibei-equation]')).map(e => e.getAttribute('data-weibei-equation')));
  const found = expected.filter(id => rendered.has(id)).length;
  if (found !== expected.length) throw new Error(t(`原文公式未能完整显示：应有 ${expected.length} 个，已显示 ${found} 个`, `Formulas are incomplete: expected ${expected.length}, showed ${found}`));
}
// R6: single broken images/equations downgrade to the resource-issue dot
// (htmlResourceIssues) instead of failing the whole document.
let resourceIssues: string[] = [];
const reportResourceIssue = (message: string) => {
  if (!resourceIssues.includes(message)) resourceIssues.push(message);
  post('htmlResourceIssues', { missing: resourceIssues.slice(0, 100) });
};
const verifyEquationsQuietly = (element: Element, part: string) => {
  try { verifyEquations(element, part); }
  catch (error) { reportResourceIssue(error instanceof Error ? error.message : String(error)); }
};
function sourceElement(location: string) {
  return Array.from(root.querySelectorAll<HTMLElement>('[data-weibei-location]')).find(e => e.dataset.weibeiLocation === location);
}
function sourceOrder(node: Node) {
  const element = (node instanceof Element ? node : node.parentElement)?.closest<HTMLElement>('[data-weibei-location]');
  if (!element) return undefined;
  const location = element.dataset.weibeiLocation!;
  if (!viewer) return [0, Array.from(root.querySelectorAll('[data-weibei-location]')).indexOf(element)];
  const part = location.split('#')[0];
  const slides = viewer.presentationData!.slides;
  const index = slides.findIndex(s => s.slidePath === part || noteParts.get(s.slidePath) === part);
  if (index < 0) return undefined;
  return [index * 2 + Number(noteParts.get(slides[index].slidePath) === part), Number(location.match(/#p(\d+)$/)?.[1] ?? 0)];
}
function sections() {
  if (viewer) return viewer.presentationData!.slides.map((s, i) => ({ id: s.slidePath, title: t(`第 ${i + 1} 页`, `Page ${i + 1}`), excerpt: '', level: 1, position: i / Math.max(1, viewer!.slideCount - 1), metadata: `${i + 1} / ${viewer!.slideCount} · PPT` }));
  const blocks = Array.from(root.querySelectorAll<HTMLElement>('p[data-weibei-location]')).filter(p => clean(p.textContent));
  const headings = blocks.filter(p => /heading|标题/i.test(p.className) || p.getAttribute('role') === 'heading');
  return (headings.length ? headings : blocks.filter((_, i) => i % 15 === 0)).map((p, i, all) => ({ id: p.dataset.weibeiLocation!, title: clean(p.textContent).slice(0, 60), excerpt: '', level: 1, position: i / Math.max(1, all.length - 1), metadata: 'Word' }));
}
const postSections = () => post('contentRailSections', { sections: sections() });
let officeNavigationInProgress = false;
let presentationHasReportedPosition = false;
async function goTo(location: string) {
  officeNavigationInProgress = true;
  let activeID = location;
  if (viewer) {
    const index = viewer.presentationData!.slides.findIndex(s => s.slidePath === location.split('#')[0]);
    // Notes have the source location of their own part, but belong to one slide.
    const noteIndex = viewer.presentationData!.slides.findIndex(s => noteParts.get(s.slidePath) === location.split('#')[0]);
    const target = index >= 0 ? index : noteIndex;
    if (target < 0) { officeNavigationInProgress = false; return false; }
    activeID = viewer.presentationData!.slides[target].slidePath;
    await viewer.goToSlide(target, { behavior: 'instant', block: 'start' });
  }
  const element = sourceElement(location);
  const note = element?.closest<HTMLElement>('[data-note-part]');
  if (note) {
    note.previousElementSibling!.scrollIntoView({ block: 'nearest', behavior: 'instant' });
    note.showPopover();
    element!.scrollIntoView({ block: 'nearest', behavior: 'instant' });
  } else if (element && (!viewer || location.includes('#'))) element.scrollIntoView({ block: 'center', behavior: 'instant' });
  else if (!viewer) { officeNavigationInProgress = false; return false; }
  post('contentRailActive', { id: activeID, title: sections().find(section => section.id === activeID)?.title, reason: 'jump' });
  window.setTimeout(() => { officeNavigationInProgress = false; }, 0);
  return true;
}
function canGoTo(location: string) {
  if (!viewer) return Boolean(sourceElement(location));
  const part = location.split('#')[0];
  return viewer.presentationData!.slides.some(slide => slide.slidePath === part || noteParts.get(slide.slidePath) === part);
}
async function find(query: string) {
  if (!viewer) return (window as any).find(query, false, false, true, false, true, false);
  if (query !== searchQuery) { searchQuery = query; searchResult = -1; }
  viewer.clearSearchHighlights();
  if (!query) return false;
  const results = viewer.searchText(query);
  const noteResults = Array.from(notes.values()).flat().filter(p => p.textContent?.toLocaleLowerCase().includes(query.toLocaleLowerCase()));
  const count = results.length + noteResults.length;
  if (!count) return false;
  searchResult = (searchResult + 1) % count;
  if (searchResult < results.length) {
    const match = await viewer.highlightSearchResult(results[searchResult], { scrollIntoView: false });
    match?.element.scrollIntoView({ block: 'center', behavior: 'instant' });
    return Boolean(match);
  }
  const location = noteResults[searchResult - results.length].getAttribute('data-weibei-location')!;
  await goTo(location);
  const block = sourceElement(location);
  if (!block) return false;
  const range = document.createRange(); range.selectNodeContents(block); range.collapse(true);
  const selection = window.getSelection(); selection?.removeAllRanges(); selection?.addRange(range);
  return (window as any).find(query, false, false, false, false, true, false);
}

function searchResults(query: string) {
  if (!viewer) return null;
  viewer.clearSearchHighlights();
  pptSearchHits = query ? viewer.searchText(query) : [];
  pptNoteSearchHits = [];
  if (query) viewer.presentationData?.slides.forEach((slide, slideIndex) => {
    for (const paragraph of notes.get(noteParts.get(slide.slidePath) ?? '') ?? []) {
      const text = paragraph.textContent ?? '';
      let from = 0, start;
      while ((start = text.toLocaleLowerCase().indexOf(query.toLocaleLowerCase(), from)) !== -1) {
        pptNoteSearchHits.push({ slideIndex, location: paragraph.getAttribute('data-weibei-location')!,
          text, start, end: start + query.length });
        from = start + query.length;
      }
    }
  });
  const slideRows = pptSearchHits.map(hit => {
    const start = Math.max(0, hit.matchStart - 8);
    const end = Math.min(hit.text.length, hit.matchEnd + 32);
    const prefix = (start ? '…' : '') + hit.text.slice(start, hit.matchStart).replace(/\s+/g, ' ');
    return {
      preview: prefix + hit.text.slice(hit.matchStart, hit.matchEnd) + hit.text.slice(hit.matchEnd, end).replace(/\s+/g, ' ') + (end < hit.text.length ? '…' : ''),
      matchStart: prefix.length, matchLength: hit.matchEnd - hit.matchStart,
      location: t(`第 ${hit.slideIndex + 1} 页`, `Page ${hit.slideIndex + 1}`), pageIndex: hit.slideIndex
    };
  });
  const noteRows = pptNoteSearchHits.map(hit => {
    const start = Math.max(0, hit.start - 8), end = Math.min(hit.text.length, hit.end + 32);
    const prefix = (start ? '…' : '') + hit.text.slice(start, hit.start);
    return { preview: prefix + hit.text.slice(hit.start, end) + (end < hit.text.length ? '…' : ''),
      matchStart: prefix.length, matchLength: hit.end - hit.start,
      location: t(`第 ${hit.slideIndex + 1} 页备注`, `Notes for page ${hit.slideIndex + 1}`), pageIndex: hit.slideIndex };
  });
  const ordered = [
    ...slideRows.map((row, index) => ({ row, note: false, index })),
    ...noteRows.map((row, index) => ({ row, note: true, index }))
  ].sort((a, b) => a.row.pageIndex - b.row.pageIndex || Number(a.note) - Number(b.note));
  pptSearchOrder = ordered.map(({ note, index }) => ({ note, index }));
  return ordered.map(({ row }) => row);
}
async function activateSearchResult(index: number) {
  const target = pptSearchOrder[index];
  const hit = target && !target.note ? pptSearchHits[target.index] : undefined;
  if (!viewer) return;
  if (!hit) {
    const note = target?.note ? pptNoteSearchHits[target.index] : undefined;
    if (!note) return;
    await goTo(note.location);
    const block = sourceElement(note.location);
    if (!block) return;
    const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
    const parts: { node: Node; start: number; end: number }[] = [];
    let node, offset = 0;
    while (node = walker.nextNode()) {
      const length = node.textContent?.length ?? 0;
      parts.push({ node, start: offset, end: offset + length }); offset += length;
    }
    const first = parts.find(part => part.end > note.start);
    const last = parts.find(part => part.end >= note.end);
    if (first && last) {
      const range = document.createRange();
      range.setStart(first.node, note.start - first.start);
      range.setEnd(last.node, note.end - last.start);
      const selection = window.getSelection(); selection?.removeAllRanges(); selection?.addRange(range);
    }
    return;
  }
  viewer.clearSearchHighlights();
  await viewer.goToSlide(hit.slideIndex);
  const match = await viewer.highlightSearchResult(hit, { scrollIntoView: false });
  match?.element.scrollIntoView({ block: 'center', behavior: 'instant' });
}

function positionNote(note: HTMLElement) {
  const rect = note.previousElementSibling!.getBoundingClientRect();
  if (rect.bottom <= 0 || rect.top >= innerHeight) {
    if (note.matches(':popover-open')) note.hidePopover();
    return;
  }
  const above = rect.top > innerHeight / 2;
  note.style.right = `${Math.max(12, innerWidth - rect.right)}px`;
  note.style.maxWidth = `${Math.max(0, rect.right - 12)}px`;
  note.style.top = above ? 'auto' : `${rect.bottom + 8}px`;
  note.style.bottom = above ? `${innerHeight - rect.top + 8}px` : 'auto';
  note.style.maxHeight = `${Math.max(0, (above ? rect.top : innerHeight - rect.bottom) - 20)}px`;
}
function positionOpenNote() {
  const note = root?.querySelector<HTMLElement>('[data-note-part]:popover-open');
  if (note) positionNote(note);
}
window.addEventListener('scroll', positionOpenNote, { passive: true });
window.addEventListener('resize', positionOpenNote);

function attachNote(index: number, wrapper: HTMLElement | null) {
  const slide = viewer?.presentationData?.slides[index];
  if (!slide || !wrapper || wrapper.querySelector('[data-note-part]')) return;
  const path = noteParts.get(slide.slidePath);
  const paragraphs = path && notes.get(path);
  if (!paragraphs || !paragraphs.some(p => clean(p.textContent))) return;
  wrapper.style.position = 'relative';
  const note = document.createElement('aside'); note.dataset.notePart = path;
  note.id = `office-note-${index}`; note.className = 'office-note'; note.popover = 'auto';
  note.setAttribute('aria-label', t(`第 ${index + 1} 页备注`, `Notes for page ${index + 1}`));
  const button = document.createElement('button'); button.type = 'button'; button.className = 'office-note-trigger';
  button.setAttribute('popovertarget', note.id); button.title = t(`查看第 ${index + 1} 页备注`, `View notes for page ${index + 1}`);
  button.setAttribute('aria-label', button.title); button.dataset.weibeiAnnotationUi = 'true';
  button.style.top = `calc(${(wrapper.firstElementChild as HTMLElement).style.height} - 34px)`;
  button.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M12 3H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8l-5-5Zm0 0v5h5M6 11h8M6 14h5"/></svg>';
  const header = document.createElement('header'); header.dataset.weibeiAnnotationUi = 'true';
  const title = document.createElement('strong'); title.textContent = t(`第 ${index + 1} 页备注`, `Notes for page ${index + 1}`);
  const close = document.createElement('button'); close.type = 'button'; close.setAttribute('aria-label', t('关闭备注', 'Close notes'));
  close.setAttribute('popovertarget', note.id); close.setAttribute('popovertargetaction', 'hide');
  close.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="m5 5 10 10M15 5 5 15"/></svg>';
  header.append(title, close); note.append(header);
  const body = document.createElement('div'); body.className = 'office-note-body'; note.append(body);
  for (const p of paragraphs) {
    const block = document.createElement('p'); block.dataset.weibeiLocation = p.getAttribute('data-weibei-location')!;
    for (const run of Array.from(p.children)) {
      if (run.getAttribute('data-weibei-math')) block.append(math(run.getAttribute('data-weibei-math')!));
      else if (run.localName === 'br') block.append(document.createElement('br'));
      else if (run.localName === 'r' || run.localName === 'fld') block.append(run.getElementsByTagNameNS(drawingNS, 't')[0]?.textContent ?? '');
    }
    body.append(block);
  }
  note.addEventListener('beforetoggle', event => { if ((event as ToggleEvent).newState === 'open') positionNote(note); });
  verifyEquationsQuietly(note, path);
  wrapper.append(button, note);
}

function setLanguage(language?: string) {
  english = language === 'english';
  root?.querySelectorAll<HTMLElement>('[data-weibei-slide-label]').forEach(label => {
    const page = Number(label.dataset.weibeiSlideLabel);
    if (Number.isFinite(page)) label.textContent = pageLabel(page);
  });
  if (viewer || root) postSections();
}

async function open(url: string | ArrayBuffer, format: string, language?: string) {
  english = language === 'english';
  root = document.getElementById('office-document')!;
  document.documentElement.style.setProperty('-webkit-text-size-adjust', '100%');
  kind = format; loadError = ''; resourceIssues = []; notes.clear(); noteParts.clear(); equations.clear(); mainPart = '';
  officeNavigationInProgress = false; presentationHasReportedPosition = false;
  try {
    const bytes = typeof url === 'string' ? await (await fetch(url)).arrayBuffer() : url;
    const zip = await prepare(bytes, format);
    viewer?.destroy(); viewer = undefined;
    pageSizing?.disconnect();
    root.replaceChildren();
    if (format === 'docx') {
      root.dataset.weibeiLocation = 'word/document.xml';
      await renderAsync(zip, root, undefined, { useBase64URL: true, renderAltChunks: false, renderComments: true, ignoreWidth: false, ignoreHeight: false });
      await mountWordGraphics(root);
      verifyEquationsQuietly(root, mainPart);
    } else {
      delete root.dataset.weibeiLocation;
      viewer = new PptxViewer(root, {
        zipLimits: RECOMMENDED_ZIP_LIMITS, lazySlides: true, lazyMedia: true, pdfjs: false,
        onNodeError: (_id, error) => { loadError = String(error); queueMicrotask(() => fail(error)); },
        onSlideError: (_index, error) => { loadError = String(error); queueMicrotask(() => fail(error)); },
        onSlideChange: index => post('contentRailActive', {
          id: viewer?.presentationData?.slides[index].slidePath,
          title: t(`第 ${index + 1} 页`, `Page ${index + 1}`),
          reason: officeNavigationInProgress
            ? 'programmatic'
            : (presentationHasReportedPosition ? 'scroll' : (presentationHasReportedPosition = true, 'initial')),
        }),
        onSlideRendered: (index, element) => {
          const slide = viewer?.presentationData?.slides[index];
          if (slide) {
            element.dataset.weibeiLocation = slide.slidePath;
            verifyEquationsQuietly(element, slide.slidePath);
          }
          post('officeReady', {});
        },
      });
      await viewer.open(await zip.generateAsync({ type: 'arraybuffer' }), { renderMode: 'list', listOptions: { windowed: true, initialSlides: 1, showSlideLabels: true } });
    }
    if (loadError) throw new Error(loadError);
    if (format === 'docx') {
      const fitPages = () => {
        if (root.clientWidth <= 32) return;
        const pages = Array.from(root.querySelectorAll<HTMLElement>('section.docx'));
        const center = window.innerHeight / 2;
        // Keep the same point on the page when an already fitted document changes width.
        const anchor = pages.find(page => page.style.zoom && page.getBoundingClientRect().bottom >= center);
        const before = anchor?.getBoundingClientRect();
        pages.forEach(page => {
          page.style.zoom = String(Math.min(1, (root.clientWidth - 32) / page.offsetWidth));
        });
        if (anchor && before && before.height > 0) {
          const after = anchor.getBoundingClientRect();
          window.scrollBy({ top: after.top + (center - before.top) * after.height / before.height - center, behavior: 'instant' });
        }
      };
      pageSizing = new ResizeObserver(fitPages); pageSizing.observe(root); fitPages();
    }
    await document.fonts.ready;
    const broken = await Promise.all(Array.from(root.querySelectorAll('img, svg image')).map(async element => { const img = new Image(); img.src = element instanceof HTMLImageElement ? element.src : (element as SVGImageElement).href.baseVal; try { await img.decode(); return false; } catch { return true; } }));
    const brokenCount = broken.filter(Boolean).length;
    if (brokenCount > 0) reportResourceIssue(t(`文稿中有 ${brokenCount} 张图片未能显示，正文已导入`, `${brokenCount} images could not be shown; the text was imported`));
    postSections();
    if (format === 'docx') reportWordActive('initial');
    post('officeReady', { loaded: true });
  } catch (error) { fail(error); }
}

let revealRequest = '';
async function applyMarks(asks: unknown[], remarks: any[]) {
  const reveal = remarks.find(mark => mark.reveal && mark.reveal !== revealRequest && mark.anchor?.location);
  if (reveal) {
    revealRequest = reveal.reveal;
    if (reveal.anchor.revision !== undefined && String(reveal.anchor.revision) !== document.body.dataset.weibeiRevision) {
      post('officeSourceChanged', {});
      return;
    }
    await goTo(reveal.anchor.location);
  }
  (window as any).WeiBeiSelectionAskMarks?.apply(asks);
  (window as any).WeiBeiRemarkMarks?.apply(remarks);
}

const reportWordActive = (reason: 'initial' | 'scroll' | 'programmatic') => {
  if (kind !== 'docx' || !root) return;
  const line = window.innerHeight * .3;
  const candidates = Array.from(root.querySelectorAll<HTMLElement>('p[data-weibei-location]'));
  const active = candidates.find(p => { const r = p.getBoundingClientRect(); return r.bottom >= line; });
  if (active) post('contentRailActive', { id: active.dataset.weibeiLocation, reason });
};
window.addEventListener('scroll', () => {
  reportWordActive(officeNavigationInProgress ? 'programmatic' : 'scroll');
}, { passive: true });

(window as any).WeiBeiOffice = { open, math, drawWMFText, renderGraphic, graphicRelations, has3DChart, render3DChart, goTo, find, searchResults, activateSearchResult, sections, sourceOrder, applyMarks, attachNote, pageLabel, setLanguage, get isPresentation() { return Boolean(viewer); }, get error() { return loadError; } };
(window as any).WeiBeiContentRail = {
  installed: true,
  scrollTo: (id: string) => {
    if (!canGoTo(id)) return false;
    void goTo(id);
    return true;
  },
  scan: postSections,
  setLanguage
};
