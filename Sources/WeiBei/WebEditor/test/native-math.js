const editor = window.WeiBeiEditor;
const pause = () => new Promise(resolve => setTimeout(resolve, 80));
const expect = (ok, reason) => { if (!ok) throw new Error(reason + ': ' + editor.getMarkdown()); };
const native = async (operation, text, extra = {}) => {
  window.webkit.messageHandlers.nativeInput.postMessage({ operation, text, ...extra });
  await pause();
};
const reset = async (markdown = '') => { editor.setMarkdown(markdown); editor.selectDocumentEndForCheck(); await pause(); };
const visible = (element) => element && getComputedStyle(element).display !== 'none' && element.getBoundingClientRect().width > 0;
const click = async (element) => {
  const rect = element.getBoundingClientRect();
  await native('click', '', { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 });
};
// A/B: type both dollars first, move between them, then enter letters or numbers.
for (const value of ['abc', '1+1']) {
  await reset();
  await native('insert', '$$');
  await native('key', '\uF702', { keyCode: 123 });
  for (const character of value) await native('insert', character);
  const math = document.querySelector('.weibei-math-inline');
  expect(math?.dataset.value === value && visible(math.querySelector('.weibei-math-source')), 'Pair-first typing did not edit formula source');
  await native('key', '\uF701', { keyCode: 125 });
  expect(visible(math.querySelector('.weibei-math-preview')) && !visible(math.querySelector('.weibei-math-source')), 'Down arrow did not immediately show the formula');
  await native('insert', '后');
  expect(editor.getMarkdown().includes('$' + value + '$后'), 'Typing after formula was captured inside it');
  const saved = editor.getMarkdown(); editor.setMarkdown(saved); await pause();
  expect(document.querySelector('.weibei-math-inline')?.dataset.value === value, 'Saving/reopening lost formula');
}
// C: actual clicks beside / on a formula. All input stays in the note, without a form.
await reset('前 $x^2$ 后');
let math = document.querySelector('.weibei-math-inline');
const after = math.nextSibling;
const range = document.createRange(); range.setStart(after, 0); range.setEnd(after, 1);
const edge = range.getBoundingClientRect();
await native('click', '', { x: edge.right, y: edge.top + edge.height / 2 });
expect(visible(math.querySelector('.weibei-math-preview')), 'Click beside formula opened source');
await click(math.querySelector('.weibei-math-preview'));
expect(editor.selectionForCheck().parent === 'math_inline' && visible(math.querySelector('.weibei-math-source'))
  && !math.querySelector('input, textarea'), 'Click on formula did not edit in place');
await native('insert', '+1');
await native('key', '\uF703', { keyCode: 124 });
expect(visible(math.querySelector('.weibei-math-preview')) && editor.getMarkdown().includes('$x^2+1$'), 'Right arrow failed to leave edited formula');
// Block: $$ then Enter opens native multiline source; Command-Enter leaves it.
await reset();
await native('insert', '$$');
await native('key', '\r', { keyCode: 36 });
expect(editor.selectionForCheck().parent === 'math_block', '$$ Enter did not enter block formula');
await native('insert', '1+1');
await native('key', '\r', { keyCode: 36 });
await native('insert', '=2');
math = document.querySelector('.weibei-math-block');
expect(math?.dataset.value === '1+1\n=2', 'Block formula did not preserve newline');
editor.pressKeyForCheck('Enter', { metaKey: true }); await pause();
expect(visible(math.querySelector('.weibei-math-preview')) && editor.selectionForCheck().parent === 'paragraph', 'Block formula did not leave into following paragraph');
await click(math.querySelector('.weibei-math-preview'));
await native('insert', '+0');
editor.pressKeyForCheck('Enter', { metaKey: true }); await pause();
const saved = editor.getMarkdown(); editor.setMarkdown(saved); await pause();
expect(document.querySelector('.weibei-math-block')?.dataset.value === '1+1\n=2+0', 'Block formula edit did not survive reload');

// Slash keyboard selection and the empty-line plus button enter the same source editor.
for (const [command, nodeType] of [['inlineMath', 'math_inline'], ['blockMath', 'math_block']]) {
  await reset(command === 'inlineMath' ? '$a$ 前 ' : '');
  if (command === 'inlineMath') {
    await native('insert', '/inline_math');
    await native('key', '\r', { keyCode: 36 });
  } else {
    await click(document.querySelector('.weibei-line-plus'));
    const button = document.querySelector('#weibei-slash-command-blockMath button');
    button.scrollIntoView({ block: 'nearest' });
    await click(button);
  }
  expect(editor.selectionForCheck().parent === nodeType && editor.selectedTextForCheck() === 'x', 'Menu did not select formula source');
  expect(editor.slashStateForCheck().show === false, 'Formula insertion left the menu open');
  const inserted = document.querySelector('.weibei-math-editing');
  await native('insert', '1/2');
  expect(inserted?.dataset.value === '1/2'
    && editor.slashStateForCheck().show === false, 'Formula input retained placeholder or opened slash menu');
  if (command === 'inlineMath') expect(editor.getMarkdown().startsWith('$a$ 前'), 'Slash replacement damaged preceding formula');
  editor.pressKeyForCheck('Enter', { metaKey: command === 'blockMath' }); await pause();
  await native('insert', '后续正文');
  expect(editor.selectionForCheck().parent === 'paragraph' && editor.getMarkdown().includes('后续正文'), 'Menu formula did not exit into normal text');
}
