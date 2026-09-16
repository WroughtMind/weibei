// Run with playwright-cli run-code "$(cat website/labs.check.js)" on the locally served site.
async (page) => {
  const origin = await page.evaluate(() => location.origin);
  const check = (condition, message) => { if (!condition) throw new Error(message); };
  for (const route of ['labs.html', 'en/labs.html']) {
    await page.goto(`${origin}/${route}`);
    const previews = page.locator('.lab-preview');
    check(await previews.count() === 3, 'Missing project preview');
    for (const width of [1440, 768, 390, 320]) {
      await page.setViewportSize({ width, height: 900 });
      await page.evaluate(() => document.fonts.ready);
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${route} overflows at ${width}px`);
      for (const preview of await previews.all()) {
        await preview.scrollIntoViewIfNeeded();
        await preview.locator('img').evaluate(image => image.decode());
        check(await preview.locator('img').evaluate(image => image.naturalWidth > 0 && image.alt.length > 0), 'Broken or undescribed image');
      }
    }
    for (const preview of await previews.all()) {
      const destination = await preview.evaluate(link => link.href);
      const [popup] = await Promise.all([page.waitForEvent('popup'), preview.click()]);
      await popup.waitForLoadState('load');
      check(decodeURI(popup.url()) === decodeURI(destination), 'Wrong full-size image');
      await popup.locator('img').evaluate(image => image.decode());
      await popup.close();
    }
  }
  await page.locator('[data-language-toggle]').click();
  check(await page.locator('html').getAttribute('lang') === 'zh-CN', 'Language switch failed');
  await page.locator('main a[href="feedback.html"]').click();
  check(page.url().endsWith('/feedback.html'), 'Feedback link failed');
  return 'PASS: bilingual layouts, all images, full-size previews, language and feedback navigation';
}
