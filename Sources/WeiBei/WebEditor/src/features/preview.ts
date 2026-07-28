import type { EditorBridge } from "../types.js";

interface PreviewDependencies {
  isCompactPreview: boolean;
  post: EditorBridge["post"];
}

/**
 * Creates compact-preview measurement, heading tracking, and quiet scrollbar behavior.
 *
 * @param dependencies - Preview dependencies
 * @returns Preview feature API
 */
export function createPreviewFeature({
  isCompactPreview,
  post,
}: PreviewDependencies) {
  document.documentElement.dataset.weibeiCompactPreview = isCompactPreview
    ? "true"
    : "false";

  let contentHeightFrame = 0;
  let lastReportedContentHeight = 0;
  const contentHeightDelayHandles = new Set<number>();

  const compactPreviewMeasureNodes = (): Element[] =>
    [
      document.querySelector("#editor"),
      document.querySelector(".milkdown"),
      document.querySelector(".ProseMirror"),
    ].filter((node): node is Element => node !== null);

  const measuredNodeHeight = (node: Element): number => {
    const htmlNode = node as HTMLElement;
    const rect = node.getBoundingClientRect();
    return Math.max(
      0,
      htmlNode.scrollHeight || 0,
      htmlNode.offsetHeight || 0,
      htmlNode.clientHeight || 0,
      rect?.height || 0,
    );
  };

  const reportContentHeight = (): void => {
    if (!isCompactPreview) return;
    window.cancelAnimationFrame(contentHeightFrame);
    contentHeightFrame = window.requestAnimationFrame(() => {
      const nodes = compactPreviewMeasureNodes();
      const height = Math.ceil(Math.max(1, ...nodes.map(measuredNodeHeight)));
      window.WeiBeiCompactPreviewHeight = height;
      window.WeiBeiCompactPreviewMeasuredAt = Date.now();
      if (Math.abs(height - lastReportedContentHeight) < 1) return;
      lastReportedContentHeight = height;
      post("contentHeightChanged", { height });
    });
  };

  const scheduleContentHeightReports = (): void => {
    if (!isCompactPreview) return;
    for (const handle of contentHeightDelayHandles) window.clearTimeout(handle);
    contentHeightDelayHandles.clear();
    lastReportedContentHeight = 0;
    reportContentHeight();
    window.requestAnimationFrame(() => {
      reportContentHeight();
      window.requestAnimationFrame(reportContentHeight);
    });
    for (const delay of [40, 120, 240, 480]) {
      const handle = window.setTimeout(() => {
        contentHeightDelayHandles.delete(handle);
        reportContentHeight();
      }, delay);
      contentHeightDelayHandles.add(handle);
    }
    document.fonts?.ready
      ?.then(() => {
        if (isCompactPreview) reportContentHeight();
      })
      .catch(() => {});
  };

  const installContentHeightObserver = (): void => {
    if (!isCompactPreview) return;
    if (window.ResizeObserver) {
      const observer = new ResizeObserver(reportContentHeight);
      compactPreviewMeasureNodes().forEach((node) => observer.observe(node));
    }
    scheduleContentHeightReports();
  };

  const quietScrollableSelector =
    '#editor, .ProseMirror pre, .ProseMirror div[data-type="math_block"], .ProseMirror div[data-type="math-block"]';
  const scrollFadeTimers = new WeakMap<Element, number>();

  const markScrollActive = (element: Element): void => {
    element.classList.add("weibei-scroll-active");
    const timer = scrollFadeTimers.get(element);
    if (timer) window.clearTimeout(timer);
    const fadeTimer = window.setTimeout(() => {
      element.classList.remove("weibei-scroll-active");
      scrollFadeTimers.delete(element);
    }, 850);
    scrollFadeTimers.set(element, fadeTimer);
  };

  const installQuietScrollIndicators = (): void => {
    document.addEventListener(
      "scroll",
      (event) => {
        const target =
          event.target instanceof Element
            ? event.target.closest(quietScrollableSelector)
            : null;
        if (target) markScrollActive(target);
      },
      true,
    );
  };

  const headingElements = (): HTMLElement[] =>
    Array.from(
      document.querySelectorAll<HTMLElement>(
        ".ProseMirror h1, .ProseMirror h2, .ProseMirror h3, .ProseMirror h4",
      ),
    );
  let activeHeadingFrame = 0;
  let lastActiveHeadingIndex = -2;

  const reportActiveHeading = (): void => {
    window.cancelAnimationFrame(activeHeadingFrame);
    activeHeadingFrame = window.requestAnimationFrame(() => {
      const headings = headingElements();
      if (headings.length === 0) {
        if (lastActiveHeadingIndex !== -1) {
          lastActiveHeadingIndex = -1;
          post("activeHeadingChanged", { index: null });
        }
        return;
      }
      const readingLine = Math.max(0, window.innerHeight * 0.32);
      let activeIndex = 0;
      headings.forEach((heading, index) => {
        if (heading.getBoundingClientRect().top <= readingLine)
          activeIndex = index;
      });
      if (activeIndex === lastActiveHeadingIndex) return;
      lastActiveHeadingIndex = activeIndex;
      post("activeHeadingChanged", { index: activeIndex });
    });
  };

  const scrollToHeadingInternal = (rawIndex: unknown): boolean => {
    const index = Number(rawIndex);
    const headings = headingElements();
    const heading = Number.isFinite(index)
      ? headings[Math.max(0, Math.floor(index))]
      : null;
    if (!heading) return false;
    heading.scrollIntoView({ block: "start", behavior: "smooth" });
    window.setTimeout(reportActiveHeading, 180);
    return true;
  };

  return {
    installContentHeightObserver,
    installQuietScrollIndicators,
    reportActiveHeading,
    scheduleContentHeightReports,
    scrollToHeading: scrollToHeadingInternal,
  };
}
