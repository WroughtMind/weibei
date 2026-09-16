// macOS: node script/check_office_graphics.mjs [office-entry.js.deflate]
// One offline rendering check; generated documents and the invisible WebKit host live in a temporary directory.
import JSZip from 'jszip';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';

const root = resolve(import.meta.dirname, '..');
const output = await mkdtemp(join(tmpdir(), 'weibei-office-graphics-'));
const office = resolve(process.argv[2] ?? join(root, 'Sources/WeiBei/Resources/Editor/office-entry.js.deflate'));
const reader = await readFile(join(root, 'Sources/WeiBei/Views/ReaderView.swift'), 'utf8');
const officeCSS = reader.match(/<style>(html,body\{margin:0;padding:0\}[\s\S]*?)<\/style>/)[1];
const ns = 'http://schemas.openxmlformats.org';
const rel = `${ns}/officeDocument/2006/relationships`;
const a = `${ns}/drawingml/2006/main`, c = `${ns}/drawingml/2006/chart`;
const relationships = entries => `<Relationships xmlns="${ns}/package/2006/relationships">${entries.map(([id, type, target]) => `<Relationship Id="${id}" Type="${rel}/${type}" Target="${target}"/>`).join('')}</Relationships>`;
const chart = (threeD, rotation) => `<c:chartSpace xmlns:c="${c}" xmlns:a="${a}"><c:chart>${threeD ? `<c:view3D><c:rotX val="25"/><c:rotY val="${rotation}"/><c:rAngAx val="0"/><c:perspective val="30"/></c:view3D>` : ''}<c:plotArea><c:layout/><c:${threeD ? 'bar3DChart' : 'barChart'}><c:barDir val="col"/><c:grouping val="clustered"/><c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:v>成绩</c:v></c:tx><c:spPr><a:solidFill><a:srgbClr val="C04030"/></a:solidFill></c:spPr><c:cat><c:strLit><c:ptCount val="2"/><c:pt idx="0"><c:v>甲</c:v></c:pt><c:pt idx="1"><c:v>乙</c:v></c:pt></c:strLit></c:cat><c:val><c:numLit><c:formatCode>0</c:formatCode><c:ptCount val="2"/><c:pt idx="0"><c:v>40</c:v></c:pt><c:pt idx="1"><c:v>80</c:v></c:pt></c:numLit></c:val></c:ser><c:axId val="1"/><c:axId val="2"/></c:${threeD ? 'bar3DChart' : 'barChart'}><c:catAx><c:axId val="1"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:axPos val="b"/><c:crossAx val="2"/><c:crosses val="autoZero"/></c:catAx><c:valAx><c:axId val="2"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:axPos val="l"/><c:crossAx val="1"/><c:crosses val="autoZero"/></c:valAx></c:plotArea></c:chart></c:chartSpace>`;
const graphic = (uri, content, width = 3657600, height = 2286000) => `<w:p><w:r><w:drawing><wp:inline><wp:extent cx="${width}" cy="${height}"/><a:graphic><a:graphicData uri="${uri}">${content}</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>`;
const record = (type, values) => { const b = Buffer.alloc(8 + values.length * 4); [type, b.length, ...values].forEach((v, i) => b.writeInt32LE(v | 0, i * 4)); return b; };
const records = [record(37, [0x80000004]), record(43, [10, 10, 90, 90]), record(14, [0, 0, 20])];
const emf = Buffer.alloc(108);
[1, 108, 0, 0, 100, 100, 0, 0, 2646, 2646, 0x464d4520, 0x10000, 108 + records.reduce((n, b) => n + b.length, 0), 4, 1, 0, 0, 0, 1000, 1000, 264, 264].forEach((v, i) => emf.writeInt32LE(v, i * 4));
const zip = new JSZip();
zip.file('[Content_Types].xml', `<Types xmlns="${ns}/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="emf" ContentType="image/x-emf"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>`);
zip.file('_rels/.rels', relationships([['office', 'officeDocument', 'word/document.xml']]));
zip.file('word/_rels/document.xml.rels', relationships([['flat', 'chart', 'charts/chart1.xml'], ['deep', 'chart', 'charts/chart2.xml'], ['pie', 'chart', 'charts/chart3.xml'], ['diagram', 'diagramData', 'diagrams/data7.xml'], ['drawing', 'diagramDrawing', 'diagrams/drawing42.xml'], ['emf', 'image', 'media/rectangle.emf']]));
zip.file('word/charts/chart1.xml', chart(false, 0));
zip.file('word/charts/chart3.xml', chart(true, 35).replaceAll('bar3DChart', 'pie3DChart').replace(/<c:barDir[^>]*\/>|<c:grouping[^>]*\/>/g, ''));
zip.file('word/diagrams/data7.xml', `<dgm:dataModel xmlns:dgm="${ns}/drawingml/2006/diagram" xmlns:dsp="http://schemas.microsoft.com/office/drawing/2008/diagram"><dgm:extLst><dgm:ext uri="test"><dsp:dataModelExt relId="drawing"/></dgm:ext></dgm:extLst></dgm:dataModel>`);
zip.file('word/diagrams/drawing42.xml', `<dsp:drawing xmlns:dsp="http://schemas.microsoft.com/office/drawing/2008/diagram" xmlns:a="${a}" xmlns:r="${rel}"><dsp:spTree><dsp:grpSpPr/><dsp:sp><dsp:nvSpPr><dsp:cNvPr id="1" name="图片示意图"/><dsp:cNvSpPr/></dsp:nvSpPr><dsp:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm><a:prstGeom prst="ellipse"/><a:blipFill><a:blip r:embed="photo"/><a:stretch><a:fillRect/></a:stretch></a:blipFill></dsp:spPr><dsp:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>图中文字</a:t></a:r></a:p></dsp:txBody></dsp:sp></dsp:spTree></dsp:drawing>`);
zip.file('word/diagrams/_rels/drawing42.xml.rels', relationships([['photo', 'image', '../media/pixel.png']]));
zip.file('word/media/pixel.png', Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=', 'base64'));
zip.file('word/media/rectangle.emf', Buffer.concat([emf, ...records]));
zip.file('word/document.xml', `<w:document xmlns:w="${ns}/wordprocessingml/2006/main" xmlns:wp="${ns}/drawingml/2006/wordprocessingDrawing" xmlns:a="${a}" xmlns:c="${c}" xmlns:r="${rel}" xmlns:dgm="${ns}/drawingml/2006/diagram" xmlns:m="${ns}/officeDocument/2006/math" xmlns:pic="${ns}/drawingml/2006/picture"><w:body><w:p><w:r><w:t>图形回归检查</w:t></w:r></w:p>${graphic(c, '<c:chart r:id="flat"/>')}${graphic(c, '<c:chart r:id="deep"/>')}${graphic(c, '<c:chart r:id="pie"/>')}${graphic(`${ns}/drawingml/2006/diagram`, '<dgm:relIds r:dm="diagram"/>', 914400, 914400)}<w:p><m:oMath><m:r><m:rPr><m:scr m:val="double-struck"/></m:rPr><m:t>R</m:t></m:r></m:oMath></w:p>${graphic(`${ns}/drawingml/2006/picture`, '<pic:pic><pic:blipFill><a:blip r:embed="emf"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm><a:prstGeom prst="rect"/></pic:spPr></pic:pic>', 914400, 914400)}<w:p><w:r><w:br w:type="page"/></w:r></w:p><w:p><w:r><w:t>继续阅读下一页</w:t></w:r></w:p><w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr></w:body></w:document>`);
// Word shape text uses Word paragraphs, including formulas; its shell uses DrawingML.
const shapeNS = 'http://schemas.microsoft.com/office/word/2010/wordprocessingShape';
const shape = graphic(shapeNS, `<wps:wsp xmlns:wps="${shapeNS}"><wps:cNvSpPr txBox="1"/><wps:spPr><a:xfrm rot="600000"><a:off x="0" y="0"/><a:ext cx="3657600" cy="1371600"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="FFF2CC"/></a:solidFill><a:ln w="19050"><a:solidFill><a:srgbClr val="C04030"/></a:solidFill></a:ln></wps:spPr><wps:txbx><w:txbxContent><w:p><w:r><w:t>文本框中的公式</w:t></w:r></w:p><w:p><m:oMath><m:f><m:num><m:r><m:t>1</m:t></m:r></m:num><m:den><m:r><m:t>2</m:t></m:r></m:den></m:f></m:oMath></w:p></w:txbxContent></wps:txbx><wps:bodyPr lIns="182880" rIns="91440" tIns="91440" bIns="45720" anchor="ctr"/></wps:wsp>`, 3657600, 1371600);
const defaultShape = shape.replace(/<wps:bodyPr[^>]*\/>/, '<wps:bodyPr/>').replace('rot="600000"', 'rot="0"');
const decoration = defaultShape.replace(/<wps:txbx>[\s\S]*?<\/wps:txbx>/, '');
zip.file('word/document.xml', (await zip.file('word/document.xml').async('string')).replace('<w:sectPr>', shape + defaultShape + decoration + '<w:sectPr>'));
// A tall slide in a wide, short reading pane exposes page-centering that hides its title.
const deck = new JSZip();
const p = `${ns}/presentationml/2006/main`;
deck.file('[Content_Types].xml', `<Types xmlns="${ns}/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>${[1, 2].map(i => `<Override PartName="/ppt/slides/slide${i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>`).join('')}${[1, 2].map(i => `<Override PartName="/ppt/notesSlides/notesSlide${i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>`).join('')}</Types>`);
deck.file('_rels/.rels', relationships([['office', 'officeDocument', 'ppt/presentation.xml']]));
deck.file('ppt/presentation.xml', `<p:presentation xmlns:p="${p}" xmlns:r="${rel}"><p:sldIdLst><p:sldId id="256" r:id="s1"/><p:sldId id="257" r:id="s2"/></p:sldIdLst><p:sldSz cx="9144000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>`);
deck.file('ppt/_rels/presentation.xml.rels', relationships([1, 2].map(i => [`s${i}`, 'slide', `slides/slide${i}.xml`])));
const textBox = (id, y, text) => `<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="text${id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="457200" y="${y}"/><a:ext cx="8229600" cy="457200"/></a:xfrm><a:prstGeom prst="rect"/></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr sz="2400"/><a:t>${text}</a:t></a:r></a:p></p:txBody></p:sp>`;
for (const i of [1, 2]) deck.file(`ppt/slides/slide${i}.xml`, `<p:sld xmlns:p="${p}" xmlns:a="${a}" xmlns:r="${rel}"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>${textBox(2, 182880, `页首标题${i}`)}${textBox(3, 5943600, `页尾摘录${i}`)}</p:spTree></p:cSld></p:sld>`);
const pptFormula = textBox(4, 3200400, '').replace('<a:r><a:rPr sz="2400"/><a:t></a:t></a:r>', `<a14:m xmlns:a14="http://schemas.microsoft.com/office/drawing/2010/main" xmlns:m="${ns}/officeDocument/2006/math"><m:oMath><m:f><m:num><m:r><m:t>3</m:t></m:r></m:num><m:den><m:r><m:t>4</m:t></m:r></m:den></m:f></m:oMath></a14:m>`);
deck.file('ppt/slides/slide2.xml', (await deck.file('ppt/slides/slide2.xml').async('string')).replace('</p:spTree>', pptFormula + '</p:spTree>'));
for (const i of [1, 2]) deck.file(`ppt/slides/_rels/slide${i}.xml.rels`, relationships([['notes', 'notesSlide', `../notesSlides/notesSlide${i}.xml`]]));
deck.file('ppt/notesSlides/notesSlide1.xml', `<p:notes xmlns:p="${p}" xmlns:a="${a}" xmlns:r="${rel}"><p:cSld><p:spTree>${textBox(2, 0, '   ')}</p:spTree></p:cSld></p:notes>`);
deck.file('ppt/notesSlides/notesSlide2.xml', `<p:notes xmlns:p="${p}" xmlns:a="${a}" xmlns:r="${rel}"><p:cSld><p:spTree>${textBox(2, 0, '老师说明：选看内容')}${textBox(3, 0, '这一页补充说明图中的课程成绩。'.repeat(80))}</p:spTree></p:cSld></p:notes>`);
try {
  await writeFile(join(output, 'navigation.pptx'), await deck.generateAsync({ type: 'nodebuffer' }));
  deck.file('ppt/slides/slide2.xml', (await deck.file('ppt/slides/slide2.xml').async('string')).replace('http://schemas.microsoft.com/office/drawing/2010/main', 'urn:unsupported-equation-wrapper'));
  await writeFile(join(output, 'omitted-formula.pptx'), await deck.generateAsync({ type: 'nodebuffer' }));
  for (const angle of [20, 65]) {
    zip.file('word/charts/chart2.xml', chart(true, angle));
    await writeFile(join(output, `${angle}.docx`), await zip.generateAsync({ type: 'nodebuffer' }));
  }
  const completeWord = await zip.file('word/document.xml').async('string');
  zip.file('word/document.xml', completeWord.replace(/<m:oMath>([\s\S]*?)<\/m:oMath>/, '<w:customXml><m:oMath>$1</m:oMath></w:customXml>'));
  await writeFile(join(output, 'omitted-formula.docx'), await zip.generateAsync({ type: 'nodebuffer' }));
  await writeFile(join(output, 'check.swift'), `
import AppKit
import WebKit
func require(_ ok: Bool, _ message: String) { if !ok { fputs("FAILED: \\(message)\\n", stderr); exit(1) } }
func wait(_ done: () -> Bool) { let end = Date().addingTimeInterval(45); while !done() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }; require(done(), "WebKit timeout") }
final class Page: NSObject, WKNavigationDelegate {
  let web: WKWebView; var loaded = false
  override init() { let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200), configuration: config); super.init(); web.navigationDelegate = self }
  func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
  func js(_ source: String, _ args: [String: Any]) -> Any? {
    var done = false; var result: Any?
    Task { @MainActor in
      do { result = try await web.callAsyncJavaScript(source, arguments: args, in: nil, contentWorld: .page) }
      catch { require(false, String(describing: (error as NSError).userInfo)) }
      done = true
    }; wait { done }; return result
  }
}
NSApplication.shared.setActivationPolicy(.prohibited)
let page = Page()
let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 900, height: 1200), styleMask: .borderless, backing: .buffered, defer: false)
window.isReleasedWhenClosed = false; window.contentView = page.web; window.orderBack(nil)
defer { window.orderOut(nil); window.close() }
let compressed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let decoded = try (compressed as NSData).decompressed(using: .zlib) as Data
let source = String(decoding: decoded, as: UTF8.self).replacingOccurrences(of: "</script", with: "<\\\\/script")
page.web.loadHTMLString("""
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-check' 'wasm-unsafe-eval'; style-src 'unsafe-inline'; img-src data: blob:; font-src data: blob:; connect-src 'none'"><style>${officeCSS}:root{--weibei-note-fill:#f9f1de;--weibei-note-ink:#1d1814;--weibei-note-muted:#665c54;--weibei-note-accent:#91261c}</style><body><main id="office-document"></main><script nonce="check">\\(source)</script></body>
""", baseURL: nil)
wait { page.loaded }
_ = page.js("""
  window.checkOfficeMask = element => {
    const assert = (ok, why) => { if (!ok) throw Error(why); };
    const root = document.getElementById('office-document');
    const color = getComputedStyle(element).color;
    const rect = element.getBoundingClientRect();
    const hit = document.elementFromPoint((rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2);
    const range = document.createRange(); range.selectNodeContents(element);
    getSelection().removeAllRanges(); getSelection().addRange(range);
    const selected = getSelection().toString();
    assert(selected.length > 0 && hit, 'mask check needs visible selectable document text');
    root.toggleAttribute('data-weibei-adapts-colors', true);
    document.documentElement.style.setProperty('--weibei-document-mask', 'rgb(244, 234, 213)');
    const mask = getComputedStyle(root, '::after');
    assert(mask.content !== 'none' && mask.mixBlendMode === 'multiply' && mask.pointerEvents === 'none', 'Office sunglasses must tint the page without intercepting input');
    assert(parseFloat(mask.width) === innerWidth && parseFloat(mask.height) === innerHeight, 'the mask must cover the reading viewport');
    const paper = mask.backgroundColor;
    document.documentElement.style.setProperty('--weibei-document-mask', 'rgb(148, 153, 163)');
    assert(getComputedStyle(root, '::after').backgroundColor !== paper, 'the mask must follow theme changes');
    assert(getComputedStyle(element).color === color && element.getBoundingClientRect().top === rect.top && getSelection().toString() === selected, 'mask changes must preserve document colors, position and selection');
    assert(document.elementFromPoint((rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2) === hit, 'the mask must not block document interaction');
    root.removeAttribute('data-weibei-adapts-colors');
    assert(getComputedStyle(root, '::after').content === 'none', 'turning sunglasses off must remove the tint');
    getSelection().removeAllRanges();
  };
  return true;
  """, [:])
var hashes: [String] = []
for path in CommandLine.arguments.dropFirst(2).prefix(2) {
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  let hash = page.js("""
    const assert = (ok, why) => { if (!ok) throw Error(why); };
    await WeiBeiOffice.open(Uint8Array.from(atob(bytes), c=>c.charCodeAt(0)).buffer, 'docx');
    assert(!WeiBeiOffice.error, WeiBeiOffice.error);
    checkOfficeMask(document.querySelector('p[data-weibei-location]'));
    const charts = [...document.querySelectorAll('canvas, img')].slice(0, 3);
    assert(charts.length === 3, 'Word must render the native 2D, 3D bar and 3D pie charts');
    const signatures = charts.map(chart => {
      const canvas = document.createElement('canvas');
      canvas.width = chart instanceof HTMLImageElement ? chart.naturalWidth : chart.width;
      canvas.height = chart instanceof HTMLImageElement ? chart.naturalHeight : chart.height;
      canvas.getContext('2d').drawImage(chart, 0, 0);
      const rgba = canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
      let colored = 0, hash = 2166136261;
      for(let i=0;i<rgba.length;i+=4) { if(rgba[i+3] && Math.max(rgba[i],rgba[i+1],rgba[i+2])-Math.min(rgba[i],rgba[i+1],rgba[i+2])>30) colored++; hash=Math.imul(hash^rgba[i],16777619); }
      assert(colored > 200, 'native chart is blank'); return String(hash);
    });
    assert(document.querySelector('math mi').getAttribute('mathvariant') === 'double-struck', 'formula lost its mathematical alphabet');
    assert(document.body.innerText.includes('图中文字'), 'diagram text is missing');
    const fraction = document.querySelector('math mfrac');
    assert(fraction && fraction.children[0].textContent === '1' && fraction.children[1].textContent === '2', 'Word text-box formula is missing or flattened');
    const textBox = fraction.closest('.office-word-shape-text');
    assert(textBox && textBox.textContent.includes('文本框中的公式') && fraction.closest('[data-weibei-location]'), 'Word text-box paragraphs must retain content and source locations');
    assert(Math.abs(parseFloat(getComputedStyle(textBox).paddingLeft) - 19.2) < .01 && getComputedStyle(textBox).justifyContent === 'center', 'Word text-box insets and vertical alignment must follow the source: ' + JSON.stringify({ padding: getComputedStyle(textBox).paddingLeft, alignment: getComputedStyle(textBox).justifyContent }));
    const shell = textBox.parentElement;
    assert(shell.style.transform.includes('rotate(10deg)') && parseFloat(shell.style.width) === 384 && parseFloat(shell.style.height) === 144, 'Word text-box size and rotation must follow the source');
    const surfaces = [shell, ...shell.querySelectorAll('svg, path, rect')].map(e => getComputedStyle(e));
    assert(surfaces.some(s => s.fill === 'rgb(255, 242, 204)' || s.backgroundColor === 'rgb(255, 242, 204)') && surfaces.some(s => s.stroke === 'rgb(192, 64, 48)' || s.borderColor === 'rgb(192, 64, 48)'), 'Word text-box fill and stroke must follow the source');
    const defaults = getComputedStyle(document.querySelectorAll('.office-word-shape-text')[1]);
    assert(Math.abs(parseFloat(defaults.paddingTop) - 4.8) < .01 && Math.abs(parseFloat(defaults.paddingLeft) - 9.6) < .01 && defaults.justifyContent === 'flex-start', 'Word text boxes must retain default insets and top alignment');

    const image = document.querySelector('svg image');
    assert(image && [...image.parentElement.children].slice([...image.parentElement.children].indexOf(image)+1).every(e=>e.localName!=='path' || e.getAttribute('fill')==='none'), 'diagram image is covered by a solid fill');
    const vector = [...document.images].find(i=>i.naturalWidth === 200);
    assert(vector, 'EMF image is missing');
    const surface=document.createElement('canvas');surface.width=surface.height=200;const ctx=surface.getContext('2d');ctx.drawImage(vector,0,0,200,200);
    const center=ctx.getImageData(100,100,1,1).data;assert(center[3]===255 && center[0]<30, 'EMF geometry is blank');
    return signatures[1];
    """, ["bytes": data.base64EncodedString()]) as! String
  hashes.append(hash)
}
require(hashes.count == 2 && hashes[0] != hashes[1], "saved 3D rotation must change rendered geometry")
window.setContentSize(NSSize(width: 900, height: 600))
_ = page.js("document.querySelector('math').scrollIntoView({block:'center',behavior:'instant'}); return true;", [:])
for width in [600.0, 900.0] {
  window.setContentSize(NSSize(width: width, height: 600))
  _ = page.js("""
    await new Promise(resolve => setTimeout(resolve, 100));
    const r = document.querySelector('math').getBoundingClientRect();
    if (Math.abs((r.top+r.bottom)/2-innerHeight/2) > r.height) throw Error('Word resizing must preserve the formula being read: ' + JSON.stringify({ center: (r.top+r.bottom)/2, viewport: innerHeight, scroll: scrollY, limit: document.documentElement.scrollHeight-innerHeight }));
    return true;
    """, [:])
}
let omittedFormula = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[4]))
_ = page.js("""
  await WeiBeiOffice.open(Uint8Array.from(atob(bytes), c => c.charCodeAt(0)).buffer, 'docx');
  if (!WeiBeiOffice.error.includes('公式未能完整显示') || !document.querySelector('[role="alert"]')) throw Error('a skipped source formula must fail explicitly instead of reporting a complete document');
  return true;
  """, ["bytes": omittedFormula.base64EncodedString()])
window.setContentSize(NSSize(width: 1200, height: 600))
let deck = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments.last!))
_ = page.js("""
  const assert = (ok, why) => { if (!ok) throw Error(why); };
  const visible = element => { const r = element.getBoundingClientRect(); return r.height > 0 && r.top >= 0 && r.bottom <= innerHeight; };
  await WeiBeiOffice.open(Uint8Array.from(atob(bytes), c=>c.charCodeAt(0)).buffer, 'pptx');
  assert(!WeiBeiOffice.error, WeiBeiOffice.error);
  await WeiBeiOffice.goTo('ppt/slides/slide2.xml');
  const title = document.querySelector('[data-weibei-location="ppt/slides/slide2.xml#p0"]');
  assert(title && visible(title), 'PPT page navigation must keep the full title visible');
  assert(document.querySelector('math mfrac')?.textContent === '34' && !WeiBeiOffice.error, 'PPT source equations must pass accounting after their slide is mounted');
  checkOfficeMask(title);
  await WeiBeiOffice.find('页首标题2');
  assert(visible(title), 'PPT search must reveal the matched title');
  await WeiBeiOffice.find('页尾摘录2');
  const excerpt = document.querySelector('[data-weibei-location="ppt/slides/slide2.xml#p1"]');
  assert(excerpt && visible(excerpt), 'PPT search must reveal the matched text at the bottom');
  const note = document.querySelector('[data-note-part]');
  assert(note && !note.matches(':popover-open'), 'PPT notes must start closed');
  assert(!document.querySelector('[data-slide-index="0"] [data-note-part], [data-slide-index="0"] .office-note-trigger'), 'an empty note must not add a panel or trigger');
  const trigger = note.previousElementSibling;
  trigger.scrollIntoView({block:'nearest',behavior:'instant'});
  const slideFrame = note.parentElement.firstElementChild;
  const before = slideFrame.getBoundingClientRect();
  const icon = trigger.getBoundingClientRect();
  assert(icon.left >= before.left && icon.right <= before.right && icon.top >= before.top && icon.bottom <= before.bottom, 'the note trigger must stay inside its PPT page');
  trigger.click();
  assert(note.matches(':popover-open'), 'the note button must open its panel');
  const panel = note.getBoundingClientRect();
  assert(panel.left >= 0 && panel.right <= innerWidth && panel.top >= 0 && panel.bottom <= innerHeight, 'note panel must fit the reading viewport');
  assert(slideFrame.getBoundingClientRect().top === before.top, 'opening a note must not move the slide');
  const noteBody = note.querySelector('.office-note-body');
  assert(noteBody.scrollHeight > noteBody.clientHeight, 'long notes must scroll inside their panel');
  const originalTitleColor = getComputedStyle(title).color;
  const paper = getComputedStyle(note).backgroundColor;
  document.documentElement.style.setProperty('--weibei-note-fill', 'rgba(27,35,48,.40)');
  document.documentElement.style.setProperty('--weibei-note-ink', '#e8eef9');
  assert(getComputedStyle(note).backgroundColor !== paper && getComputedStyle(title).color === originalTitleColor, 'note theme must change without recoloring PPT text');
  note.querySelector('[popovertargetaction="hide"]').click();
  assert(!note.matches(':popover-open'), 'close control must dismiss the note');
  await WeiBeiOffice.goTo('ppt/notesSlides/notesSlide2.xml#p0');
  const noteText = note.querySelector('[data-weibei-location]');
  assert(note.matches(':popover-open') && visible(noteText), 'a note excerpt return must open and reveal the source');
  note.hidePopover();
  await WeiBeiOffice.find('老师说明');
  assert(note.matches(':popover-open') && visible(noteText), 'PPT search must open and reveal matching notes');
  await WeiBeiOffice.goTo('ppt/slides/slide1.xml');
  await WeiBeiOffice.goTo('ppt/slides/slide2.xml#p1');
  assert(visible(excerpt), 'PPT excerpt return must reveal its paragraph');
  return true;
  """, ["bytes": deck.base64EncodedString()])
let omittedSlideFormula = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[5]))
_ = page.js("""
  await WeiBeiOffice.open(Uint8Array.from(atob(bytes), c => c.charCodeAt(0)).buffer, 'pptx');
  if (!WeiBeiOffice.error) await WeiBeiOffice.goTo('ppt/slides/slide2.xml');
  await new Promise(resolve => setTimeout(resolve, 0));
  if (!WeiBeiOffice.error.includes('公式未能完整显示') || !document.querySelector('[role="alert"]')) throw Error('a skipped slide formula must reach the reader error state through the slide event');
  return true;
  """, ["bytes": omittedSlideFormula.base64EncodedString()])
print("Office graphics and reading: Word charts, 3D bar/pie images and rotation, diagram, math, EMF; Word resize position; PPT title navigation, search, excerpt return, themed note popovers and Word/PPT sunglasses passed")
`);
  execFileSync('xcrun', ['swiftc', join(output, 'check.swift'), '-o', join(output, 'check')], { stdio: 'inherit' });
  execFileSync(join(output, 'check'), [office, join(output, '20.docx'), join(output, '65.docx'), join(output, 'omitted-formula.docx'), join(output, 'omitted-formula.pptx'), join(output, 'navigation.pptx')], { stdio: 'inherit', timeout: 120000 });
} finally { await rm(output, { recursive: true, force: true }); }
