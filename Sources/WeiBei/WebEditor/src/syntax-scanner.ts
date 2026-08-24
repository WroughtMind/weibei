export type PendingSyntaxKind = 'math' | 'heading' | 'quote' | 'bold' | 'italic' | 'strike' | 'code' | 'highlight';

export interface PendingSyntaxRange {
  from: number;
  to: number;
  kind: PendingSyntaxKind;
}

const isEscapedPosition = (source: string, index: number) => {
  let slashes = 0;
  for (let cursor = index - 1; cursor >= 0 && source[cursor] === '\\'; cursor -= 1) slashes += 1;
  return slashes % 2 === 1;
};

/** Openers that read as half-typed syntax while the closer has not been typed yet. */
const pairMarkerKinds: Array<{ marker: string; kind: PendingSyntaxKind }> = [
  { marker: '$$', kind: 'math' },
  { marker: '**', kind: 'bold' },
  { marker: '__', kind: 'bold' },
  { marker: '~~', kind: 'strike' },
  { marker: '==', kind: 'highlight' },
  { marker: '`', kind: 'code' },
];

const leadingMarkerPatterns: Array<{ pattern: RegExp; kind: PendingSyntaxKind }> = [
  { pattern: /^(#{1,6})( |$)/, kind: 'heading' },
  { pattern: /^(>)( |$)/, kind: 'quote' },
];

const appendPendingRange = (ranges: PendingSyntaxRange[], from: number, to: number, kind: PendingSyntaxKind) => {
  if (from < to && !ranges.some((range) => range.from === from && range.to === to)) {
    ranges.push({ from, to, kind });
  }
};

const collectMarkerOccurrences = (text: string, marker: string) => {
  const occurrences: number[] = [];
  let index = text.indexOf(marker);
  while (index >= 0) {
    if (!isEscapedPosition(text, index)) occurrences.push(index);
    index = text.indexOf(marker, index + marker.length);
  }
  return occurrences;
};

/**
 * Complete literal inline-math spans (`$x^2$` sitting in a textblock as plain
 * text), paired by the same rules as the pending scanner. Used by the editor to
 * convert pre-typed pairs once the caret leaves them — typing the closing `$`
 * at line end is not the only way to finish a formula.
 */
export const findCompleteInlineMathSpans = (text: string): Array<{ from: number; to: number; source: string }> => {
  const source = String(text || '');
  const consumed = new Set<number>();
  // `$$` runs stay out of inline pairing.
  for (const index of collectMarkerOccurrences(source, '$$')) {
    consumed.add(index);
    consumed.add(index + 1);
  }
  const openers = collectSingleDollarOpeners(source, consumed);
  const spans: Array<{ from: number; to: number; source: string }> = [];
  for (let index = 0; index + 1 < openers.length; index += 2) {
    const from = openers[index];
    const to = openers[index + 1] + 1;
    const payload = source.slice(from + 1, to - 1).trim();
    if (payload) spans.push({ from, to, source: payload });
  }
  return spans;
};

const collectSingleDollarOpeners = (text: string, consumed: Set<number>) => {
  const occurrences: number[] = [];
  let index = text.indexOf('$');
  while (index >= 0) {
    const next = text[index + 1];
    // Currency `$5` never counts; a space-followed `$` still may close a pair.
    if (!consumed.has(index) && !isEscapedPosition(text, index) && (!next || !/\d|\$/.test(next))) {
      occurrences.push(index);
    }
    index = text.indexOf('$', index + 1);
  }
  return occurrences;
};

/**
 * Finds half-typed Markdown markers inside one textblock's text: leading `#`/`>`
 * that have not converted yet, and opener/closer runs (`**`, `$$`, `$`, `~~`,
 * `==`, `` ` ``) left unpaired. Offsets are relative to the start of `text`.
 * Purely lexical — converted runs no longer exist as text, so they never match.
 */
export const findPendingSyntaxMarkers = (text: string): PendingSyntaxRange[] => {
  const source = String(text || '');
  const ranges: PendingSyntaxRange[] = [];
  for (const { pattern, kind } of leadingMarkerPatterns) {
    const match = source.match(pattern);
    if (match && match[1]) appendPendingRange(ranges, 0, match[1].length, kind);
  }
  const consumed = new Set<number>();
  for (const { marker, kind } of pairMarkerKinds) {
    const occurrences: number[] = [];
    for (const index of collectMarkerOccurrences(source, marker)) {
      const overlapped = Array.from({ length: marker.length }, (_, offset) => index + offset).some((position) => consumed.has(position));
      if (overlapped) continue;
      for (let offset = 0; offset < marker.length; offset += 1) consumed.add(index + offset);
      occurrences.push(index);
    }
    // Greedy pairing: the first occurrence closes with the next, an odd tail stays pending.
    if (occurrences.length % 2 === 1) {
      const opener = occurrences[occurrences.length - 1];
      appendPendingRange(ranges, opener, opener + marker.length, kind);
    }
  }
  const dollars = collectSingleDollarOpeners(source, consumed);
  if (dollars.length % 2 === 1) {
    const opener = dollars[dollars.length - 1];
    appendPendingRange(ranges, opener, opener + 1, 'math');
  }
  return ranges.sort((a, b) => a.from - b.from);
};
