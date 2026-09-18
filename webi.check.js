// Run with playwright-cli run-code "$(cat website/webi.check.js)" after opening the local site.
async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/');
  const check = (condition, message) => { if (!condition) throw new Error(message); };
  await page.goto(`${origin}/webi.html`);
  for (const width of [390, 1280]) {
    await page.setViewportSize({ width, height: 844 });
    check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Gallery overflows the viewport');
    check(await page.locator('[data-artwork]').count() > 0, 'Collection is empty');
  }
  await page.locator('[data-animated="true"]').first().click();
  await page.locator('dialog[open]').waitFor();
  await page.locator('.webi-full').evaluate(image => image.decode());
  check(await page.locator('.webi-full').evaluate(image => image.naturalWidth > 0), 'Animation did not load');
  await page.locator('.webi-close').click();
  await page.locator('.webi-full:not([src])').waitFor({ state: 'attached' });
  check(await page.locator('dialog[open]').count() === 0, 'Preview did not close');
  check(await page.locator('.webi-full').getAttribute('src') === null, 'Animation remains loaded after closing');
  await page.locator('#comics [data-artwork]').first().click();
  await page.locator('.webi-full').evaluate(image => image.decode());
  await page.keyboard.press('Escape');
  check(await page.locator('dialog[open]').count() === 0, 'Escape did not close preview');
  await page.locator('[data-language-toggle]').click();
  check(await page.locator('html').getAttribute('lang') === 'en', 'Language did not change');
  check(!/[\u4e00-\u9fff]/.test(await page.locator('main').innerText()), 'Untranslated gallery text');
  for (const name of ['index.html#scene-4', 'qa.html', 'labs.html', 'feedback.html']) {
    await page.goto(`${origin}/${name}`);
    check(await page.locator('.release-nav a[href="webi.html"]').count() === 1, 'Missing shared Webi entry');
    if (name.startsWith('index')) {
      await page.locator('.release-webi').click();
      check(page.url().endsWith('/webi.html'), 'Fold-map entry does not open Webi');
    }
  }
  await page.goto(`${origin}/webi.html`);
  await page.locator('[data-language-toggle]').click();
  console.log('Webi gallery: responsive layout, previews, language and all entries passed.');
}
