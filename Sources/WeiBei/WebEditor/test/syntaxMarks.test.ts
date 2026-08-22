import assert from 'node:assert/strict';
import test from 'node:test';
import { findPendingSyntaxMarkers } from '../src/syntax-scanner';

const rangesOf = (text: string) => findPendingSyntaxMarkers(text).map((range) => text.slice(range.from, range.to));

test('unclosed pair markers are pending until their closer arrives', () => {
  assert.deepEqual(rangesOf('**粗体'), ['**']);
  assert.deepEqual(rangesOf('__下划线'), ['__']);
  assert.deepEqual(rangesOf('~~删除'), ['~~']);
  assert.deepEqual(rangesOf('==高亮'), ['==']);
  assert.deepEqual(rangesOf('`行内代码'), ['`']);
  assert.deepEqual(rangesOf('$x^'), ['$']);
  assert.deepEqual(rangesOf('$$块'), ['$$']);
});

test('closed pairs and ordinary prose stay untinted', () => {
  assert.deepEqual(rangesOf('**粗体**收尾'), []);
  assert.deepEqual(rangesOf('`code` 闭合'), []);
  assert.deepEqual(rangesOf('$x^2$ 已闭合'), []);
  assert.deepEqual(rangesOf('普通中文,没有任何符号。'), []);
  assert.deepEqual(rangesOf('a * b = c 与 snake_case'), []);
});

test('only the unmatched tail of repeated markers is pending', () => {
  assert.deepEqual(rangesOf('a **b** c **d'), ['**']);
  assert.deepEqual(rangesOf('第一 `x` 第二 `y` 第三 `z'), ['`']);
  assert.deepEqual(rangesOf('$a$ 与 $b'), ['$']);
});

test('leading heading and quote markers tint only while unconverted', () => {
  assert.deepEqual(rangesOf('#'), ['#']);
  assert.deepEqual(rangesOf('###'), ['###']);
  assert.deepEqual(rangesOf('>'), ['>']);
  assert.deepEqual(rangesOf('#tag 不算标题'), []);
  assert.deepEqual(rangesOf('>文字没空格不算引用'), []);
  assert.deepEqual(rangesOf('正文里的 # 不算'), []);
});

test('escapes and currency dollars are respected', () => {
  assert.deepEqual(rangesOf('\\*\\*转义星号'), []);
  assert.deepEqual(rangesOf('价格 $100 起'), []);
  assert.deepEqual(rangesOf('价格$5 和 $10–$20'), []);
  assert.deepEqual(rangesOf('行尾的公式符$'), ['$']);
});

test('display math markers coexist with inline dollars', () => {
  assert.deepEqual(rangesOf('$$x$$ 已闭合'), []);
  assert.deepEqual(rangesOf('$$x$$ 后面 $y'), ['$']);
  assert.deepEqual(rangesOf('前 $a$ 中 $$b 后 $c'), ['$$', '$']);
});
