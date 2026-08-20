import assert from 'node:assert/strict';
import test from 'node:test';
import { outlineChangeKey, type EditorOutlineItem } from '../src/outline';

const outline: EditorOutlineItem[] = [
  { id: 'note-heading-0', index: 0, level: 1, title: '开头', position: 0.1 },
  { id: 'note-heading-1', index: 1, level: 2, title: '细节', position: 0.5 },
];

test('outline changes only for heading text, level, insertion, or deletion', () => {
  const key = outlineChangeKey(outline);
  assert.equal(outlineChangeKey(outline.map((item) => ({ ...item, position: item.position + 0.2 }))), key);
  assert.notEqual(outlineChangeKey([{ ...outline[0], title: '新开头' }, outline[1]]), key);
  assert.notEqual(outlineChangeKey([{ ...outline[0], level: 2 }, outline[1]]), key);
  assert.notEqual(outlineChangeKey(outline.slice(0, 1)), key);
});
