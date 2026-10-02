import assert from 'node:assert/strict';
import test from 'node:test';
import { mountMermaidMeasurementContainer } from '../src/vendor/mermaid-measurement-context';

function fixture(withHost: boolean) {
  const mounted: string[] = [];
  const host = { appendChild: () => mounted.push('component') };
  const body = { appendChild: () => mounted.push('body') };
  const ownerDocument = {
    body,
    getElementById: (id: string) => {
      assert.equal(id, 'genui-content');
      return withHost ? { querySelector: (selector: string) => {
        assert.equal(selector, '[data-genui]');
        return host;
      } } : null;
    },
  };
  return { container: { ownerDocument } as unknown as HTMLElement, mounted };
}

test('GenUI label measurement shares its visible component context', () => {
  const { container, mounted } = fixture(true);
  mountMermaidMeasurementContainer(container);
  assert.deepEqual(mounted, ['component']);
});

test('ordinary diagram pages retain body measurement', () => {
  const { container, mounted } = fixture(false);
  mountMermaidMeasurementContainer(container);
  assert.deepEqual(mounted, ['body']);
});

test('a component not yet mounted retains the body fallback', () => {
  const { container, mounted } = fixture(false);
  container.ownerDocument.getElementById = () => ({ querySelector: () => null }) as unknown as HTMLElement;
  mountMermaidMeasurementContainer(container);
  assert.deepEqual(mounted, ['body']);
});
