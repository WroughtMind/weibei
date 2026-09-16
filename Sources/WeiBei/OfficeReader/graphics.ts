import JSZip from 'jszip';
import { officeDrawing as drawing } from 'weibei-pptx-drawing';
import { parseOfficeCharts } from 'weibei-office-chart-parser';
import { threeD } from '@silurus/ooxml/three-d';
import type { ChartModel } from '@silurus/ooxml/docx';

const relNS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const pptNS = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const drawNS = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const chartNS = 'http://schemas.openxmlformats.org/drawingml/2006/chart';
const resolvePart = (part: string, target: string) => new URL(target, `https://office.invalid/${part}`).pathname.slice(1);
const relPart = (part: string) => part.replace(/([^/]+)$/, '_rels/$1.rels');
const xml = (source: string) => new DOMParser().parseFromString(source, 'application/xml');
const attribute = (value: string) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
let parts = new Map<string, string>();
const mediaURLs = new Map<string, string>();
const chartInstances = new Set<any>();
const charts3D = new Map<string, ChartModel>();
let presentation: any;
const relations = (part: string) => drawing.rels(parts.get(relPart(part)) ?? '');
const related = (part: string, id: string) => {
  const rel = relations(part).get(id);
  if (!rel || rel.targetMode === 'External') throw new Error('绘图内容缺少文档内的关联文件');
  return resolvePart(part, rel.target);
};
function themeFor(part: string, visited = new Set<string>()): string | undefined {
  if (visited.has(part)) return;
  visited.add(part);
  const rels = [...relations(part).values()].filter(r => r.targetMode !== 'External');
  const theme = rels.find(r => r.type.endsWith('/theme'));
  if (theme) return parts.get(resolvePart(part, theme.target));
  const parent = rels.find(r => /\/(slideLayout|slideMaster)$/.test(r.type));
  if (parent) return themeFor(resolvePart(part, parent.target), visited);
  if (part.startsWith('word/') && part !== 'word/document.xml') return themeFor('word/document.xml', visited);
}

export function disposeGraphics() {
  for (const instance of chartInstances) instance.dispose();
  chartInstances.clear();
  for (const url of mediaURLs.values()) URL.revokeObjectURL(url);
  mediaURLs.clear(); parts.clear(); charts3D.clear(); presentation = undefined;
}

export async function prepareGraphics(zip: JSZip, format: string) {
  disposeGraphics();
  for (const file of Object.values(zip.files).filter(f => /\.(xml|rels)$/.test(f.name))) parts.set(file.name, await file.async('string'));
  const chartHosts = new Map<string, string>();
  for (const [part, source] of parts) {
    if (!part.endsWith('.xml')) continue;
    const doc = xml(source);
    let changed = false;
    for (const chart of Array.from(doc.getElementsByTagNameNS(chartNS, 'chart'))) {
      const id = chart.getAttributeNS(relNS, 'id');
      if (id) chartHosts.set(related(part, id), part);
    }
    // SmartArt's data part names its saved drawing explicitly. Never guess by file number.
    for (const ids of Array.from(doc.getElementsByTagNameNS('*', 'relIds'))) {
      const id = ids.getAttributeNS(relNS, 'dm');
      if (!id) continue;
      const dataPart = related(part, id);
      const data = xml(parts.get(dataPart) ?? '');
      const drawingID = data.getElementsByTagNameNS('*', 'dataModelExt')[0]?.getAttribute('relId');
      if (!drawingID) throw new Error('这份示意图缺少保存的原始绘图内容');
      ids.setAttribute('data-weibei-drawing', related(part, drawingID)); changed = true;
    }
    if (format === 'docx') for (const graphic of Array.from(doc.getElementsByTagNameNS(drawNS, 'graphic'))) {
      const extent = Array.from(graphic.parentElement?.children ?? []).find(e => e.localName === 'extent');
      graphic.setAttribute('data-weibei-part', part);
      graphic.setAttribute('data-weibei-width', extent?.getAttribute('cx') ?? '0');
      graphic.setAttribute('data-weibei-height', extent?.getAttribute('cy') ?? '0'); changed = true;
    }
    if (changed) { const result = new XMLSerializer().serializeToString(doc); parts.set(part, result); zip.file(part, result); }
  }
  const threeDParts = [...chartHosts.keys()].filter(path => /<(?:\w+:)?(?:bar|line|area|pie|surface)3DChart\b/.test(parts.get(path) ?? ''));
  if (threeDParts.length) {
    // ChartML is shared by Word and PPT. A small in-memory container lets the
    // maintained OOXML parser read every saved chart setting without a second hand-written parser.
    const charts = new JSZip();
    for (const [path, source] of parts) if (/\/(charts|theme)\//.test(path)) charts.file(path, source);
    const relsXML = (entries: [string, string, string][]) => `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${entries.map(([id, type, target]) => `<Relationship Id="${id}" Type="${relNS}/${type}" Target="${attribute(target)}"/>`).join('')}</Relationships>`;
    charts.file('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/></Types>');
    charts.file('_rels/.rels', relsXML([['office', 'officeDocument', 'ppt/presentation.xml']]));
    const ids = threeDParts.map((_, i) => `<p:sldId id="${256 + i}" r:id="s${i}"/>`).join('');
    charts.file('ppt/presentation.xml', `<p:presentation xmlns:p="${pptNS}" xmlns:r="${relNS}"><p:sldIdLst>${ids}</p:sldIdLst><p:sldSz cx="9144000" cy="6858000"/></p:presentation>`);
    charts.file('ppt/_rels/presentation.xml.rels', relsXML(threeDParts.map((_, i) => [`s${i}`, 'slide', `slides/slide${i}.xml`])));
    for (const [i, path] of threeDParts.entries()) {
      charts.file(`ppt/slides/slide${i}.xml`, `<p:sld xmlns:p="${pptNS}" xmlns:a="${drawNS}" xmlns:r="${relNS}" xmlns:c="${chartNS}"><p:cSld><p:spTree><p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="1" name="chart"/></p:nvGraphicFramePr><p:xfrm><a:off x="0" y="0"/><a:ext cx="9144000" cy="6858000"/></p:xfrm><a:graphic><a:graphicData uri="${chartNS}"><c:chart r:id="chart"/></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld></p:sld>`);
      charts.file(`ppt/slides/_rels/slide${i}.xml.rels`, relsXML([['chart', 'chart', `/${path}`], ['layout', 'slideLayout', `../slideLayouts/layout${i}.xml`]]));
      charts.file(`ppt/slideLayouts/layout${i}.xml`, `<p:sldLayout xmlns:p="${pptNS}"><p:cSld><p:spTree/></p:cSld></p:sldLayout>`);
      charts.file(`ppt/slideLayouts/_rels/layout${i}.xml.rels`, relsXML([['master', 'slideMaster', `../slideMasters/master${i}.xml`]]));
      charts.file(`ppt/slideMasters/master${i}.xml`, `<p:sldMaster xmlns:p="${pptNS}"><p:cSld><p:spTree/></p:cSld></p:sldMaster>`);
      const theme = themeFor(chartHosts.get(path)!);
      if (theme) {
        charts.file(`ppt/theme/weibei${i}.xml`, theme);
        charts.file(`ppt/slideMasters/_rels/master${i}.xml.rels`, relsXML([['theme', 'theme', `../theme/weibei${i}.xml`]]));
      }
    }
    const parsed = parseOfficeCharts(await charts.generateAsync({ type: 'uint8array' }));
    threeDParts.forEach((path, index) => {
      const chart = parsed.slides[index]?.elements.find(e => e.type === 'chart')?.chart;
      if (!chart) throw new Error('三维图表数据读取失败');
      charts3D.set(path, chart);
    });
  }
  if (format !== 'docx') return;
  const parsedParts = [...parts].filter(([path]) => /\/charts\/[^/]+\.xml$/.test(path));
  presentation = {
    slides: [], themes: new Map(), masters: new Map(), layouts: new Map(), slideToLayout: new Map(), layoutToMaster: new Map(), masterToTheme: new Map(),
    charts: new Map(parsedParts.map(([path, source]) => [path, drawing.xml(source)])), chartThemes: new Map(), chartStyles: new Map(), chartColorStyles: new Map(),
    diagramDrawings: new Map([...parts].filter(([path]) => /\/diagrams\/drawing[^/]*\.xml$/.test(path))), media: new Map(), isWps: false,
  };
  for (const [path] of parsedParts) for (const rel of relations(path).values()) {
    const source = parts.get(resolvePart(path, rel.target));
    if (!source || rel.targetMode === 'External') continue;
    if (rel.type.endsWith('/themeOverride')) presentation.chartThemes.set(path, drawing.theme(drawing.xml(source)));
    if (rel.type.endsWith('/chartStyle')) presentation.chartStyles.set(path, drawing.xml(source));
    if (rel.type.endsWith('/chartColorStyle')) presentation.chartColorStyles.set(path, drawing.xml(source));
  }
  for (const file of Object.values(zip.files).filter(f => /\/media\//.test(f.name) && !f.dir)) presentation.media.set(file.name.replace(/^word\//, 'ppt/'), await file.async('uint8array'));
}

export function graphicRelations(part: string) { return relations(part); }
function drawGraphic(source: string) {
  const graphic = xml(source).documentElement;
  const part = graphic.getAttribute('data-weibei-part')!;
  const w = Number(graphic.getAttribute('data-weibei-width')), h = Number(graphic.getAttribute('data-weibei-height'));
  if (!(w > 0 && h > 0)) throw new Error('绘图内容缺少有效尺寸');
  const shape = graphic.getElementsByTagNameNS('http://schemas.microsoft.com/office/word/2010/wordprocessingShape', 'wsp')[0];
  const frame = shape
    ? drawing.xml(`<p:sp xmlns:p="${pptNS}" xmlns:a="${drawNS}">${Array.from(shape.children).filter(e => ['spPr', 'style'].includes(e.localName)).map(e => new XMLSerializer().serializeToString(e)).join('')}</p:sp>`)
    : drawing.xml(`<p:graphicFrame xmlns:p="${pptNS}" xmlns:a="${drawNS}"><p:xfrm><a:off x="0" y="0"/><a:ext cx="${w}" cy="${h}"/></p:xfrm>${source}</p:graphicFrame>`);
  const context = drawing.context(presentation, { index: 0, slidePath: part, rels: relations(part) }, mediaURLs, chartInstances);
  const theme = themeFor(part); if (theme) context.theme = drawing.theme(drawing.xml(theme));
  context.asyncTasks = [];
  const node = drawing.node(frame, { rels: context.slide.rels, partPath: part, diagramDrawings: presentation.diagramDrawings });
  if (!node) throw new Error('绘图内容未能读取');
  // Word owns paragraph/table layout; the existing DrawingML renderer owns the shell.
  if (shape) { node.position = { x: 0, y: 0 }; node.size = { w: w / 9525, h: h / 9525 }; }
  const element = drawing.render(node, context);
  let text: HTMLElement | undefined;
  if (shape && (shape.getElementsByTagNameNS('*', 'txbxContent').length || shape.getElementsByTagNameNS('*', 'linkedTxbx').length)) {
    const properties = Array.from(shape.children).find(e => e.localName === 'bodyPr');
    const value = (name: string) => properties?.getAttribute(name);
    if (shape.getElementsByTagNameNS('*', 'linkedTxbx').length ||
        (value('vert') && value('vert') !== 'horz') || Number(value('rot') ?? 0) !== 0 ||
        Number(value('numCol') ?? 1) !== 1 || properties?.getElementsByTagNameNS('*', 'prstTxWarp').length ||
        properties?.getElementsByTagNameNS('*', 'normAutofit').length ||
        properties?.getElementsByTagNameNS('*', 'spAutoFit').length ||
        ['upright', 'anchorCtr'].some(name => ['1', 'true'].includes(value(name) ?? '')) ||
        ['flipH', 'flipV'].some(name => ['1', 'true'].includes(frame.child('spPr').child('xfrm').attr(name) ?? '')) ||
        (value('wrap') && value('wrap') !== 'square')) {
      throw new Error('这份 Word 文本框的文字变换暂不能完整显示');
    }
    const insets = ['tIns', 'rIns', 'bIns', 'lIns'].map((name, i) => Number(value(name) ?? (i % 2 ? 91440 : 45720)) / 9525);
    text = document.createElement('div'); text.className = 'office-word-shape-text';
    Object.assign(text.style, {
      position: 'absolute', inset: '0', boxSizing: 'border-box', display: 'flex', flexDirection: 'column',
      padding: insets.map(n => `${n}px`).join(' '),
      justifyContent: ({ t: 'flex-start', ctr: 'center', b: 'flex-end', just: 'space-between', dist: 'space-around' } as Record<string, string>)[value('anchor') ?? 't'],
    });
    element.append(text);
  }
  return { element, text, ready: Promise.all(context.asyncTasks) };
}

// Word constructs detached pages first; charts need their final, connected layout.
export function renderGraphic(source: string) {
  const element = document.createElement('div');
  element.dataset.weibeiGraphic = source;
  element.style.cssText = 'position:relative;width:100%;height:100%';
  return element;
}
export async function mountWordGraphics(root: HTMLElement) {
  for (const placeholder of Array.from(root.querySelectorAll<HTMLElement>('[data-weibei-graphic]'))) {
    const graphic = drawGraphic(placeholder.dataset.weibeiGraphic!);
    placeholder.removeAttribute('data-weibei-graphic');
    if (graphic.text) graphic.text.append(...Array.from(placeholder.childNodes));
    placeholder.append(graphic.element);
    await graphic.ready;
  }
}

export const has3DChart = (path: string) => charts3D.has(path);
export function render3DChart(path: string, size: { w: number; h: number }) {
  if (!(size.w > 0 && size.h > 0)) throw new Error('三维图表缺少有效尺寸');
  const canvas = document.createElement('canvas');
  const scale = Math.min(2, Math.sqrt(8 * 1024 * 1024 / (size.w * size.h)));
  canvas.width = Math.ceil(size.w * scale); canvas.height = Math.ceil(size.h * scale);
  const context = canvas.getContext('2d')!; context.scale(scale, scale);
  if (!threeD.render(context, charts3D.get(path)!, { x: 0, y: 0, w: size.w, h: size.h }, 96 / 72)) throw new Error('三维图表未能完整显示');
  // A static chart belongs to the document image cache, not a retained drawing surface.
  const image = new Image();
  image.alt = '三维图表';
  image.style.width = `${size.w}px`; image.style.height = `${size.h}px`;
  image.src = canvas.toDataURL('image/png');
  canvas.width = canvas.height = 0;
  return image;
}
