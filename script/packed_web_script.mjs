import { createHash } from 'node:crypto';
import pako from 'pako';

export function packedWebScript(program) {
  const hash = `'sha256-${createHash('sha256').update(program).digest('base64')}'`;
  const compressed = Buffer.from(pako.gzip(program, { level: 9, header: { time: 0 } })).toString('base64');
  return { hash, source: `(async () => {
  const bytes = Uint8Array.from(atob(${JSON.stringify(compressed)}), c => c.charCodeAt(0));
  const script = document.createElement('script');
  script.textContent = await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'))).text();
  document.head.append(script);
  script.remove();
})()` };
}
