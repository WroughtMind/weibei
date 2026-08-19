import assert from 'node:assert/strict';
import test from 'node:test';
import {
  parseCalloutHeader,
  parseStructuredInline,
  serializeCalloutHeader,
  serializeStructuredInline,
} from '../src/structuredMarkdownRules';

const roundTrip = (source: string) => serializeStructuredInline(parseStructuredInline(source));

test('wiki link keeps target and title', () => {
  assert.equal(roundTrip('前 [[笔记#段落|显示标题]] 后'), '前 [[笔记#段落|显示标题]] 后');
});

test('highlight keeps its text', () => {
  assert.equal(roundTrip('这是 ==重点==。'), '这是 ==重点==。');
});

test('inline footnote keeps its text', () => {
  assert.equal(roundTrip('正文^[补充说明]'), '正文^[补充说明]');
});

test('embed keeps target and title', () => {
  assert.equal(roundTrip('![[图片.png|说明|320x180]]'), '![[图片.png|说明|320x180]]');
});

test('callout header keeps type, fold and title', () => {
  const parsed = parseCalloutHeader('[!warning]- 阅读线索');
  assert.ok(parsed);
  assert.equal(serializeCalloutHeader(parsed), '[!warning]- 阅读线索');
});

test('malformed and escaped syntax stays ordinary text', () => {
  const source = String.raw`\[[未完成]] ==未完成 ^[未完成`;
  assert.equal(roundTrip(source), source);
});
