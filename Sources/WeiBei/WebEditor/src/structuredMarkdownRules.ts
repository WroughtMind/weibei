export type StructuredInlineToken =
  | { type: 'text'; value: string }
  | { type: 'wikiLink'; raw: string; target: string; label: string }
  | { type: 'highlight'; value: string }
  | { type: 'inlineFootnote'; value: string }
  | { type: 'embed'; raw: string; target: string; label: string };

const isEscaped = (source: string, index: number) => {
  let slashes = 0;
  for (let cursor = index - 1; cursor >= 0 && source[cursor] === '\\'; cursor -= 1) slashes += 1;
  return slashes % 2 === 1;
};

export const parseStructuredInline = (source: string): StructuredInlineToken[] => {
  const tokens: StructuredInlineToken[] = [];
  const pattern = /!\[\[([^\]\n]+)\]\]|\[\[([^\]\n]+)\]\]|==([^=\n]+)==|\^\[([^\]\n]+)\]/g;
  let cursor = 0;
  for (const match of source.matchAll(pattern)) {
    const index = match.index || 0;
    if (isEscaped(source, index)) continue;
    if (index > cursor) tokens.push({ type: 'text', value: source.slice(cursor, index) });
    const raw = match[1] ?? match[2];
    if (raw !== undefined) {
      const divider = raw.indexOf('|');
      const target = (divider < 0 ? raw : raw.slice(0, divider)).trim();
      const label = (divider < 0 ? '' : raw.slice(divider + 1)).trim();
      tokens.push({ type: match[1] === undefined ? 'wikiLink' : 'embed', raw, target, label });
    } else if (match[3] !== undefined) tokens.push({ type: 'highlight', value: match[3] });
    else tokens.push({ type: 'inlineFootnote', value: match[4] });
    cursor = index + match[0].length;
  }
  if (cursor < source.length) tokens.push({ type: 'text', value: source.slice(cursor) });
  return tokens.length ? tokens : [{ type: 'text', value: source }];
};

export const serializeStructuredInline = (tokens: StructuredInlineToken[]) => tokens.map((token) => {
  if (token.type === 'text') return token.value;
  if (token.type === 'highlight') return `==${token.value}==`;
  if (token.type === 'inlineFootnote') return `^[${token.value}]`;
  return `${token.type === 'embed' ? '!' : ''}[[${token.raw}]]`;
}).join('');

export const parseCalloutHeader = (source: string) => {
  const match = source.match(/^\[!([A-Za-z][A-Za-z0-9_-]*)\]([+-]?)(?:[ \t]+(.+))?$/);
  return match ? { calloutType: match[1].toLowerCase(), fold: match[2] || '', title: (match[3] || '').trim() } : null;
};

export const serializeCalloutHeader = (value: { calloutType: string; fold: string; title: string }) => (
  `[!${value.calloutType}]${value.fold}${value.title ? ` ${value.title}` : ''}`
);
