import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import { build } from 'esbuild';

type RailSection = { id: string; title: string };
type RailMessage = { loadToken: string; sections: RailSection[] };

// Exercise the actual Office bridge; renderers are irrelevant to messages from an
// already loaded document and are stubbed rather than requiring browser layout.
async function officeFixture() {
  const source = await readFile(new URL('../../OfficeReader/office.ts', import.meta.url), 'utf8');
  const result = await build({
    stdin: {
      contents: source + '\n(globalThis as any).setOfficeFixture = (value: HTMLElement, presentation?: PptxViewer) => { root = value; viewer = presentation; };',
      loader: 'ts', resolveDir: process.cwd(),
    },
    bundle: true, format: 'iife', write: false, logLevel: 'silent',
    plugins: [{
      name: 'office-renderer-stubs',
      setup(builder) {
        builder.onResolve({ filter: /.*/ }, ({ path }) => ({ path, namespace: 'office-stub' }));
        builder.onLoad({ filter: /.*/, namespace: 'office-stub' }, () => ({ contents: `
          export default class JSZip {}
          export class PptxViewer {}
          export const RECOMMENDED_ZIP_LIMITS = {};
          export const renderAsync = () => {};
          export const renderOmml = () => {};
          export const prepareGraphics = () => {};
          export const mountWordGraphics = () => {};
          export const renderGraphic = () => {};
          export const graphicRelations = () => {};
          export const has3DChart = () => {};
          export const render3DChart = () => {};
          export const disposeGraphics = () => {};
          export const drawWMFText = () => {};
          export const renderWMF = () => {};
          export const renderEMF = () => {};
        ` }));
      },
    }],
  });
  const messages: RailMessage[] = [];
  const context: Record<string, any> = {
    window: {
      addEventListener() {}, setTimeout() {},
      webkit: { messageHandlers: {
        contentRailSections: { postMessage: (message: RailMessage) => messages.push(message) },
      } },
    },
    document: { body: { dataset: { weibeiReaderLoadToken: 'fixture-load' } } },
  };
  runInNewContext(result.outputFiles[0].text, context);
  const label = { dataset: { weibeiSlideLabel: '1' }, textContent: '第 1 页' };
  const paragraph = {
    dataset: { weibeiLocation: 'word/document.xml#p0' }, textContent: 'Loaded Word paragraph',
    className: '', getAttribute() { return null; }, closest() { return null; }, scrollIntoView() {},
  };
  const root = { querySelectorAll: (selector: string) => selector === '[data-weibei-slide-label]' ? [label] : [paragraph] };
  context.setOfficeFixture(root);
  return { context, root, label, paragraph, messages, rail: context.window.WeiBeiContentRail };
}

test('Office scan and language changes preserve the load-token section envelope', async () => {
  const { context, root, label, paragraph, messages, rail } = await officeFixture();
  rail.scan();
  assert.equal(messages.length, 1);
  assert.equal(messages[0].loadToken, 'fixture-load');
  assert.equal(messages[0].sections[0].id, paragraph.dataset.weibeiLocation);

  context.setOfficeFixture(root, {
    presentationData: { slides: [{ slidePath: 'ppt/slides/slide1.xml' }] }, slideCount: 1,
  });
  rail.setLanguage('english');
  assert.equal(label.textContent, 'Page 1');
  assert.equal(messages.at(-1)?.loadToken, 'fixture-load');
  assert.equal(messages.at(-1)?.sections[0].title, 'Page 1');
  rail.setLanguage('chinese');
  assert.equal(label.textContent, '第 1 页');
  assert.equal(messages.at(-1)?.loadToken, 'fixture-load');
  assert.equal(messages.at(-1)?.sections[0].title, '第 1 页');
});

test('Office scroll requests keep the synchronous target acceptance result', async () => {
  const { paragraph, rail } = await officeFixture();
  assert.equal(rail.scrollTo('word/document.xml#missing'), false);
  assert.equal(rail.scrollTo(paragraph.dataset.weibeiLocation), true);
});
