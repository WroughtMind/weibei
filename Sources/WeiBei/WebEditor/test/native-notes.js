const e = window.WeiBeiEditor;
const pause = () => new Promise(resolve => setTimeout(resolve, 40));
const expect = (ok, reason) => { if (!ok) throw new Error(reason + ': ' + e.getMarkdown()); };
const wait = async predicate => {
  for (let i = 0; i < 20; i++) { if (predicate()) return; await pause(); }
  throw new Error('Timed out: ' + predicate + '; focus=' + document.activeElement?.outerHTML.slice(0, 250) + '; selection=' + JSON.stringify(e.selectionForCheck()) + '; markdown=' + e.getMarkdown());
};
const native = (operation, text, extra = {}) => window.webkit.messageHandlers.nativeInput.postMessage({ operation, text, ...extra });
const reset = async markdown => { e.setMarkdown(markdown); e.selectDocumentEndForCheck(); await pause(); };
const key = (text, keyCode, shift = false) => native('key', text, { keyCode, shift });
const paste = (text, html = '') => {
  const data = new DataTransfer(); data.setData('text/plain', text);
  if (html) data.setData('text/html', html);
  document.querySelector('.ProseMirror').dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data }));
};

await reset('[[旧目标|旧标题]]');
const link = document.querySelector('.weibei-wikilink');
link.click();
let inputs = link.querySelectorAll('input');
inputs[0].value = '新目标';
key('\t', 48); await wait(() => document.activeElement === inputs[1]);
inputs[1].value = '新标题';
const outside = document.createElement('button'); document.body.append(outside); outside.focus();
await wait(() => !link.querySelector('input'));
expect(e.getMarkdown().includes('[[新目标|新标题]]'), 'Leaving link fields lost changes');
link.click(); inputs = link.querySelectorAll('input');
inputs[0].dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', isComposing: true, bubbles: true }));
expect(link.querySelector('input'), 'IME confirmation ended link editing');
await pause();
key('\r', 36); await wait(() => !link.querySelector('input') && document.activeElement === document.querySelector('.ProseMirror'));
native('insert', '后'); await wait(() => e.getMarkdown().includes(']]后'));
expect(window.wikiEvents.length === 0, 'Editing link fields navigated to another note');
outside.remove();

for (const markdown of ['正文', '```text\n正文\n```']) {
  await reset(markdown); const before = e.getMarkdown();
  key('\t', 48); await wait(() => e.getMarkdown() !== before);
  key('\t', 48, true); await wait(() => e.getMarkdown() === before);
  expect(document.activeElement === document.querySelector('.ProseMirror'), 'Reverse indent left editor');
}

await reset('替换'); e.selectFirstTextForCheck('替换'); paste('\talpha\n\tbeta');
await wait(() => e.getMarkdown().includes('beta'));
expect(!document.querySelector('.ProseMirror table'), 'Indented text became a table');
await reset('替换'); e.selectFirstTextForCheck('替换'); paste('A\tB\n1\t2');
expect(document.querySelectorAll('.ProseMirror table tr').length === 2, 'Rectangular data did not become a table');
e.selectFirstTextForCheck('1'); paste('\t右', '<table><tr><td></td><td>右</td></tr></table>');
expect(document.querySelector('.ProseMirror table').textContent.includes('右'), 'Sparse spreadsheet paste was lost');

for (const markdown of ['* 第一项\n* 第二项', '| 标题 |\n| --- |\n| 单元格 |']) {
  await reset(markdown);
  native('insert', '/inline_math'); await wait(() => e.slashStateForCheck().show);
  key('\t', 48); await wait(() => e.selectionForCheck().parent === 'math_inline');
  expect(e.selectedTextForCheck() === 'x', 'Nested menu did not select source');
  native('insert', '1+1'); await wait(() => e.getMarkdown().includes('$1+1$'));
  key('\r', 36); await wait(() => e.selectionForCheck().parent === 'paragraph');
  const saved = e.getMarkdown(); e.setMarkdown(saved);
  expect(document.querySelector('.weibei-math-inline')?.dataset.value === '1+1', 'Nested math was lost after reload');
}

await reset('查找甲\n\n查找乙\n\n编辑位置');
const saved = e.getMarkdown();
window.nativeFindResult = null; native('find', '查找'); await wait(() => window.nativeFindResult === true);
window.nativeFindResult = null; native('find', '查找', { backwards: true }); await wait(() => window.nativeFindResult === true);
expect(e.getMarkdown() === saved && e.selectedTextForCheck() === '查找', 'Find did not locate text without modifying the note');
window.nativeFindResult = null; native('find', '不存在的内容'); await wait(() => window.nativeFindResult === false);
window.nativeFindResult = null; native('find', ''); await wait(() => window.nativeFindResult !== null);
e.selectDocumentEndForCheck();
native('focus', ''); await pause();
native('insert', '继续'); await wait(() => e.getMarkdown().endsWith('编辑位置继续\n'));
