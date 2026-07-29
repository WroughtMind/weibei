import type { EditorBridge } from "../types.js";

interface PreviewDependencies {
  isCompactPreview: boolean;
  post: EditorBridge["post"];
}

/**
 * Resolves the next compact-preview height and suppresses unchanged reports.
 *
 * @param measurements - Heights reported by the preview measurement nodes
 * @param lastReportedHeight - Last height delivered to the native host
 * @returns The normalized height, or null when the host already has that height
 */
export function nextPreviewContentHeight(
  measurements: readonly number[],
  lastReportedHeight: number,
): number | null {
  const height = Math.ceil(
    Math.max(
      1,
      ...measurements.filter((measurement) => Number.isFinite(measurement)),
    ),
  );
  return Math.abs(height - lastReportedHeight) < 1 ? null : height;
}

/**
 * Selects the heading at or immediately above the preview reading line.
 *
 * @param headingTops - Heading positions relative to the viewport
 * @param viewportHeight - Current viewport height
 * @returns The active heading index, or null when the document has no headings
 */
export function activePreviewHeadingIndex(
  headingTops: readonly number[],
  viewportHeight: number,
): number | null {
  if (headingTops.length === 0) return null;
  const readingLine = Math.max(0, viewportHeight * 0.32);
  let activeIndex = 0;
  headingTops.forEach((top, index) => {
    if (top <= readingLine) activeIndex = index;
  });
  return activeIndex;
}

/**
 * Normalizes an untrusted native heading index to an available heading.
 *
 * @param rawIndex - Index supplied by the native bridge
 * @param headingCount - Number of headings currently in the document
 * @returns A valid heading index, or null when the request cannot be fulfilled
 */
export function normalizedPreviewHeadingIndex(
  rawIndex: unknown,
  headingCount: number,
): number | null {
  const index = Number(rawIndex);
  if (!Number.isFinite(index) || headingCount <= 0) return null;
  const normalized = Math.max(0, Math.floor(index));
  return normalized < headingCount ? normalized : null;
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
      const measuredHeight = Math.ceil(
        Math.max(1, ...nodes.map(measuredNodeHeight)),
      );
      const height = nextPreviewContentHeight(
        [measuredHeight],
        lastReportedContentHeight,
      );
      window.WeiBeiCompactPreviewHeight = measuredHeight;
      window.WeiBeiCompactPreviewMeasuredAt = Date.now();
      if (height === null) return;
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
      const activeIndex = activePreviewHeadingIndex(
        headings.map((heading) => heading.getBoundingClientRect().top),
        window.innerHeight,
      );
      if (activeIndex === null) {
        if (lastActiveHeadingIndex !== -1) {
          lastActiveHeadingIndex = -1;
          post("activeHeadingChanged", { index: null });
        }
        return;
      }
      if (activeIndex === lastActiveHeadingIndex) return;
      lastActiveHeadingIndex = activeIndex;
      post("activeHeadingChanged", { index: activeIndex });
    });
  };

  const scrollToHeadingInternal = (rawIndex: unknown): boolean => {
    const headings = headingElements();
    const index = normalizedPreviewHeadingIndex(rawIndex, headings.length);
    const heading = index === null ? null : headings[index];
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
