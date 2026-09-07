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
window.webkit.messageHandlers.nativeInput.postMessage({ operation: 'checkpoint', text: 'selection and marks' });
// Existing Agent append commands must preserve a selection inside a quote.
await reset('> 原来的引用\n\n正文');
editor.selectFirstTextForCheck('原来的引用');
editor.applyAgentPatch('补充的正文');
expect(document.querySelector('.ProseMirror blockquote').textContent === '原来的引用', 'Agent append overwrote the selected quote');
expect(document.querySelector('.ProseMirror > p:last-child').textContent === '补充的正文', 'Agent append entered the existing quote');
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
await reset('第一段**加粗**文字。\n\n第二段收尾。𠮷');
editor.setEditable(false);
const passage = '第一段加粗文字。\n第二段收尾。𠮷';
editor.setSelectionAskMarks([{ id: 'ask-check', text: passage }]);
editor.setSelectionRemarkMarks([{ id: 'remark-check', text: passage }]);
await pause();
expect(document.querySelectorAll('.weibei-selection-ask-mark').length > 1, 'Cross-paragraph ask underline is missing');
const dot = document.querySelector('.weibei-remark-end');
expect(dot && dot.textContent === '𠮷' && getComputedStyle(dot, '::after').content !== 'none', 'Remark dot is missing or split the final character');
const bounds = dot.getBoundingClientRect();
dot.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: bounds.right, clientY: bounds.top + bounds.height / 2 }));
await pause();
const mark = window.remarkEvents.at(-1);
expect(mark?.recordId === 'remark-check' && Math.abs(mark.rect.y - (bounds.top + bounds.height / 2)) < 2, 'Remark popover lost the clicked passage coordinates');
// Returning from the book reveals the exact occurrence once, without hijacking later scrolling.
await reset('同一句\n\n' + Array(40).fill('阅读中的其他内容。').join('\n\n') + '\n\n同一句\n\n末尾');
editor.setEditable(false);
const textIndex = document.querySelector('.ProseMirror').textContent.replace(/\s/g, '');
const repeatedStart = textIndex.lastIndexOf('同一句');
const target = { id: 'return-check', text: '同一句', anchor: { startOffset: repeatedStart, endOffset: repeatedStart + 3 }, active: true, reveal: 'markdown-return' };
editor.setSelectionRemarkMarks([target]);
editor.setSelectionAskMarks([{ ...target, id: 'ask-return-check' }]);
await pause();
const revealed = document.querySelector('.weibei-remark-active');
expect(revealed && revealed.getBoundingClientRect().top >= 0 && revealed.getBoundingClientRect().bottom < innerHeight, 'Markdown return did not reveal the anchored occurrence');
window.scrollTo(0, 0);
editor.setSelectionRemarkMarks([target]);
expect(window.scrollY === 0, 'A remark refresh took over the reader scroll position');
const markedText = document.querySelector('.weibei-remark-mark').firstChild;
selection.setBaseAndExtent(markedText, 0, markedText, 1);
const eventCount = window.remarkEvents.length;
const askCount = window.askEvents.length;
document.querySelector('.weibei-remark-mark').dispatchEvent(new MouseEvent('click', { bubbles: true }));
await pause();
expect(window.remarkEvents.length === eventCount, 'Selecting a marked passage opened its remark instead');
expect(window.askEvents.length === askCount, 'Selecting a marked passage opened its question instead');
selection.removeAllRanges();
// The same normalized anchor and wrapper implementation also runs in HTML documents.
const html = document.createElement('article');
html.innerHTML = '<p>同一句</p><p>第一段<b>加粗</b>文字。</p><p>第二段收尾。𠮷</p><p style="margin-top:1500px">同一句</p>';
document.body.appendChild(html);
const index = window.WeiBeiSelection.indexDOMSelectionText(html);
const startOffset = index.text.lastIndexOf('同一句');
const htmlMarks = [{ id: 'repeat', text: '同一句', anchor: { startOffset, endOffset: startOffset + 3 }, active: true, reveal: 'html-return' }, { id: 'multi', text: passage }];
window.WeiBeiSelection.applyDOMSelectionMarks(html, htmlMarks, 'weibei-remark-mark', 'data-record-id');
expect(html.querySelectorAll('[data-record-id="repeat"]').length === 1 && !html.firstChild.querySelector('.weibei-remark-mark'), 'HTML marks confused repeated passages');
expect(Array.from(html.querySelectorAll('[data-record-id="multi"]')).map(node => node.textContent).join('') === passage.replace(/\s/g, ''), 'HTML marks lost formatted or multi-paragraph text');
const htmlTarget = html.querySelector('.weibei-remark-active').getBoundingClientRect();
expect(htmlTarget.top >= 0 && htmlTarget.bottom <= innerHeight, 'HTML return did not reveal the anchored occurrence');
window.scrollTo(0, 0);
window.WeiBeiSelection.applyDOMSelectionMarks(html, htmlMarks, 'weibei-remark-mark', 'data-record-id');
expect(window.scrollY === 0, 'HTML mark refresh took over scrolling');
html.remove();
return { quotes: true, composition: true, lists: true, direction: true, markdownMarks: true, htmlMarks: true, excerptReturn: true };
