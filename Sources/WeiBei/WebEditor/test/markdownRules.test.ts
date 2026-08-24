import assert from 'node:assert/strict';
import test from 'node:test';
import {
  joinFrontmatter,
  inlineMathInputPattern,
  incompleteStreamingMarkdownTailMarkers,
  looksLikeMarkdownSyntax,
  normalizeHtmlBreaks,
  normalizeMarkdownSource,
  normalizeMarkdownOutput,
  protectCurrencyDollars,
  splitFrontmatter,
} from '../src/markdownRules';

test('document boundary rules preserve frontmatter and extended Markdown on round-trip', () => {
  const source = [
    '---',
    'title: Round trip',
    '---',
    '',
    '\\[\\[Note\\|Alias\\]\\] and \\=\\=marked\\=\\= and ^\\[footnote]',
    '',
    '`\\[\\[inline code\\]\\]`',
    '',
    '```md',
    '\\[\\[fenced code\\]\\]',
    '```',
  ].join('\n');
  const document = splitFrontmatter(source);
  const output = joinFrontmatter(document.frontmatter, document.body);

  assert.equal(output, [
    '---',
    'title: Round trip',
    '---',
    '',
    '[[Note\\|Alias]] and ==marked== and ^[footnote]',
    '',
    '`\\[\\[inline code\\]\\]`',
    '',
    '```md',
    '\\[\\[fenced code\\]\\]',
    '```',
  ].join('\n'));
  assert.equal(joinFrontmatter(document.frontmatter, normalizeMarkdownOutput(document.body)), output);
  assert.equal(normalizeMarkdownOutput('literal ` before [[Note]]'), 'literal \\` before [[Note]]');
});

test('HTML break normalization changes prose but leaves inline and fenced code untouched', () => {
  const source = [
    'first<br>second',
    '`inline<br>code`',
    '```html',
    '<br>',
    '```',
  ].join('\n');

  assert.equal(normalizeHtmlBreaks(source), [
    'first  ',
    'second',
    '`inline<br>code`',
    '```html',
    '<br>',
    '```',
  ].join('\n'));
  assert.equal(normalizeHtmlBreaks('<br />\n\n> <br>'), '<br />\n\n> <br>');
});

test('currency dollars are protected at parse time without touching formulas, escapes, or code', () => {
  assert.equal(
    protectCurrencyDollars('Price $5, range $10–$20, escaped \\$5, formula $x_1 + y$ and `$8`.\n```\n$9\n```'),
    'Price \\$5, range \\$10–\\$20, escaped \\$5, formula $x_1 + y$ and `$8`.\n```\n$9\n```',
  );
  assert.equal(normalizeMarkdownOutput(protectCurrencyDollars('$5 / $10–$20')), '$5 / $10–$20');
  assert.equal('$x_1 + y$'.match(inlineMathInputPattern)?.[1], 'x_1 + y');
  assert.equal('$5'.match(inlineMathInputPattern), null);
  assert.equal('$10–$20'.match(inlineMathInputPattern), null);
  assert.equal('\\$5'.match(inlineMathInputPattern), null);
});

test('source matrix keeps user documents literal and repairs only explicit paste and Agent math', () => {
  const cases = {
    userDocument: normalizeMarkdownSource('\\(x^2\\) and $$y$$ and $5', 'userDocument'),
    userPaste: normalizeMarkdownSource('\\(x^2\\) and $5', 'userPaste'),
    agentGenerated: normalizeMarkdownSource('$$x^2$$\n[ y = \\beta ]\n\\hat y and $5', 'agentGenerated'),
    internalFragment: normalizeMarkdownSource('$x^2$ and $5', 'internalFragment'),
  };
  assert.equal(cases.userDocument, '\\(x^2\\) and $$y$$ and \\$5');
  assert.equal(cases.userPaste, '$x^2$ and \\$5');
  assert.equal(cases.agentGenerated, '$$\nx^2\n$$\n$$\ny = \\beta\n$$\n\\hat{y} and \\$5');
  assert.equal(cases.internalFragment, '$x^2$ and \\$5');
});

test('normalization preserves valid and incomplete formula source for lossless editing', () => {
  assert.equal(normalizeMarkdownSource('$\\frac{a}{b}$', 'userDocument'), '$\\frac{a}{b}$');
  assert.equal(normalizeMarkdownSource('$\\frac{a}{$', 'userDocument'), '$\\frac{a}{$');
  assert.equal(normalizeMarkdownSource('$\\unknown{x}$', 'agentGenerated'), '$\\unknown{x}$');
});

test('chat streaming identifies only unfinished trailing emphasis markers', () => {
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers('前文 *'), [{ marker: '*', index: 3, rankFromEnd: 1 }]);
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers('前文 **粗'), [{ marker: '**', index: 3, rankFromEnd: 1 }]);
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers('前文 **粗体**'), []);
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers('前文 ~~删除'), [{ marker: '~~', index: 3, rankFromEnd: 1 }]);
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers('前文 __强调'), [{ marker: '__', index: 3, rankFromEnd: 1 }]);
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers('链接 [材料：讲义] 与 $5'), []);
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers('代码 `const value = "**"`'), []);
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers('转义 \\** 不隐藏'), []);
  assert.deepEqual(
    incompleteStreamingMarkdownTailMarkers('**未闭合 与转义 \\**'),
    [{ marker: '**', index: 0, rankFromEnd: 2 }],
  );
  assert.deepEqual(
    incompleteStreamingMarkdownTailMarkers(`**${'字'.repeat(158)}`),
    [{ marker: '**', index: 0, rankFromEnd: 1 }],
  );
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers(`**${'字'.repeat(159)}`), []);
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers(`**${'字'.repeat(161)}`), []);
  assert.deepEqual(
    incompleteStreamingMarkdownTailMarkers(`${'字'.repeat(161)}**尾`),
    [{ marker: '**', index: 161, rankFromEnd: 1 }],
  );
  assert.deepEqual(incompleteStreamingMarkdownTailMarkers(`\`\`\`md\n**源码`), []);
});

test('paste probe flags Markdown clipboard text and leaves plain prose alone', () => {
  const flagged = [
    '# 标题',
    '## 二级标题',
    '> 引用一行',
    '- 无序列表',
    '* 星号列表',
    '1. 有序列表',
    '---',
    '```js\nconst x = 1;\n```',
    '| 列 | 表 |',
    '**粗体**',
    '__下划线粗体__',
    '~~删除线~~',
    '==高亮==',
    '`行内代码`',
    '$x^2$',
    '$\\mathcal{F}(x)$',
    '$$\\frac{a}{b}$$',
    '[链接](https://example.com)',
    '![图片](https://example.com/i.png)',
    '[[双链]]',
    '[[双链|别名]]',
    '> [!note] 提示块',
    '---\ntitle: x\n---',
    '普通段落\n\n第二段 **粗体** 收尾',
  ];
  for (const value of flagged) {
    assert.equal(looksLikeMarkdownSyntax(value), true, `expected flagged: ${value}`);
  }
  const plain = [
    '',
    '   ',
    '普通中文段落,没有任何特殊符号。',
    'Price is $100 and range $10–$20',
    'a * b = c',
    'snake_case_name',
    'C:\\path\\to\\file',
    '1 + 1 = 2',
    '100% done',
    '字里行间有 $ 美元符号也是单只',
  ];
  for (const value of plain) {
    assert.equal(looksLikeMarkdownSyntax(value), false, `expected plain: ${value}`);
  }
  // The probe runs on normalized paste text, so currency protection applies first.
  const normalizedPaste = normalizeMarkdownSource('报价 $100 起,**加粗** 提示', 'userPaste');
  assert.equal(looksLikeMarkdownSyntax(normalizedPaste), true);
  const normalizedPlainPaste = normalizeMarkdownSource('报价 $100 起,不加粗', 'userPaste');
  assert.equal(looksLikeMarkdownSyntax(normalizedPlainPaste), false);
});
