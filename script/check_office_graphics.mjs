// macOS: node script/check_office_graphics.mjs [office-entry.js.deflate]
// One offline rendering check; generated documents and the invisible WebKit host live in a temporary directory.
import JSZip from 'jszip';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';

const root = resolve(import.meta.dirname, '..');
const output = await mkdtemp(join(tmpdir(), 'weibei-office-graphics-'));
const office = resolve(process.argv[2] ?? join(root, 'Sources/WeiBei/Resources/Editor/office-entry.js.deflate'));
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
zip.file('word/_rels/document.xml.rels', relationships([['flat', 'chart', 'charts/chart1.xml'], ['deep', 'chart', 'charts/chart2.xml'], ['diagram', 'diagramData', 'diagrams/data7.xml'], ['drawing', 'diagramDrawing', 'diagrams/drawing42.xml'], ['emf', 'image', 'media/rectangle.emf']]));
zip.file('word/charts/chart1.xml', chart(false, 0));
zip.file('word/diagrams/data7.xml', `<dgm:dataModel xmlns:dgm="${ns}/drawingml/2006/diagram" xmlns:dsp="http://schemas.microsoft.com/office/drawing/2008/diagram"><dgm:extLst><dgm:ext uri="test"><dsp:dataModelExt relId="drawing"/></dgm:ext></dgm:extLst></dgm:dataModel>`);
zip.file('word/diagrams/drawing42.xml', `<dsp:drawing xmlns:dsp="http://schemas.microsoft.com/office/drawing/2008/diagram" xmlns:a="${a}" xmlns:r="${rel}"><dsp:spTree><dsp:grpSpPr/><dsp:sp><dsp:nvSpPr><dsp:cNvPr id="1" name="图片示意图"/><dsp:cNvSpPr/></dsp:nvSpPr><dsp:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm><a:prstGeom prst="ellipse"/><a:blipFill><a:blip r:embed="photo"/><a:stretch><a:fillRect/></a:stretch></a:blipFill></dsp:spPr><dsp:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>图中文字</a:t></a:r></a:p></dsp:txBody></dsp:sp></dsp:spTree></dsp:drawing>`);
zip.file('word/diagrams/_rels/drawing42.xml.rels', relationships([['photo', 'image', '../media/pixel.png']]));
zip.file('word/media/pixel.png', Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=', 'base64'));
zip.file('word/media/rectangle.emf', Buffer.concat([emf, ...records]));
zip.file('word/document.xml', `<w:document xmlns:w="${ns}/wordprocessingml/2006/main" xmlns:wp="${ns}/drawingml/2006/wordprocessingDrawing" xmlns:a="${a}" xmlns:c="${c}" xmlns:r="${rel}" xmlns:dgm="${ns}/drawingml/2006/diagram" xmlns:m="${ns}/officeDocument/2006/math" xmlns:pic="${ns}/drawingml/2006/picture"><w:body><w:p><w:r><w:t>图形回归检查</w:t></w:r></w:p>${graphic(c, '<c:chart r:id="flat"/>')}${graphic(c, '<c:chart r:id="deep"/>')}${graphic(`${ns}/drawingml/2006/diagram`, '<dgm:relIds r:dm="diagram"/>', 914400, 914400)}<w:p><m:oMath><m:r><m:rPr><m:scr m:val="double-struck"/></m:rPr><m:t>R</m:t></m:r></m:oMath></w:p>${graphic(`${ns}/drawingml/2006/picture`, '<pic:pic><pic:blipFill><a:blip r:embed="emf"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm><a:prstGeom prst="rect"/></pic:spPr></pic:pic>', 914400, 914400)}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr></w:body></w:document>`);
try {
  for (const angle of [20, 65]) {
    zip.file('word/charts/chart2.xml', chart(true, angle));
    await writeFile(join(output, `${angle}.docx`), await zip.generateAsync({ type: 'nodebuffer' }));
  }
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
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-check' 'wasm-unsafe-eval'; style-src 'unsafe-inline'; img-src data: blob:; font-src data: blob:; connect-src 'none'"><body><main id="office-document"></main><script nonce="check">\\(source)</script></body>
""", baseURL: nil)
wait { page.loaded }
var hashes: [String] = []
for path in CommandLine.arguments.dropFirst(2) {
  let data = try Data(contentsOf: URL(fileURLWithPath: path))
  let hash = page.js("""
    const assert = (ok, why) => { if (!ok) throw Error(why); };
    await WeiBeiOffice.open(Uint8Array.from(atob(bytes), c=>c.charCodeAt(0)).buffer, 'docx');
    assert(!WeiBeiOffice.error, WeiBeiOffice.error);
    const charts = [...document.querySelectorAll('canvas')];
    assert(charts.length === 2, 'Word must render both native charts');
    const signatures = charts.map(canvas => {
      const rgba = canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
      let colored = 0, hash = 2166136261;
      for(let i=0;i<rgba.length;i+=4) { if(rgba[i+3] && Math.max(rgba[i],rgba[i+1],rgba[i+2])-Math.min(rgba[i],rgba[i+1],rgba[i+2])>30) colored++; hash=Math.imul(hash^rgba[i],16777619); }
      assert(colored > 200, 'native chart is blank'); return String(hash);
    });
    assert(document.querySelector('math mi').getAttribute('mathvariant') === 'double-struck', 'formula lost its mathematical alphabet');
    assert(document.body.innerText.includes('图中文字'), 'diagram text is missing');
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
print("Office graphics: native Word charts, 3D rotation, diagram image/text, math alphabet and EMF passed")
`);
  execFileSync('xcrun', ['swiftc', join(output, 'check.swift'), '-o', join(output, 'check')], { stdio: 'inherit' });
  execFileSync(join(output, 'check'), [office, join(output, '20.docx'), join(output, '65.docx')], { stdio: 'inherit', timeout: 120000 });
} finally { await rm(output, { recursive: true, force: true }); }
