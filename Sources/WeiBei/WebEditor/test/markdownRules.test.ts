import assert from 'node:assert/strict';
import test from 'node:test';
import {
  joinFrontmatter,
  normalizeHtmlBreaks,
  normalizeMarkdownOutput,
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
});
