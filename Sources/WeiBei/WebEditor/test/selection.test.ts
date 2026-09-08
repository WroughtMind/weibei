import assert from 'node:assert/strict';
import test from 'node:test';
import { indexSelectionText, selectionMarkRange } from '../src/selection';

test('a saved passage spans formatting and paragraph boundaries without truncation', () => {
  const runs = [
    { text: '这段 ', point: (offset: number) => 1 + offset },
    { text: '加粗文字', point: (offset: number) => 4 + offset },
    { text: '\n下一段', point: (offset: number) => 10 + offset },
  ];
  const index = indexSelectionText(runs);
  const range = selectionMarkRange(index.text, { id: 'remark', text: '这段 加粗文字\n下一段' });
  assert.ok(range);
  assert.equal(index.points[range.startOffset], 1);
  assert.equal(index.points[range.endOffset - 1], 13);
});

test('identical passages retain their own anchors and ambiguous relocation adds no false mark', () => {
  const text = '第一段相同的原文第二段相同的原文';
  const startOffset = text.lastIndexOf('相同的原文');
  const anchor = { startOffset, endOffset: text.length };
  assert.deepEqual(selectionMarkRange(text, { id: 'second', text: '相同的原文', anchor }), anchor);
  assert.equal(selectionMarkRange(text, { id: 'missing', text: '相同的原文' }), null);
  assert.deepEqual(selectionMarkRange('前面增加了文字唯一的原文', {
    id: 'moved', text: '唯一的原文', anchor: { startOffset: 0, endOffset: 5 },
  }), { startOffset: 7, endOffset: 12 });
});
