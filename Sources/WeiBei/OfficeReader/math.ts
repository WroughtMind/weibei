// Office's native equations use OMML in both Word and PowerPoint.
// Mapping: https://learn.microsoft.com/en-us/office/math/mathml
const mathNS = 'http://www.w3.org/1998/Math/MathML';
const ommlNS = 'http://schemas.openxmlformats.org/officeDocument/2006/math';
const children = (e: Element) => Array.from(e.children);
const child = (e: Element, name: string) => children(e).find(c => c.localName === name);
const value = (e?: Element, key = 'val') => e?.getAttributeNS(ommlNS, key) ?? e?.getAttribute(key);
const flag = (e?: Element) => !!e && !['0', 'false', 'off'].includes(value(e) ?? '1');
function node(tag: string, content: (Node | string)[] = [], attrs: Record<string, string> = {}) {
  const result = document.createElementNS(mathNS, tag);
  result.append(...content);
  for (const [key, val] of Object.entries(attrs)) result.setAttribute(key, val);
  return result;
}

export function renderOmml(e: Element): Element {
  const tag = e.localName;
  const props = child(e, `${tag}Pr`);
  const prop = (name: string) => child(props ?? e, name);
  const part = (name: string) => { const c = child(e, name); return c ? renderOmml(c) : node('mrow'); };
  const all = () => children(e).filter(c => !c.localName.endsWith('Pr')).map(renderOmml);
  const row = () => node('mrow', all());
  switch (tag) {
    case 'oMath': return node('math', all(), e.hasAttribute('data-weibei-equation') ? { 'data-weibei-equation': e.getAttribute('data-weibei-equation')! } : {});
    case 'oMathPara': {
      const result = document.createElement('span');
      result.style.display = 'block';
      for (const c of all()) { if (c.localName === 'math') c.setAttribute('display', 'block'); result.append(c); }
      return result;
    }
    case 'r': {
      const rPr = child(e, 'rPr');
      const text = children(e).filter(c => c.localName === 't').map(c => c.textContent ?? '').join('');
      if (flag(rPr && child(rPr, 'nor'))) return node('mtext', [text]);
      const tokens = text.match(/\d+(?:[.,]\d+)?|\p{L}[\p{M}]*|\s+|./gu) ?? [];
      const result = node('mrow', tokens.map(t => node(/^\d/.test(t) ? 'mn' : /^\p{L}/u.test(t) ? 'mi' : /^\s+$/.test(t) ? 'mtext' : 'mo', [t])));
      const style = rPr && value(child(rPr, 'sty'));
      const script = rPr && value(child(rPr, 'scr'));
      const variant = script === 'double-struck' ? 'double-struck' : script === 'fraktur' ? (style === 'b' ? 'bold-fraktur' : 'fraktur') : script === 'script' ? (style === 'b' ? 'bold-script' : 'script') : script === 'monospace' ? 'monospace' : script === 'sans-serif' ? (style === 'bi' ? 'sans-serif-bold-italic' : style === 'b' ? 'bold-sans-serif' : style === 'i' ? 'sans-serif-italic' : 'sans-serif') : style === 'b' ? 'bold' : style === 'bi' ? 'bold-italic' : style === 'p' ? 'normal' : undefined;
      if (variant) for (const token of Array.from(result.children)) token.setAttribute('mathvariant', variant);
      return result;
    }
    case 't': return node('mtext', [e.textContent ?? '']);
    case 'e': case 'num': case 'den': case 'deg': case 'sup': case 'sub': case 'lim': case 'fName': case 'box': return row();
    case 'f': {
      const type = value(prop('type'));
      if (type === 'lin') return node('mrow', [part('num'), node('mo', ['/']), part('den')]);
      return node('mfrac', [part('num'), part('den')], type === 'noBar' ? { linethickness: '0' } : type === 'skw' ? { bevelled: 'true' } : {});
    }
    case 'rad': return flag(prop('degHide')) || !(child(e, 'deg')?.textContent) ? node('msqrt', [part('e')]) : node('mroot', [part('e'), part('deg')]);
    case 'sSup': return node('msup', [part('e'), part('sup')]);
    case 'sSub': return node('msub', [part('e'), part('sub')]);
    case 'sSubSup': return node('msubsup', [part('e'), part('sub'), part('sup')]);
    case 'sPre': return node('mmultiscripts', [part('e'), node('mprescripts'), part('sub'), part('sup')]);
    case 'nary': {
      let op = node('mo', [value(prop('chr')) ?? '∫'], { largeop: 'true', movablelimits: 'false' });
      const sub = !flag(prop('subHide')) && !!child(e, 'sub')?.textContent;
      const sup = !flag(prop('supHide')) && !!child(e, 'sup')?.textContent;
      const limits = value(prop('limLoc')) === 'undOvr';
      if (sub && sup) op = node(limits ? 'munderover' : 'msubsup', [op, part('sub'), part('sup')]);
      else if (sub) op = node(limits ? 'munder' : 'msub', [op, part('sub')]);
      else if (sup) op = node(limits ? 'mover' : 'msup', [op, part('sup')]);
      return node('mrow', [op, part('e')]);
    }
    case 'd': {
      const entries = children(e).filter(c => c.localName === 'e');
      const middle = entries.flatMap((c, i) => i ? [node('mo', [value(prop('sepChr')) ?? '|'], { stretchy: 'true' }), renderOmml(c)] : [renderOmml(c)]);
      return node('mrow', [node('mo', [value(prop('begChr')) ?? '('], { fence: 'true', stretchy: String(!prop('grow') || flag(prop('grow'))) }), ...middle, node('mo', [value(prop('endChr')) ?? ')'], { fence: 'true', stretchy: String(!prop('grow') || flag(prop('grow'))) })]);
    }
    case 'm': {
      const aligns = children(prop('mcs') ?? document.createElement('i')).flatMap(c => Array(Number(value(child(c, 'mcPr') && child(child(c, 'mcPr')!, 'count'))) || 1).fill(value(child(c, 'mcPr') && child(child(c, 'mcPr')!, 'mcJc')) ?? 'center'));
      return node('mtable', children(e).filter(c => c.localName === 'mr').map(renderOmml), aligns.length ? { columnalign: aligns.join(' ') } : {});
    }
    case 'mr': return node('mtr', children(e).filter(c => c.localName === 'e').map(c => node('mtd', [renderOmml(c)])));
    case 'eqArr': return node('mtable', children(e).filter(c => c.localName === 'e').map(c => node('mtr', [node('mtd', [renderOmml(c)])])));
    case 'acc': return node('mover', [part('e'), node('mo', [value(prop('chr')) ?? '̂'], { stretchy: 'true' })], { accent: 'true' });
    case 'bar': return node(value(prop('pos')) === 'bot' ? 'munder' : 'mover', [part('e'), node('mo', ['¯'], { stretchy: 'true' })]);
    case 'groupChr': return node(value(prop('pos')) === 'top' ? 'mover' : 'munder', [part('e'), node('mo', [value(prop('chr')) ?? '⏟'], { stretchy: 'true' })]);
    case 'limLow': return node('munder', [part('e'), part('lim')]);
    case 'limUpp': return node('mover', [part('e'), part('lim')]);
    case 'func': return node('mrow', [part('fName'), node('mo', ['⁡']), part('e')]);
    case 'borderBox': {
      const borders = ['top', 'bottom', 'left', 'right'].filter(s => !flag(prop(`hide${s[0].toUpperCase()}${s.slice(1)}`)));
      for (const [key, style] of [['strikeH', 'horizontalstrike'], ['strikeV', 'verticalstrike'], ['strikeBLTR', 'updiagonalstrike'], ['strikeTLBR', 'downdiagonalstrike']]) if (flag(prop(key))) borders.push(style);
      return node('menclose', [part('e')], { notation: borders.join(' ') });
    }
    case 'phant': {
      const body = part('e');
      const result = flag(prop('show')) ? body : node('mphantom', [body]);
      const attrs: Record<string, string> = {};
      if (flag(prop('zeroWid'))) attrs.width = '0px';
      if (flag(prop('zeroAsc'))) attrs.height = '0px';
      if (flag(prop('zeroDesc'))) attrs.depth = '0px';
      return node('mpadded', [result], attrs);
    }
    default: throw new Error(`无法完整显示公式中的 ${tag} 元素`);
  }
}
