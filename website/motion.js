// Copied from Sources/WeiBei/Resources/Editor/motion.js.
(() => {
  const root = document.documentElement;
  const systemReduced = matchMedia('(prefers-reduced-motion: reduce)');
  let scrollFrame = 0;
  let scrollListeners;
  let restoreSnapping = [];

  function cancelScroll() {
    cancelAnimationFrame(scrollFrame);
    scrollFrame = 0;
    scrollListeners?.abort();
    for (const restore of restoreSnapping) restore();
    restoreSnapping = [];
  }

  const reducesMotion = () => root.dataset.weibeiReduceMotion === 'true'
    || (root.dataset.weibeiReduceMotion === undefined && systemReduced.matches);

  function scrollIntoView(element, { duration, easing, viewportOffsetY = 0, onFinish, ...options } = {}) {
    if (!element) { cancelScroll(); return; }
    const scrollers = new Set([document.scrollingElement || root]);
    for (let parent = element.parentElement; parent; parent = parent.parentElement) {
      if (parent.scrollHeight > parent.clientHeight || parent.scrollWidth > parent.clientWidth) {
        scrollers.add(parent);
      }
    }
    // The browser resolves nested alignment, scroll margins and clamping.
    animateScroll(scrollers, () => {
      element.scrollIntoView({ ...options, behavior: 'instant' });
      if (viewportOffsetY) window.scrollBy({ top: viewportOffsetY, behavior: 'instant' });
    }, { duration, easing, onFinish });
  }

  function scrollToTop(scroller, { onFinish } = {}) {
    if (!scroller) { cancelScroll(); return; }
    animateScroll([scroller], () => scroller.scrollTo({ top: 0, behavior: 'instant' }), { onFinish });
  }

  function animateScroll(scrollers, land, { duration = 'md-exit', easing, onFinish }) {
    cancelScroll();
    const landImmediately = () => {
      cancelScroll();
      land();
      onFinish?.();
    };
    if (reducesMotion()) { landImmediately(); return; }

    // Record the destination and restore the start before a frame is painted.
    const positions = [...scrollers].map(scroller => ({
      scroller, x: scroller.scrollLeft, y: scroller.scrollTop,
    }));
    land();
    const moving = positions.flatMap(({ scroller, x, y }) => {
      const dx = scroller.scrollLeft - x;
      const dy = scroller.scrollTop - y;
      if (dx === 0 && dy === 0) return [];
      // Resolve the destination with scroll snap on, then keep the intermediate
      // offsets free of snap until the user or the last frame takes over.
      if (getComputedStyle(scroller).scrollSnapType !== 'none') {
        const previous = scroller.style.getPropertyValue('scroll-snap-type');
        const priority = scroller.style.getPropertyPriority('scroll-snap-type');
        scroller.style.setProperty('scroll-snap-type', 'none', 'important');
        restoreSnapping.push(() => scroller.style.setProperty('scroll-snap-type', previous, priority));
      }
      scroller.scrollTo({ left: x, top: y, behavior: 'instant' });
      return [{ scroller, x, y, dx, dy }];
    });
    if (!moving.length) { onFinish?.(); return; }

    const styles = getComputedStyle(root);
    const time = typeof duration === 'number' ? duration : parseFloat(styles.getPropertyValue('--duration-' + duration));
    const points = (easing ?? styles.getPropertyValue('--ease-in-out')).match(/-?(?:\d*\.)?\d+/g)?.map(Number);
    if (!time || points?.length !== 4) { landImmediately(); return; }
    const [x1, y1, x2, y2] = points;
    const component = (a, b, t) => 3 * (1 - t) ** 2 * t * a + 3 * (1 - t) * t ** 2 * b + t ** 3;
    const ease = timeProgress => {
      if (timeProgress >= 1) return 1;
      let low = 0;
      let high = 1;
      for (let i = 0; i < 12; i++) {
        const mid = (low + high) / 2;
        if (component(x1, x2, mid) < timeProgress) low = mid;
        else high = mid;
      }
      return component(y1, y2, (low + high) / 2);
    };

    scrollListeners = new AbortController();
    const listener = { capture: true, passive: true, signal: scrollListeners.signal };
    for (const input of ['wheel', 'touchstart', 'pointerdown', 'keydown', 'popstate', 'pagehide']) {
      window.addEventListener(input, cancelScroll, listener);
    }
    systemReduced.addEventListener('change', () => {
      if (reducesMotion()) landImmediately();
    }, { signal: scrollListeners.signal });
    const start = performance.now();
    const step = now => {
      if (reducesMotion()) { landImmediately(); return; }
      const fraction = Math.min((now - start) / time, 1);
      const progress = ease(fraction);
      for (const { scroller, x, y, dx, dy } of moving) {
        scroller.scrollTo({ left: x + dx * progress, top: y + dy * progress, behavior: 'instant' });
      }
      if (fraction < 1) {
        scrollFrame = requestAnimationFrame(step);
      } else {
        cancelScroll();
        onFinish?.();
      }
    };
    scrollFrame = requestAnimationFrame(step);
  }

  window.WeiBeiMotion = { scrollIntoView, scrollToTop };
})();
