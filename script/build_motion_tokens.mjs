import { readFile, writeFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const source = 'DesignSystem/08-implementation/tokens.json';
const { motion } = JSON.parse(await readFile(new URL(source, root), 'utf8'));
const { easing, durationMilliseconds } = motion;
const camel = name => name.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
const bezier = points => 'cubic-bezier(' + points.join(', ') + ')';
const cubicCurves = Object.entries(easing).filter(([name]) => name !== 'ease-spring');
const indent = (lines, spaces) => lines.map(line => ' '.repeat(spaces) + line).join('\n');
const css = [
  ':root {',
  ...cubicCurves.map(([name, points]) => '  --' + name + ': ' + bezier(points) + ';'),
  '  --ease-spring: var(--ease-out-strong);',
  ...Object.entries(durationMilliseconds).map(([name, duration]) => '  --duration-' + name + ': ' + duration + 'ms;'),
  '}',
  '',
  '@supports (animation-timing-function: linear(0, 1)) {',
  '  :root { --ease-spring: linear(' + easing['ease-spring'].join(', ') + '); }',
  '}',
];
const swift = [
  '// Generated from ' + source + '.',
  '',
  'public enum WeiBeiMotionTokens {',
  '    public struct Cubic: Sendable {',
  '        public let x1: Double',
  '        public let y1: Double',
  '        public let x2: Double',
  '        public let y2: Double',
  '    }',
  '',
  ...cubicCurves.map(([name, [x1, y1, x2, y2]]) =>
    '    public static let ' + camel(name) + ' = Cubic(x1: ' + x1 + ', y1: ' + y1 + ', x2: ' + x2 + ', y2: ' + y2 + ')'),
  '',
  ...Object.entries(durationMilliseconds).map(([name, duration]) =>
    '    public static let ' + camel('duration-' + name) + ' = ' + duration / 1000),
  '',
  '    public static let css = """',
  indent(css, 4).replace(/^ +$/gm, ''),
  '    """',
  '}',
  '',
].join('\n');
const web = '/* Generated from ' + source + '. */\n' + css.join('\n') + '\n';
const scrollSource = await readFile(new URL('Sources/WeiBei/Resources/Editor/motion.js', root), 'utf8');

for (const [path, content] of [
  ['Sources/WeiBeiCore/MotionTokens.swift', swift],
  ['Sources/WeiBei/Resources/Editor/motion.css', web],
  ['website/motion.css', web],
  ['website/motion.js', '// Copied from Sources/WeiBei/Resources/Editor/motion.js.\n' + scrollSource],
]) {
  const file = new URL(path, root);
  if (process.argv.includes('--check')) {
    const actual = await readFile(file, 'utf8').catch(error => {
      if (error.code !== 'ENOENT') throw error;
    });
    if (actual === content) continue;
    console.error(path + ' is out of date. Run node script/build_motion_tokens.mjs.');
    process.exitCode = 1;
  } else {
    await writeFile(file, content);
  }
}
