export interface PendingSyntaxRange {
  from: number;
  to: number;
}

const isEscapedPosition = (source: string, index: number) => {
  let slashes = 0;
  for (let cursor = index - 1; cursor >= 0 && source[cursor] === '\\'; cursor -= 1) slashes += 1;
  return slashes % 2 === 1;
};

/** Openers that read as half-typed syntax while the closer has not been typed yet. */
const pairMarkers = ['$$', '**', '__', '~~', '==', '`', '$'] as const;

const leadingMarkerPatterns: RegExp[] = [
  /^(#{1,6})( |$)/,
  /^(>)( |$)/,
];

const appendPendingRange = (ranges: PendingSyntaxRange[], from: number, to: number) => {
  if (from < to && !ranges.some((range) => range.from === from && range.to === to)) {
    ranges.push({ from, to });
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
  for (const pattern of leadingMarkerPatterns) {
    const match = source.match(pattern);
    if (match && match[1]) appendPendingRange(ranges, 0, match[1].length);
  }
  const consumed = new Set<number>();
  for (const marker of pairMarkers) {
    if (marker === '$') continue;
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
      appendPendingRange(ranges, opener, opener + marker.length);
    }
  }
  const dollars = collectSingleDollarOpeners(source, consumed);
  if (dollars.length % 2 === 1) {
    const opener = dollars[dollars.length - 1];
    appendPendingRange(ranges, opener, opener + 1);
  }
  return ranges.sort((a, b) => a.from - b.from);
};

