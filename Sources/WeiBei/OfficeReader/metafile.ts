import { Renderer, loggingEnabled } from 'rtf.js/dist/WMFJS.bundle.js';
import symbols from './symbol-encoding.json';
import { renderEmf } from 'emf-renderer';
loggingEnabled(false);
const svgNS = 'http://www.w3.org/2000/svg';
let clipID = 0;

// WMF records store text origins, character advances and Windows character sets.
// https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-settextalign
export function drawWMFText(ctx: any, x: number, y: number, raw: string, flags = 0, rect?: any, dx: number[] = []) {
  const font = ctx.state.selected.font;
  if (ctx.state.textalign & 1) { x = ctx.state.x; y = ctx.state.y; }
  const chars: string[] = [], advances: number[] = [];
  const symbol = font.charset === 2 || font.facename.toLowerCase() === 'symbol';
  if (symbol) {
    for (let i = 0; i < raw.length; i++) {
      const char = (symbols as Record<string, string>)[raw.charCodeAt(i)];
      if (char === undefined) throw new Error('公式含有无法解码的 Symbol 字符');
      chars.push(char); advances.push(dx[i]);
    }
  } else {
    const encoding = ({ 0: 'windows-1252', 1: 'windows-1252', 128: 'shift_jis', 129: 'euc-kr', 134: 'gbk', 136: 'big5', 161: 'windows-1253', 162: 'windows-1254', 163: 'windows-1258', 177: 'windows-1255', 178: 'windows-1256', 186: 'windows-1257', 204: 'windows-1251', 222: 'windows-874', 238: 'windows-1250', 255: 'ibm866' } as Record<number, string>)[font.charset];
    if (!encoding) throw new Error(`无法解码公式字体字符集 ${font.charset}`);
    const decoder = new TextDecoder(encoding, { fatal: true });
    let advance = 0;
    for (let i = 0; i < raw.length; i++) {
      advance += dx[i] ?? 0;
      const text = decoder.decode(Uint8Array.of(raw.charCodeAt(i)), { stream: i + 1 < raw.length });
      if (text) { chars.push(text); advances.push(dx.length ? advance : NaN); advance = 0; }
    }
  }
  ctx._pushGroup();
  const opts = ctx._applyOpts(null, false, false, true);
  opts['font-family'] = symbol ? 'Times New Roman' : font.facename;
  opts['font-weight'] = font.weight || 400;
  opts['font-style'] = font.italic ? 'italic' : 'normal';
  if (font.underline || font.strikeout) opts['text-decoration'] = [font.underline ? 'underline' : '', font.strikeout ? 'line-through' : ''].filter(Boolean).join(' ');
  const baseline = ctx.state.textalign & 24;
  opts['dominant-baseline'] = baseline === 24 ? 'alphabetic' : baseline === 8 ? 'text-after-edge' : 'text-before-edge';
  const measure = document.createElement('canvas').getContext('2d')!;
  measure.font = `${opts['font-style']} ${opts['font-weight']} ${opts['font-size']}px "${opts['font-family']}"`;
  const scaleX = ctx._todevX(x + 100) - ctx._todevX(x);
  const widths = chars.map((c, i) => Number.isFinite(advances[i]) ? advances[i] : measure.measureText(c).width * 100 / scaleX);
  const total = widths.reduce((a, b) => a + b, 0);
  const horizontal = ctx.state.textalign & 6;
  let cursor = x - (horizontal === 6 ? total / 2 : horizontal === 2 ? total : 0);
  const originX = ctx._todevX(x), originY = ctx._todevY(y);
  if (font.escapement) opts.transform = `rotate(${-font.escapement / 10},${originX},${originY})`;
  let group = ctx.state._svggroup;
  if (flags & 4) {
    if (!rect) throw new Error('公式文字缺少裁剪区域');
    const clip = document.createElementNS(svgNS, 'clipPath');
    const box = document.createElementNS(svgNS, 'rect');
    clip.id = `wmf-clip-${++clipID}`;
    box.setAttribute('x', String(ctx._todevX(rect.left))); box.setAttribute('y', String(ctx._todevY(rect.top)));
    box.setAttribute('width', String(ctx._todevX(rect.right) - ctx._todevX(rect.left))); box.setAttribute('height', String(ctx._todevY(rect.bottom) - ctx._todevY(rect.top)));
    clip.append(box); ctx._getSvgDef().append(clip);
    const clipped = document.createElementNS(svgNS, 'g'); clipped.setAttribute('clip-path', `url(#${clip.id})`); group.append(clipped); group = clipped;
  }
  if ((flags & 2) && rect) ctx._svg.rect(group, ctx._todevX(rect.left), ctx._todevY(rect.top), ctx._todevW(rect.right - rect.left), ctx._todevH(rect.bottom - rect.top), 0, 0, { fill: `#${ctx.state.bkcolor.toHex()}` });
  else if (ctx.state.bkmode === 2) {
    const metrics = measure.measureText(chars.join(''));
    const top = baseline === 24 ? originY - metrics.actualBoundingBoxAscent : baseline === 8 ? originY - opts['font-size'] : originY;
    ctx._svg.rect(group, ctx._todevX(cursor), top, ctx._todevW(total), opts['font-size'], 0, 0, { fill: `#${ctx.state.bkcolor.toHex()}`, transform: opts.transform });
  }
  chars.forEach((char, i) => { ctx._svg.text(group, ctx._todevX(cursor), originY, char, opts); cursor += widths[i]; });
  if (ctx.state.textalign & 1) {
    const angle = font.escapement * Math.PI / 1800;
    ctx.state.x = x + total * Math.cos(angle); ctx.state.y = y - total * Math.sin(angle);
  }
}

export function renderWMF(bytes: Uint8Array): string {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const placeable = view.getUint32(0, true) === 0x9ac6cdd7;
  let width = placeable ? view.getInt16(10, true) - view.getInt16(6, true) : 0;
  let height = placeable ? view.getInt16(12, true) - view.getInt16(8, true) : 0;
  for (let offset = (placeable ? 22 : 0) + 18; offset + 6 <= view.byteLength;) {
    const size = view.getUint32(offset, true) * 2, type = view.getUint16(offset + 4, true);
    if (size < 6 || offset + size > view.byteLength) throw new Error('公式图形记录损坏');
    if (type === 0x020c && !width && !height) { height = Math.abs(view.getInt16(offset + 6, true)); width = Math.abs(view.getInt16(offset + 8, true)); }
    offset += size;
  }
  if (!width || !height) throw new Error('公式图形缺少原始尺寸');
  const svg = new Renderer(bytes).render({ width: `${width}px`, height: `${height}px`, xExt: width, yExt: height, mapMode: 8 });
  svg.setAttribute('xmlns', svgNS);
  return svg.outerHTML;
}

export async function renderEMF(bytes: Uint8Array): Promise<Uint8Array> {
  const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 88 || header.getUint32(0, true) !== 1 || header.getUint32(40, true) !== 0x464d4520) throw new Error('EMF 图形文件损坏');
  const width = header.getInt32(16, true) - header.getInt32(8, true);
  const height = header.getInt32(20, true) - header.getInt32(12, true);
  if (width <= 0 || height <= 0) throw new Error('EMF 图形缺少有效尺寸');
  // Keep the original aspect ratio and cap the transient RGBA surface at 32 MiB.
  const scale = Math.min(2, Math.sqrt(8 * 1024 * 1024 / (width * height)), 8192 / Math.max(width, height));
  const result = await renderEmf(bytes, { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) });
  try {
    if (result.meta.unsupported.length || result.meta.warnings.length) throw new Error(`无法完整显示 EMF 图形：${[...result.meta.unsupported, ...result.meta.warnings].join('；')}`);
    return new Uint8Array(await (await result.toBlob()).arrayBuffer());
  } finally { result.canvas.width = result.canvas.height = 0; }
}
