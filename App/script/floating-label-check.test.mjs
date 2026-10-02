import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

// Execute the exact acceptance program with synthetic DOM geometry. These
// fixtures test clipping decisions, not WKWebView layout or product rendering.
const source = readFileSync(new URL('../Sources/CatalystBusinessCheck.swift', import.meta.url), 'utf8');
const script = source.match(/private static let floatingDiagramCheckScript = #"""([\s\S]*?)"""#/)[1];
const rectangle = (left, top, width, height) => ({ left, top, width, height, right: left + width, bottom: top + height });
const style = (overflowX = 'visible', overflowY = 'visible') => ({
  overflowX, overflowY, fontFamily: 'Synthetic Font', fontSize: '13px', lineHeight: '20.8px',
});

function fixture({ firstRangeWidth = 80, clip, missingEnd = false, svgRightOutside = false } = {}) {
  const root = {
    parentElement: null,
    getBoundingClientRect: () => rectangle(0, 0, 352, 120),
    style: style(),
    contains(node) {
      for (let current = node; current; current = current.parentElement) if (current === root) return true;
      return false;
    },
  };
  const svg = {
    parentElement: root,
    style: style(),
    getBoundingClientRect: () => rectangle(20, 10, svgRightOutside ? 400 : 300, 65),
  };
  const labels = ['WB514_START', 'WB514_END'].map((text, index) => {
    const left = index === 0 ? 40 : 200;
    const foreign = {
      parentElement: svg, localName: 'foreignObject', style: style(),
      getBoundingClientRect: () => rectangle(left, 20, 90, 22),
      getAttribute: name => name === 'width' ? '90' : '22',
    };
    const width = index === 0 ? firstRangeWidth : 70;
    const label = {
      textContent: text, parentElement: foreign, localName: 'span', style: style(),
      clientWidth: 90, scrollWidth: width,
      getBoundingClientRect: () => rectangle(left, 20, 90, 22),
      closest: name => name === 'foreignObject' ? foreign : null,
      textNodes: [{ textContent: text, rect: rectangle(left + 2, 22, width, 16) }],
    };
    if (index === 0 && clip) {
      label.parentElement = {
        parentElement: foreign, localName: 'div', style: style(clip.x, clip.y),
        getBoundingClientRect: () => rectangle(left, 20, clip.width, clip.height),
      };
    }
    return label;
  });
  if (missingEnd) labels.pop();
  svg.textContent = 'UNRELATED_CSS_SENTINEL;' + labels.map(label => label.textContent).join('');
  svg.querySelectorAll = selector => selector === '.nodeLabel' ? labels : [];
  root.textContent = svg.textContent;
  root.querySelector = selector => selector === 'svg' ? svg : null;
  const document = {
    querySelector: selector => selector === '#genui-content' ? root : null,
    createTreeWalker(label) {
      let index = 0;
      return { nextNode: () => label.textNodes[index++] ?? null };
    },
    createRange() {
      let selected;
      return {
        selectNodeContents(node) { selected = node; },
        getClientRects: () => [selected.rect],
      };
    },
  };
  return runInNewContext(script, { document, NodeFilter: { SHOW_TEXT: 4 }, getComputedStyle: node => node.style,
    innerWidth: 352, innerHeight: 120 }, { timeout: 1000 });
}

test('both visible labels pass and diagnostics retain geometry/fonts without SVG CSS', () => {
  const result = fixture();
  assert.equal(result.ok, true);
  assert.equal(result.stage, 'passed');
  assert.equal(result.labels.length, 2);
  assert.equal(result.labels.every(label => label.visible), true);
  assert.equal(result.labels[0].font.size, '13px');
  assert.equal(result.labels[0].text_rects.length, 1);
  assert.equal(JSON.stringify(result).includes('UNRELATED_CSS_SENTINEL'), false);
});

test('complete SVG text still fails when the label range exceeds its foreignObject', () => {
  const result = fixture({ firstRangeWidth: 104 });
  assert.equal(result.ok, false);
  assert.equal(result.stage, 'diagram_label_foreign_object_clip');
  assert.equal(result.labels[0].text, 'WB514_START');
  assert.equal(result.labels[0].text_rects[0][2], 104);
  assert.equal(result.labels[0].foreign_rect[2], 90);
  assert.equal(result.labels[1].text, 'WB514_END');
  assert.equal(result.labels[1].visible, true, 'Both labels must be observed even when the first fails');
});

test('horizontal clipping rejects overflow on x and records the clip rectangle', () => {
  const result = fixture({ clip: { x: 'clip', y: 'visible', width: 50, height: 22 } });
  assert.equal(result.ok, false);
  assert.equal(result.stage, 'diagram_label_ancestor_clip');
  assert.equal(result.labels[0].clips[0].x, 'clip');
  assert.equal(result.labels[0].clips[0].visible, false);
});

test('vertical clipping rejects overflow on y', () => {
  const result = fixture({ clip: { x: 'visible', y: 'clip', width: 90, height: 10 } });
  assert.equal(result.ok, false);
  assert.equal(result.stage, 'diagram_label_ancestor_clip');
  assert.equal(result.labels[0].clips[0].y, 'clip');
});

test('a clip only constrains its declared axis', () => {
  assert.equal(fixture({ clip: { x: 'clip', y: 'visible', width: 90, height: 10 } }).ok, true);
  assert.equal(fixture({ clip: { x: 'visible', y: 'clip', width: 50, height: 22 } }).ok, true);
});

test('missing expected text and SVG viewport overflow retain their original rejection', () => {
  assert.equal(fixture({ missingEnd: true }).stage, 'diagram_labels_or_raw_source');
  assert.equal(fixture({ svgRightOutside: true }).stage, 'diagram_svg_bounds');
});

test('failure exit trap preserves the compact label diagnostic', () => {
  const shell = readFileSync(new URL('check-ci.sh', import.meta.url), 'utf8');
  const copy = shell.match(/save_evidence\(\) \{[\s\S]*?\n\}/)[0];
  const scratch = mkdtempSync(join(tmpdir(), 'weibei-label-evidence-'));
  try {
    const support = join(scratch, 'Support');
    mkdirSync(join(support, 'Results'), { recursive: true });
    const diagnostic = JSON.stringify({ stage: 'diagram_label_foreign_object_clip', labels: ['WB514_START', 'WB514_END'] });
    writeFileSync(join(support, 'Results/floating-rich-diagnostic.json'), diagnostic);
    // Empty PID cannot signal a process. The real trap's kill is caught by || true.
    const result = spawnSync('bash', ['-c', `server_pid=''
CHECK_SUPPORT="$1"
CHECK_DIR="$2"
mkdir -p App/Evidence
${copy}
trap save_evidence EXIT
exit 7`, 'fixture', support, scratch], { cwd: scratch, encoding: 'utf8' });
    assert.equal(result.status, 7);
    assert.equal(readFileSync(join(scratch, 'App/Evidence/ci-floating-rich-diagnostic.json'), 'utf8'), diagnostic);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
