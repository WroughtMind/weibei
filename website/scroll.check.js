// playwright-cli run-code "$(cat website/scroll.check.js)" on the local site.
async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/');
  const cdp = await page.context().newCDPSession(page);
  const results = [];
  await page.addInitScript(() => {
    window.foldDecoded = new Set();
    const decode = HTMLImageElement.prototype.decode;
    HTMLImageElement.prototype.decode = async function () {
      await decode.call(this);
      if (this.isConnected && this.closest('.release-layer')) window.foldDecoded.add(this);
    };
  });
  try {
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1470, height: 876, deviceScaleFactor: 2, mobile: false });
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
    for (let run = 0; run < 3; run++) {
      await page.goto(`${origin}/index.html?scroll-check=${Date.now()}`);
      await page.locator('#scene-2').evaluate(el => el.scrollIntoView({ behavior: 'instant' }));
      // Must prepare the actual responsive images in scene two, not detached copies in scene three.
      await page.waitForFunction(() => window.foldDecoded.size === document.querySelectorAll('.release-layer img').length);
      results.push(await page.evaluate(async () => {
        const start = document.querySelector('#scene-3').offsetTop;
        const end = document.documentElement.scrollHeight - innerHeight;
        scrollTo({ top: start, behavior: 'instant' });
        // Begin with scene three displayed, then repeatedly open and close the fold.
        await new Promise(resolve => setTimeout(resolve, 500));
        const intervals = [];
        const slow = [];
        let previous;
        await new Promise(resolve => {
          let frame = 0;
          function step(now) {
            if (previous) { intervals.push(now - previous); if (now - previous > 50) slow.push({ ms: now - previous, progress: scrollY / end }); }
            previous = now;
            const progress = frame <= 150 ? frame / 150 : (300 - frame) / 150;
            scrollTo({ top: start + (end - start) * progress, behavior: 'instant' });
            if (frame++ < 300) requestAnimationFrame(step); else resolve();
          }
          requestAnimationFrame(step);
        });
        return { max: Math.max(...intervals), over50: intervals.filter(ms => ms > 50).length, slow };
      }));
    }
    if (results.some(result => result.max > 100)) throw new Error(`Scroll stalled: ${JSON.stringify(results)}`);
    return { earlyDecode: 'passed', highDpiScroll: results };
  } finally {
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    await cdp.send('Emulation.clearDeviceMetricsOverride');
    await cdp.detach();
  }
}
