const editor = window.WeiBeiEditor;
const pause = () => new Promise(resolve => setTimeout(resolve, 80));
const expect = (condition, reason) => { if (!condition) throw new Error(reason); };
const native = async (operation, text) => {
  window.webkit.messageHandlers.nativeInput.postMessage({ operation, text });
  await pause();
};
const reset = async (markdown = '') => {
  editor.setEditable(true);
  editor.setMarkdown(markdown);
  editor.selectDocumentEndForCheck();
  await pause();
};
// Native NSTextInputClient input is essential: the editor's scripted typing helper
// bypasses the WebKit substitutions that caused repeated closing quotes.
window.webkit.messageHandlers.nativeInput.postMessage({ operation: 'checkpoint', text: 'quotes' });
for (const text of ['""""""', "''''''", '“中文”‘引号’']) {
  await reset();
  for (const character of text) await native('insert', character);
  expect(editor.getMarkdown().trim() === text, 'Native quote input changed: ' + editor.getMarkdown());
}
window.webkit.messageHandlers.nativeInput.postMessage({ operation: 'checkpoint', text: 'composition' });
for (const initial of ['', '\u200b']) {
  await reset(initial);
  await native('marked', 'p');
  expect(editor.compositionStateForCheck().composing, 'First pinyin did not enter composition');
  await native('marked', 'pin');
  const root = document.querySelector('.ProseMirror');
  expect(root.textContent.replace(/\u200b/g, '') === 'pin', 'Pinyin lost its first character');
  expect(getComputedStyle(root, '::selection').backgroundColor === 'rgba(0, 0, 0, 0)', 'Pinyin inherited the red reading selection');
  await native('insert', '拼');
  expect(!editor.compositionStateForCheck().composing && editor.getMarkdown().replace(/\u200b/g, '').trim() === '拼', 'Composition did not commit once');
}
for (const initial of ['', '\u200b']) {
  await reset(initial);
  for (const character of '1. ') await native('insert', character);
  expect(document.querySelector('.ProseMirror > ol > li'), 'A visually empty line could not start a list');
}
window.webkit.messageHandlers.nativeInput.postMessage({ operation: 'checkpoint', text: 'append and selection' });
// Explicit insertion must preserve a selection inside a quote and append outside it.
await reset('> 原来的引用\n\n正文');
editor.selectFirstTextForCheck('原来的引用');
editor.applyAgentPatch('**摘抄来源**\n\n新的原文');
expect(document.querySelector('.ProseMirror blockquote').textContent === '原来的引用', 'Append overwrote the selected quote');
expect(document.querySelector('.ProseMirror > p:last-child').textContent === '新的原文', 'Append nested the excerpt at the cursor');
// Forward and backward selection must use different ends of the same passage.
await reset('第一段选择文字。\n\n第二段选择文字。');
const paragraphs = document.querySelectorAll('.ProseMirror > p');
const selection = window.getSelection();
selection.setBaseAndExtent(paragraphs[0].firstChild, 0, paragraphs[1].firstChild, 5);
document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
await pause();
const forward = window.selectionEvents.at(-1)?.rect;
selection.setBaseAndExtent(paragraphs[1].firstChild, 5, paragraphs[0].firstChild, 0);
document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
await pause();
const backward = window.selectionEvents.at(-1)?.rect;
expect(forward && backward && backward.y < forward.y && backward.prefersAbove && !forward.prefersAbove, 'Selection popover ignored drag direction');
// Reading marks span formatting boundaries, survive refresh, and report their live location.
await reset('第一段**加粗**文字。\n\n第二段收尾。');
editor.setEditable(false);
const passage = '第一段加粗文字。\n第二段收尾。';
editor.setSelectionAskMarks([{ id: 'ask-check', text: passage }]);
editor.setSelectionRemarkMarks([{ id: 'remark-check', text: passage }]);
await pause();
expect(document.querySelectorAll('.weibei-selection-ask-mark').length > 1, 'Cross-paragraph ask underline is missing');
const dot = document.querySelector('.weibei-remark-end');
expect(dot && getComputedStyle(dot, '::after').content !== 'none', 'Remark dot is missing');
const bounds = dot.getBoundingClientRect();
dot.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: bounds.right, clientY: bounds.top + bounds.height / 2 }));
await pause();
const mark = window.remarkEvents.at(-1);
expect(mark?.recordId === 'remark-check' && Math.abs(mark.rect.y - (bounds.top + bounds.height / 2)) < 2, 'Remark popover lost the clicked passage coordinates');
// The same normalized anchor and wrapper implementation also runs in HTML documents.
const html = document.createElement('article');
html.innerHTML = '<p>同一句</p><p>第一段<b>加粗</b>文字。</p><p>第二段收尾。</p><p>同一句</p>';
document.body.appendChild(html);
const index = window.WeiBeiSelection.indexDOMSelectionText(html);
const startOffset = index.text.lastIndexOf('同一句');
window.WeiBeiSelection.applyDOMSelectionMarks(html, [{ id: 'repeat', text: '同一句', anchor: { startOffset, endOffset: startOffset + 3 } }, { id: 'multi', text: passage }], 'remark', 'data-id');
expect(html.querySelectorAll('[data-id="repeat"]').length === 1 && !html.firstChild.querySelector('.remark'), 'HTML marks confused repeated passages');
expect(Array.from(html.querySelectorAll('[data-id="multi"]')).map(node => node.textContent).join('') === passage.replace(/\s/g, ''), 'HTML marks lost formatted or multi-paragraph text');
html.remove();
return { quotes: true, composition: true, lists: true, append: true, direction: true, markdownMarks: true, htmlMarks: true };
