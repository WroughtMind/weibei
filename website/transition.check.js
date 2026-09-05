// playwright-cli run-code "$(cat website/transition.check.js)"
async (page) => {
  await page.setViewportSize({ width: 1470, height: 876 });
  const origin = page.url().split('/').slice(0, 3).join('/');
  await page.goto(`${origin}/index.html?motion-check=${Date.now()}`);
  await page.mouse.move(10, 400);
  const seek = async progress => {
    await page.evaluate(p => scrollTo({ top: (document.documentElement.scrollHeight - innerHeight) * p, behavior: 'instant' }), progress);
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  };
  await seek(.7);
  await page.waitForFunction(() => document.documentElement.dataset.scene === '3');
  const intercepted = await page.locator('.download-control').evaluate(el => {
    const b = el.getBoundingClientRect();
    return !!document.elementFromPoint(b.x + b.width / 2, b.y + b.height / 2)?.closest('.release-layer');
  });
  const widths = [];
  for (let p = .82; p <= .951; p += .005) {
    await seek(p);
    widths.push(await page.locator('.release-map-paper').evaluate(el => el.getBoundingClientRect().width));
  }
  const increments = widths.slice(1).map((width, index) => width - widths[index]);
  const reverses = increments.some(delta => delta < -1);
  const cliff = increments.some((delta, index) => index && increments[index - 1] > 30 && delta < increments[index - 1] * .3);
  const failures = [];
  if (intercepted) failures.push('Invisible download control intercepts theme hover');
  if (reverses) failures.push('Paper reverses size while scrolling forward');
  if (cliff) failures.push('Paper expansion speed drops abruptly');
  if (failures.length) throw new Error(JSON.stringify({ failures, increments }));
  for (let cycle = 0; cycle < 6; cycle++) {
    await seek(.7);
    await page.waitForFunction(() => document.documentElement.dataset.scene === '3');
    if (await page.locator('html').getAttribute('data-theme')) throw new Error('Scrolling under stationary mouse expanded a theme');
    await page.mouse.move(600 + cycle, 680);
    await page.waitForFunction(() => !!document.documentElement.dataset.theme);
    await seek(.96);
    await page.waitForFunction(() => document.documentElement.dataset.scene === '4');
    if (await page.locator('html').getAttribute('data-theme')) throw new Error('Theme stays active in scene four');
  }
  await page.locator('[data-download-toggle]').click();
  if (await page.locator('[data-download-menu]').isHidden()) throw new Error('Visible download menu cannot open');
  await page.keyboard.press('Escape');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.locator('#scene-3').evaluate(el => el.scrollIntoView({ behavior: 'instant' }));
  await page.waitForFunction(() => document.documentElement.dataset.scene === '3');
  await page.locator('.theme-paper').click();
  await page.waitForFunction(() => document.documentElement.dataset.theme === 'paper-ink');
  return { hiddenHitArea: 'passed', monotonicExpansion: 'passed', smoothDeceleration: 'passed', hoverRoundTrips: 6, mobileSelection: 'passed' };
}
