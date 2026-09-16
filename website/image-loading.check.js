// Run with playwright-cli run-code "$(cat website/image-loading.check.js)" on a served build.
async (entryPage) => {
  const base = new URL('./', entryPage.url());
  const check = (ok, message) => { if (!ok) throw new Error(message); };
  for (const route of ['', 'en/']) {
    for (const width of [1440, 390]) {
      const page = await entryPage.context().browser().newPage({ viewport: { width, height: 900 }, deviceScaleFactor: 2 });
      await page.goto(new URL(route, base).href);
      await page.waitForLoadState('networkidle');
      check(await page.locator('img[data-image-scene="3"], img[data-image-scene="4"]').evaluateAll(images =>
        images.length > 0 && images.every(img => !img.hasAttribute('src') && !img.hasAttribute('srcset'))),
      'Later scenes downloaded images on entry');
      if (width === 390) check(!await page.locator('.giant-webi').evaluate(img => img.complete && img.naturalWidth > 0), 'Mobile downloaded hidden desktop decoration');
      for (const scene of [2, 3, 4]) {
        await page.locator(`#scene-${scene}`).evaluate(element => element.scrollIntoView({ behavior: 'instant' }));
        await page.waitForFunction(scene => !document.querySelector(`img[data-image-scene="${scene}"]`), scene);
        const selector = {2: '.experience-layer img, .mascot-two', 3: '.themes-layer img, .theme-world img', 4: '.release-layer img'}[scene];
        await page.locator(selector).evaluateAll(images => Promise.all(images.map(img => img.decode().catch(error => { throw new Error(`${img.currentSrc || img.outerHTML}: ${error.message}`); }))));
        check(await page.locator(selector).evaluateAll(images => images.every(img => img.naturalWidth > 0)), `Scene ${scene} has missing images`);
      }
      await page.goto(new URL(`${route}#scene-3`, base).href);
      await page.waitForFunction(() => !document.querySelector('img[data-image-scene="3"]'));
      await page.locator('.themes-layer img').evaluateAll(images => Promise.all(images.map(img => img.decode().catch(error => { throw new Error(`${img.currentSrc || img.outerHTML}: ${error.message}`); }))));
      await page.close();
    }
  }
  console.log('Image loading: desktop/mobile, both languages, all scenes and direct scene entry passed.');
}
