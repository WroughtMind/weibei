import assert from 'node:assert/strict';
import test from 'node:test';
import {
  joinFrontmatter,
  inlineMathInputPattern,
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
