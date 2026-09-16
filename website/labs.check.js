// Run with playwright-cli run-code "$(cat website/labs.check.js)" on the locally served site.
async (page) => {
  const origin = await page.evaluate(() => location.origin);
  const check = (condition, message) => { if (!condition) throw new Error(message); };
  for (const route of ['labs.html', 'en/labs.html']) {
    await page.goto(`${origin}/${route}`);
    const imageLanguage = route.startsWith('en/') ? 'en' : 'zh';
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
        const image = await preview.locator('img').evaluate(image => ({ src: image.currentSrc, srcset: image.srcset }));
        check(image.src.includes(`/labs/${imageLanguage}/`), 'Preview image has the wrong language');
        check(image.srcset.split(',').every(source => source.includes(`/labs/${imageLanguage}/`)), 'Responsive image has the wrong language');
      }
    }
    for (const preview of await previews.all()) {
      const destination = await preview.evaluate(link => link.href);
      check(destination.includes(`/labs/${imageLanguage}/`), 'Full-size image has the wrong language');
      const [popup] = await Promise.all([page.waitForEvent('popup'), preview.click()]);
      await popup.waitForLoadState('load');
      check(decodeURI(popup.url()) === decodeURI(destination), 'Wrong full-size image');
      await popup.locator('img').evaluate(image => image.decode());
      await popup.close();
    }
  }
  // Fresh contexts prove mobile requests the smaller image instead of a previously cached desktop image.
  for (const language of ['zh', 'en']) {
    const context = await page.context().browser().newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
    try {
      const mobile = await context.newPage();
      const requests = [];
      mobile.on('request', request => { if (request.url().includes('/assets/labs/')) requests.push(request.url()); });
      await mobile.goto(`${origin}/${language === 'en' ? 'en/' : ''}labs.html`);
      for (const image of await mobile.locator('.lab-preview img').all()) {
        await image.scrollIntoViewIfNeeded();
        await image.evaluate(image => image.decode());
        check((await image.evaluate(image => image.currentSrc)).endsWith('-768.webp'), 'Mobile did not select the compressed 768px image');
      }
      check(requests.length === 3 && requests.every(url => url.includes(`/labs/${language}/`) && url.endsWith('-768.webp')), 'Mobile loaded extra or wrong-language images');
    } finally {
      await context.close();
    }
  }
  for (const language of ['zh-CN', 'en', 'zh-CN']) {
    await page.locator('[data-language-toggle]').click();
    check(await page.locator('html').getAttribute('lang') === language, 'Language switch failed');
    const imageLanguage = language === 'en' ? 'en' : 'zh';
    for (const image of await page.locator('.lab-preview img').all()) {
      await image.scrollIntoViewIfNeeded();
      await image.evaluate(image => image.decode());
      check((await image.evaluate(image => image.currentSrc)).includes(`/labs/${imageLanguage}/`), 'Language switch retained the previous image');
    }
  }
  await page.locator('main a[href="feedback.html"]').click();
  check(page.url().endsWith('/feedback.html'), 'Feedback link failed');
  return 'PASS: bilingual images and full-size links, responsive layouts, mobile-only 768px requests, language and feedback navigation';
}
