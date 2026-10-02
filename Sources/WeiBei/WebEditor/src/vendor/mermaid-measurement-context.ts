/** Keep Mermaid's hidden label measurements under the same component CSS as
 * its visible SVG. The GenUI root supplies numeral features and box sizing;
 * measuring under body and then moving the SVG can clip otherwise valid text.
 * Pages without a GenUI component retain the engine's original body fallback. */
export function mountMermaidMeasurementContainer(container: HTMLElement): void {
  const page = container.ownerDocument;
  const host = page.getElementById('genui-content')?.querySelector('[data-genui]');
  (host ?? page.body)?.appendChild(container);
}
