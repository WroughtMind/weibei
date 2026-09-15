import { readFile } from 'node:fs/promises';

// Versions are pinned. Fail the build if an upstream edit invalidates a patch.
export const officeVendorPatches = {
  name: 'office-source-fidelity',
  setup(build) {
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
        replace('o.textContent = `Slide ${t + 1}`', 'o.dataset.weibeiAnnotationUi = "true", o.textContent = `第 ${t + 1} 页`');
        // Notes must occupy their final height before any slide navigation.
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
