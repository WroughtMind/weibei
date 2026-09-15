import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

// Versions are pinned. Fail the build if an upstream edit invalidates a patch.
export const officeVendorPatches = {
  name: 'office-source-fidelity',
  setup(build) {
    build.onResolve({ filter: /^weibei-pptx-drawing$/ }, args => build.resolve('@aiden0z/pptx-renderer/browser', { resolveDir: args.resolveDir, kind: 'import-statement' }));
    build.onResolve({ filter: /^weibei-office-chart-parser$/ }, () => ({ path: resolve(import.meta.dirname, '../../../node_modules/@silurus/ooxml/dist/session-CrU8f8DI.js') }));
    build.onLoad({ filter: /session-CrU8f8DI\.js$/ }, async ({ path }) => ({
      contents: (await readFile(path, 'utf8')) + `
import officeWasm from './pptx_parser_bg.wasm';
export function parseOfficeCharts(bytes) {
  ue({ module: officeWasm });
  return JSON.parse(new TextDecoder().decode(se(bytes, BigInt(32 * 1024 * 1024), BigInt(256 * 1024 * 1024))));
}`, loader: 'js',
    }));
    build.onLoad({ filter: /pptx_parser_bg\.wasm$/ }, async ({ path }) => ({ contents: await readFile(path), loader: 'binary' }));
    build.onLoad({ filter: /(?:docx-preview\.mjs|pptx-renderer\.browser\.es\.js|WMFJS\.bundle\.js)$/ }, async ({ path }) => {
      let source = await readFile(path, 'utf8');
      const replace = (before, after, count = 1) => {
        if (source.split(before).length - 1 !== count) throw new Error(`Office patch no longer matches ${path}: ${before.slice(0, 70)}`);
        source = source.split(before).join(after);
      };
      if (path.endsWith('docx-preview.mjs')) {
        replace('const zip = await JSZip.loadAsync(input);', 'const zip = input instanceof JSZip ? input : await JSZip.loadAsync(input);');
        replace('var result = { type: DomType.Paragraph, children: [] };', 'var result = { type: DomType.Paragraph, children: [], location: node.getAttribute("data-weibei-location") };');
        replace('case "pict":', 'case "object":\n                case "pict":');
        replace('    renderVmlPicture(elem) {\n        return this.renderContainer(elem, "div");', '    renderVmlPicture(elem) {\n        return this.renderContainer(elem, "span");');
        const mathStart = source.indexOf('    parseMathElement(elem) {');
        const mathEnd = source.indexOf('    parseRunProperties(elem, run) {', mathStart);
        if (mathStart < 0 || mathEnd < 0) throw new Error('Word math patch no longer matches');
        source = source.slice(0, mathStart) + '    parseMathElement(elem) { return {type: "weibeiMath", source: elem.outerHTML}; }\n' + source.slice(mathEnd);
        replace('                case "pic":\n                    return this.parsePicture(n);', '                case "chart":\n                case "relIds":\n                    return { type: "weibeiGraphic", source: elem.outerHTML };\n                case "pic":\n                    return this.parsePicture(n);');
        replace('    renderElement(elem) {', '    renderElement(elem) {\n        if (elem.type === "weibeiGraphic") return window.WeiBeiOffice.renderGraphic(elem.source);');
        replace('    renderElement(elem) {', '    renderElement(elem) {\n        if (elem.type === "weibeiMath") return window.WeiBeiOffice.math(elem.source);');
        replace('var result = this.toHTML(elem, ns.html, "p");', 'var result = this.toHTML(elem, ns.html, "p");\n        if (elem.location) result.setAttribute("data-weibei-location", elem.location);');
      } else if (path.endsWith('WMFJS.bundle.js')) {
        replace('_Helper__WEBPACK_IMPORTED_MODULE_2__.Helper.log("[WMF] " + recordName + " record (0x" + type.toString(16) + ") at offset 0x"\n                        + curpos.toString(16) + " with " + (size * 2) + " bytes");', 'throw new Error("无法完整显示图形记录：" + recordName);');
        const start = source.indexOf('    GDIContext.prototype.textOut = function');
        const end = source.indexOf('    GDIContext.prototype.lineTo = function', start);
        if (start < 0 || end < 0) throw new Error('WMF text patch no longer matches');
        source = source.slice(0, start) + `    GDIContext.prototype.textOut = function(x,y,text) { return window.WeiBeiOffice.drawWMFText(this,x,y,text); };
    GDIContext.prototype.extTextOut = function(x,y,text,flags,rect,dx) { return window.WeiBeiOffice.drawWMFText(this,x,y,text,flags,rect,dx); };
` + source.slice(end);
      } else {
        // Chart data may be stored directly, without a linked spreadsheet cache.
        replace('e.child("strRef").exists() ? e.child("strRef").child("strCache") : e.child("strCache")', 'e.child("strRef").exists() ? e.child("strRef").child("strCache") : e.child("strLit").exists() ? e.child("strLit") : e.child("strCache")');
        replace('e.child("numRef").exists() ? e.child("numRef").child("numCache") : e.child("numCache")', 'e.child("numRef").exists() ? e.child("numRef").child("numCache") : e.child("numLit").exists() ? e.child("numLit") : e.child("numCache")', 3);
        const diagramStart = source.indexOf('function gT(e, t) {');
        const diagramEnd = source.indexOf('function Pl(e, t) {', diagramStart);
        if (diagramStart < 0 || diagramEnd < 0) throw new Error('SmartArt drawing patch no longer matches');
        source = source.slice(0, diagramStart) + `function gT(e, t) {
  const path = e.child('graphic').child('graphicData').child('relIds').attr('data-weibei-drawing');
  const source = t.diagramDrawings?.get(path);
  if (!source) throw new Error('示意图的原始绘图内容未能读取');
  return { ...vT(qa(e), source), weibeiPart: path };
}\n` + source.slice(diagramEnd);
        replace('function AP(e, t, r) {', 'function AP(e, t, r) {\n  if (e.weibeiPart) t = { ...t, partPath: e.weibeiPart, slide: { ...t.slide, rels: window.WeiBeiOffice.graphicRelations(e.weibeiPart) } };');
        source += '\nexport const officeDrawing = { xml: Ar, rels: ms, theme: qy, context: CT, node: Pl, render: Iu };\n';
        // A loaded image replaces the temporary shape fill, while retaining its stroke.
        replace('r.parentNode || t.appendChild(r), (s == null ? void 0 : s.parentNode) === t', 's && s.setAttribute("fill", "none"), r.parentNode || t.appendChild(r), (s == null ? void 0 : s.parentNode) === t');
        // Do not replace missing or unsupported source charts with a placeholder.
        replace('return {\n      option: { title: { text: "Unsupported chart", left: "center" } },\n      chartFrameStyle: Q_(e, i)\n    };', 'throw new Error("图表缺少绘图数据");');
        replace('return {\n    option: {\n      title: { text: "Unsupported chart type", left: "center", textStyle: { fontSize: 12 } }\n    },\n    chartFrameStyle: u\n  };', 'throw new Error("这类图表暂不支持完整显示");');
        replace('return r.style.border = "1px dashed #ccc", r.style.display = "flex", r.style.alignItems = "center", r.style.justifyContent = "center", r.style.color = "#999", r.style.fontSize = "12px", r.textContent = "Chart not found", r;', 'throw new Error("图表关联的数据文件缺失");');
        // The chart legend must use its own font metrics, not the surrounding reader's line height.
        replace('  for (const $ of h) {\n    const S = document.createElement("div");', '  d.style.fontSize = `${p}px`; d.style.lineHeight = "normal";\n  for (const $ of h) {\n    const S = document.createElement("div");');
        // Rendering must finish when a document is opened in a hidden reader.
        replace('    requestAnimationFrame(() => {\n      if (!i.isConnected)', '    setTimeout(() => {\n      if (!i.isConnected)');
        replace('if (n.setOption(t), r == null || r.add(n), typeof ResizeObserver > "u")', 'if (n.setOption({ ...t, animation: false }), n.getZr().flush(), r == null || r.add(n), typeof ResizeObserver > "u")');
        replace('  const i = document.createElement("div");\n  i.style.width = "100%", i.style.flex', '  if (window.WeiBeiOffice.has3DChart(e.chartPath)) { r.appendChild(window.WeiBeiOffice.render3DChart(e.chartPath, e.size)); return r; }\n  const i = document.createElement("div");\n  i.style.width = "100%", i.style.flex');
        replace('o.textContent = `Slide ${t + 1}`', 'o.dataset.weibeiAnnotationUi = "true", o.textContent = `第 ${t + 1} 页`');
        // Keep note controls outside the lazily mounted slide content.
        replace('return { item: i, wrapper: a };', 'window.WeiBeiOffice.attachNote(t, i);\n    return { item: i, wrapper: a };');
        // Equal visibility must not replace the page the reader just chose.
        replace('u > l && (l = u, s = c);', '(u > l || (u === l && c === this.currentSlide)) && (l = u, s = c);');
        // A hidden reader has no visible slide; keep its last reading position.
        replace('s >= 0 && s !== this.currentSlide', 's >= 0 && l > 0 && s !== this.currentSlide');
        // Rebuilding scaled slide wrappers changes their document offsets.
        replace('const { scale: i, displayWidth: a, displayHeight: o } = this.getDisplayMetrics();', 'const weibeiSlide = this.currentSlide;\n          const { scale: i, displayWidth: a, displayHeight: o } = this.getDisplayMetrics();');
        replace('this.activeRenderMode !== "slide" && this.correctListMetricsIfNeeded(), this.emitSlideChange(this.currentSlide);', 'this.activeRenderMode !== "slide" && (this.correctListMetricsIfNeeded(), await this.goToSlide(weibeiSlide, { behavior: "instant", block: "start" })), this.emitSlideChange(this.currentSlide);');
        // DOM batching must complete even when the reader is in a background tab.
        replace('await new Promise((b) => requestAnimationFrame(() => b()))', 'await new Promise((b) => setTimeout(b, 0))');
        replace('(o) => requestAnimationFrame(() => {\n          this.suppressScrollChange = !1, o();\n        })', '(o) => setTimeout(() => {\n          this.suppressScrollChange = !1, o();\n        }, 0)');
        replace('text: c.text(),\n        properties: l.exists() ? l : void 0', 'text: c.text(),\n        math: o.attr("data-weibei-math"),\n        properties: l.exists() ? l : void 0', 2);
        replace('runs: i.length > 0 ? i : n,', 'runs: i.length > 0 ? i : n,\n    location: e.attr("data-weibei-location"),');
        replace('const _ = document.createElement("div");\n    _.style.width', 'const _ = document.createElement("div");\n    if (b.location) _.setAttribute("data-weibei-location", b.location);\n    _.style.width');
        replace('if (N.text && N.text.includes("\t"))', 'if (N.math) X.appendChild(window.WeiBeiOffice.math(N.math));\n      else if (N.text && N.text.includes("\t"))');
      }
      return { contents: source, loader: 'js' };
    });
  },
};
