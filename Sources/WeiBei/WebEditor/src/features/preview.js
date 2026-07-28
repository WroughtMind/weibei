/**
 * Creates compact-preview measurement, heading tracking, and quiet scrollbar behavior.
 *
 * @param {object} dependencies - Preview dependencies
 * @returns {object} Preview feature API
 */
export function createPreviewFeature({ isCompactPreview, post }) {

  document.documentElement.dataset.weibeiCompactPreview = isCompactPreview ? 'true' : 'false';

  let contentHeightFrame = 0;
  let lastReportedContentHeight = 0;
  const contentHeightDelayHandles = new Set();

  const compactPreviewMeasureNodes = () => [
    document.querySelector('#editor'),
    document.querySelector('.milkdown'),
    document.querySelector('.ProseMirror'),
  ].filter(Boolean);

  const measuredNodeHeight = (node) => {
    const rect = node.getBoundingClientRect?.();
    return Math.max(
      0,
      node.scrollHeight || 0,
      node.offsetHeight || 0,
      node.clientHeight || 0,
      rect?.height || 0
    );
  };

  const reportContentHeight = () => {
    if (!isCompactPreview) return;
    window.cancelAnimationFrame(contentHeightFrame);
    contentHeightFrame = window.requestAnimationFrame(() => {
      const nodes = compactPreviewMeasureNodes();
      const height = Math.ceil(Math.max(1, ...nodes.map(measuredNodeHeight)));
      window.WeiBeiCompactPreviewHeight = height;
      window.WeiBeiCompactPreviewMeasuredAt = Date.now();
      if (Math.abs(height - lastReportedContentHeight) < 1) return;
      lastReportedContentHeight = height;
      post('contentHeightChanged', { height });
    });
  };

  const scheduleContentHeightReports = () => {
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
    document.fonts?.ready?.then(() => {
      if (isCompactPreview) reportContentHeight();
    }).catch(() => {});
  };

  const installContentHeightObserver = () => {
    if (!isCompactPreview) return;
    if (window.ResizeObserver) {
      const observer = new ResizeObserver(reportContentHeight);
      compactPreviewMeasureNodes().forEach((node) => observer.observe(node));
    }
    scheduleContentHeightReports();
  };

  const annotateMathErrors = () => {
    window.requestAnimationFrame(() => {
      document.querySelectorAll('.ProseMirror .katex-error').forEach((element) => {
        if (element.getAttribute('title')) return;
        element.setAttribute('title', editorLabel('mathError'));
      });
    });
  };

  const quietScrollableSelector = '#editor, .ProseMirror pre, .ProseMirror div[data-type="math_block"], .ProseMirror div[data-type="math-block"]';
  const scrollFadeTimers = new WeakMap();

  const markScrollActive = (element) => {
    if (!(element instanceof Element)) return;
    element.classList.add('weibei-scroll-active');
    const timer = scrollFadeTimers.get(element);
    if (timer) window.clearTimeout(timer);
    scrollFadeTimers.set(element, window.setTimeout(() => {
      element.classList.remove('weibei-scroll-active');
      scrollFadeTimers.delete(element);
    }, 850));
  };

  const installQuietScrollIndicators = () => {
    document.addEventListener('scroll', (event) => {
      const target = event.target instanceof Element
        ? event.target.closest(quietScrollableSelector)
        : null;
      if (target) markScrollActive(target);
    }, true);
  };

  const headingElements = () => Array.from(document.querySelectorAll('.ProseMirror h1, .ProseMirror h2, .ProseMirror h3, .ProseMirror h4'));
  let activeHeadingFrame = 0;
  let lastActiveHeadingIndex = -2;

  const reportActiveHeading = () => {
    window.cancelAnimationFrame(activeHeadingFrame);
    activeHeadingFrame = window.requestAnimationFrame(() => {
      const headings = headingElements();
      if (headings.length === 0) {
        if (lastActiveHeadingIndex !== -1) {
          lastActiveHeadingIndex = -1;
          post('activeHeadingChanged', { index: null });
        }
        return;
      }
      const readingLine = Math.max(0, window.innerHeight * 0.32);
      let activeIndex = 0;
      headings.forEach((heading, index) => {
        if (heading.getBoundingClientRect().top <= readingLine) activeIndex = index;
      });
      if (activeIndex === lastActiveHeadingIndex) return;
      lastActiveHeadingIndex = activeIndex;
      post('activeHeadingChanged', { index: activeIndex });
    });
  };

  const scrollToHeadingInternal = (rawIndex) => {
    const index = Number(rawIndex);
    const headings = headingElements();
    const heading = Number.isFinite(index) ? headings[Math.max(0, Math.floor(index))] : null;
    if (!heading) return false;
    heading.scrollIntoView({ block: 'start', behavior: 'smooth' });
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
