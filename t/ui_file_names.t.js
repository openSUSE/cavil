#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// File names reach the frontend as the filesystem's bytes. In the "file_names" fixture package 1 has "Lizenzä.txt"
// and "altä.txt" (Latin-1 on disk, not UTF-8) with an MIT match each, and "Notizen-ü.txt" with nothing matched.
// Package 2 is a Gitea repository just created, holding only Gitea's .gitignore and .gitattributes.
t.test('Cavil UI - file names', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'file_names';
  const ui = await launchUi('js_ui_file_names');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('the report shows names as people wrote them and links them', async t => {
      await page.goto(`${url}/reviews/details/1`);
      await page.waitForSelector('.file-link');
      const names = await page.locator('.risk-license-section .file-link').allInnerTexts();
      t.same(names.map(name => name.trim()).sort(), ['Lizenzä.txt', 'altä.txt'], 'decoded, Latin-1 shown as is');

      await page.locator('.file-link', {hasText: 'Lizenzä.txt'}).click();
      await page.waitForSelector('.report-match-panel table.snippet');
      const viewUrl = await page
        .locator('.report-file-actions .dropdown-item', {hasText: 'View file'})
        .getAttribute('href');
      t.match(viewUrl, /\/reviews\/file_view\/1\/Lizenz%C3%A4\.txt#L1$/, 'linked by its bytes');
      await page.goto(`${url}${viewUrl}`);
      await page.waitForSelector('.file-browser-source .snippet');
      t.match(await page.title(), /Content of Lizenzä\.txt/, 'the browser opens it');
      t.match(await page.innerText('.file-browser-breadcrumb'), /Lizenzä\.txt/, 'and names it readably');
    });

    await t.test('the file browser opens a name that is not UTF-8 and goes back', async t => {
      await page.goto(`${url}/reviews/file_view/1/`);
      await page.waitForSelector('.file-browser-name a');
      t.same(
        await page.locator('.file-browser-name a').allInnerTexts(),
        ['altä.txt', 'Lizenzä.txt', 'Notizen-ü.txt'],
        'every entry readable'
      );

      await page.locator('.file-browser-name a', {hasText: 'altä.txt'}).click();
      await page.waitForSelector('.file-browser-source .snippet');
      t.match(page.url(), /\/reviews\/file_view\/1\/alt%E4\.txt$/, 'its bytes are in the address bar');

      await page.goBack();
      await page.waitForSelector('.file-browser-name a');
      t.equal(await page.locator('.file-browser-name a').count(), 3, 'back at the listing');
      await page.goForward();
      await page.waitForSelector('.file-browser-source .snippet');
      t.match(await page.innerText('.file-browser-breadcrumb'), /altä\.txt/, 'and forward to the file again');
    });

    await t.test('the empty report of a near-empty checkout lists what it contains', async t => {
      await page.goto(`${url}/reviews/details/2`);
      await page.waitForSelector('[data-empty-report-notice]');
      t.match(
        await page.innerText('[data-empty-report-notice]'),
        /The checkout only contains these files:/,
        'it says the list is everything'
      );
      const links = page.locator('[data-empty-report-notice] a.checkout-file');
      t.same(await links.allInnerTexts(), ['.gitattributes', '.gitignore'], 'both files are listed');
      t.equal(await links.first().getAttribute('href'), '/reviews/file_view/2/.gitattributes', 'linked to the browser');
    });

    await t.test('the file browser shows its dotfiles', async t => {
      await page.goto(`${url}/reviews/file_view/2/`);
      await page.waitForSelector('.file-browser-name a');
      t.same(await page.locator('.file-browser-name a').allInnerTexts(), ['.gitattributes', '.gitignore'], 'both');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    await ui.teardown();
  }
});
