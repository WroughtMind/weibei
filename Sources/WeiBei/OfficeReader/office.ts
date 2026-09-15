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
const post = (name: string, payload: unknown) => (window as any).webkit?.messageHandlers?.[name]?.postMessage(payload);
const parse = (xml: string) => {
  const doc = new DOMParser().parseFromString(xml, 'application/xml');
  if (doc.querySelector('parsererror')) throw new Error('文档内容损坏，无法读取');
  return doc;
};
const math = (xml: string) => renderOmml(parse(xml).documentElement);
let viewer: PptxViewer | undefined;
let pageSizing: ResizeObserver | undefined;
let root: HTMLElement;
let kind: string;
const notes = new Map<string, Element[]>();
const noteParts = new Map<string, string>();
let loadError = '';
let searchQuery = '';
let searchResult = -1;
const clean = (text?: string | null) => (text ?? '').replace(/\s+/g, ' ').trim();

function fail(error: unknown) {
  loadError = error instanceof Error ? error.message : String(error);
  viewer?.destroy(); disposeGraphics();
  const message = document.createElement('p');
  message.setAttribute('role', 'alert');
  message.style.cssText = 'font:15px/1.8 -apple-system;padding:24px;white-space:pre-wrap';
  message.textContent = `这份文档暂时无法完整显示。\n${loadError}\n原文件已保留。`;
  root.replaceChildren(message);
  post('officeReady', { error: loadError });
}

// Only the in-memory display package is adapted. Original file bytes are never written back.
async function prepare(bytes: ArrayBuffer, format: string) {
  if (bytes.byteLength > RECOMMENDED_ZIP_LIMITS.maxTotalUncompressedBytes) throw new Error('文档大小超过阅读组件容量');
  const zip = await JSZip.loadAsync(bytes);
  const entries = Object.values(zip.files).filter(f => !f.dir);
  const limits = RECOMMENDED_ZIP_LIMITS;
  if (entries.length > limits.maxEntries) throw new Error('文档包含的内容超过阅读组件容量');
  let total = 0;
  for (const file of entries) {
    const size = (file as any)._data?.uncompressedSize ?? 0;
    total += size;
    if (size > limits.maxEntryUncompressedBytes || total > limits.maxTotalUncompressedBytes) throw new Error('文档解压后的内容超过阅读组件容量');
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
      if (!chosen) throw new Error('文档包含尚未支持的绘图对象');
      alternate.replaceWith(...Array.from(chosen.childNodes));
    }
    const ns = format === 'docx' ? 'http://schemas.openxmlformats.org/wordprocessingml/2006/main' : drawingNS;
    Array.from(doc.getElementsByTagNameNS(ns, 'p')).forEach((p, index) => p.setAttribute('data-weibei-location', `${file.name}#p${index}`));
    for (const formula of Array.from(doc.getElementsByTagNameNS(mathNS, 'oMath'))) renderOmml(formula);
    if (format === 'pptx') {
      for (const wrapper of Array.from(doc.getElementsByTagNameNS('http://schemas.microsoft.com/office/drawing/2010/main', 'm'))) {
        const formula = Array.from(wrapper.children).find(c => c.namespaceURI === mathNS);
        if (!formula) throw new Error('幻灯片公式缺少数学内容');
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
  if (viewer) return viewer.presentationData!.slides.map((s, i) => ({ id: s.slidePath, title: `第 ${i + 1} 页`, excerpt: '', level: 1, position: i / Math.max(1, viewer!.slideCount - 1), metadata: `${i + 1} / ${viewer!.slideCount} · PPT` }));
  const blocks = Array.from(root.querySelectorAll<HTMLElement>('p[data-weibei-location]')).filter(p => clean(p.textContent));
  const headings = blocks.filter(p => /heading|标题/i.test(p.className) || p.getAttribute('role') === 'heading');
  return (headings.length ? headings : blocks.filter((_, i) => i % 15 === 0)).map((p, i, all) => ({ id: p.dataset.weibeiLocation!, title: clean(p.textContent).slice(0, 60), excerpt: '', level: 1, position: i / Math.max(1, all.length - 1), metadata: 'Word' }));
}
async function goTo(location: string) {
  if (viewer) {
    const index = viewer.presentationData!.slides.findIndex(s => s.slidePath === location.split('#')[0]);
    // Notes have the source location of their own part, but belong to one slide.
    const noteIndex = viewer.presentationData!.slides.findIndex(s => noteParts.get(s.slidePath) === location.split('#')[0]);
    const target = index >= 0 ? index : noteIndex;
    if (target < 0) return false;
    await viewer.goToSlide(target, { behavior: 'instant' });
  }
  const element = sourceElement(location);
  if (element) element.scrollIntoView({ block: 'center', behavior: 'instant' });
  else if (!viewer) return false;
  post('contentRailActive', { id: viewer ? location.split('#')[0] : location, reason: 'jump' });
  return true;
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
    await viewer.highlightSearchResult(results[searchResult]);
    return true;
  }
  const location = noteResults[searchResult - results.length].getAttribute('data-weibei-location')!;
  await goTo(location);
  const block = sourceElement(location);
  if (!block) return false;
  const range = document.createRange(); range.selectNodeContents(block); range.collapse(true);
  const selection = window.getSelection(); selection?.removeAllRanges(); selection?.addRange(range);
  return (window as any).find(query, false, false, false, false, true, false);
}

function attachNote(index: number, wrapper: HTMLElement | null) {
  const slide = viewer?.presentationData?.slides[index];
  if (!slide || !wrapper || wrapper.querySelector('[data-note-part]')) return;
  const path = noteParts.get(slide.slidePath);
  const paragraphs = path && notes.get(path);
  if (!paragraphs || !paragraphs.some(p => clean(p.textContent))) return;
  const aside = document.createElement('aside'); aside.dataset.notePart = path;
  aside.style.width = (wrapper.firstElementChild as HTMLElement)?.style.width; aside.style.maxWidth = '100%';
  aside.setAttribute('aria-label', `第 ${index + 1} 页备注`);
  const title = document.createElement('strong'); title.textContent = `第 ${index + 1} 页 · 备注`; title.dataset.weibeiAnnotationUi = 'true'; aside.append(title);
  for (const p of paragraphs) {
    const block = document.createElement('p'); block.dataset.weibeiLocation = p.getAttribute('data-weibei-location')!;
    for (const run of Array.from(p.children)) {
      if (run.getAttribute('data-weibei-math')) block.append(math(run.getAttribute('data-weibei-math')!));
      else if (run.localName === 'br') block.append(document.createElement('br'));
      else if (run.localName === 'r' || run.localName === 'fld') block.append(run.getElementsByTagNameNS(drawingNS, 't')[0]?.textContent ?? '');
    }
    aside.append(block);
  }
  wrapper.append(aside);
}

async function open(url: string | ArrayBuffer, format: string) {
  root = document.getElementById('office-document')!;
  document.documentElement.style.setProperty('-webkit-text-size-adjust', '100%');
  kind = format; loadError = ''; notes.clear(); noteParts.clear();
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
    } else {
      delete root.dataset.weibeiLocation;
      viewer = new PptxViewer(root, {
        zipLimits: RECOMMENDED_ZIP_LIMITS, lazySlides: true, lazyMedia: true, pdfjs: false,
        onNodeError: (_id, error) => { loadError = String(error); queueMicrotask(() => fail(error)); },
        onSlideError: (_index, error) => { loadError = String(error); queueMicrotask(() => fail(error)); },
        onSlideChange: index => post('contentRailActive', { id: viewer?.presentationData?.slides[index].slidePath, reason: 'scroll' }),
        onSlideRendered: (index, element) => {
          const slide = viewer?.presentationData?.slides[index];
          if (slide) element.dataset.weibeiLocation = slide.slidePath;
          post('officeReady', {});
        },
      });
      await viewer.open(await zip.generateAsync({ type: 'arraybuffer' }), { renderMode: 'list', listOptions: { windowed: true, initialSlides: 1, showSlideLabels: true } });
    }
    if (loadError) throw new Error(loadError);
    if (format === 'docx') {
      const fitPages = () => {
        if (root.clientWidth <= 32) return;
        root.querySelectorAll<HTMLElement>('section.docx').forEach(page => {
          page.style.zoom = String(Math.min(1, (root.clientWidth - 32) / page.offsetWidth));
        });
      };
      pageSizing = new ResizeObserver(fitPages); pageSizing.observe(root); fitPages();
    }
    await document.fonts.ready;
    const broken = await Promise.all(Array.from(root.querySelectorAll('img, svg image')).map(async element => { const img = new Image(); img.src = element instanceof HTMLImageElement ? element.src : (element as SVGImageElement).href.baseVal; try { await img.decode(); return false; } catch { return true; } }));
    if (broken.some(Boolean)) throw new Error('文档中的图片未能完整显示');
    post('contentRailSections', sections());
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

window.addEventListener('scroll', () => {
  if (kind !== 'docx' || !root) return;
  const line = window.innerHeight * .3;
  const candidates = Array.from(root.querySelectorAll<HTMLElement>('p[data-weibei-location]'));
  const active = candidates.find(p => { const r = p.getBoundingClientRect(); return r.bottom >= line; });
  if (active) post('contentRailActive', { id: active.dataset.weibeiLocation, reason: 'scroll' });
}, { passive: true });

(window as any).WeiBeiOffice = { open, math, drawWMFText, renderGraphic, graphicRelations, has3DChart, render3DChart, goTo, find, sections, sourceOrder, applyMarks, attachNote, get error() { return loadError; } };
(window as any).WeiBeiContentRail = { installed: true, scrollTo: (id: string) => { void goTo(id); }, scan: () => post('contentRailSections', sections()) };
