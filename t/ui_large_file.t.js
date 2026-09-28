#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The report shows a license's matches inline, and the file browser pages through files of any size in
// windows, like GitHub's blob view. The "large_file" fixture (one package, id 1) has the browser budget
// lowered to 2000 bytes (about 43 lines); hidden-match.txt has an MIT match on line 1 and another on line
// 82, past the first window.
t.test('Cavil UI - large file windows', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'large_file';
  const ui = await launchUi('js_ui_large_file');
  const {page, url, errorLogs} = ui;

  try {
    let fileUrl;

    await t.test('plain users follow line numbers into the file browser', async t => {
      await page.goto(`${url}/login_as_uploader`);
      await page.goto(`${url}/reviews/details/1`);
      await page.locator('.file-link', {hasText: 'hidden-match.txt'}).click();
      await page.waitForSelector('.report-match-panel table.snippet');
      t.equal(
        await page.locator('.report-match-panel td.code', {hasText: 'license marker'}).count(),
        2,
        'both MIT matches are shown'
      );
      const viewUrl = await page
        .locator('.report-file-actions .dropdown-item', {hasText: 'View file'})
        .getAttribute('href');
      t.match(viewUrl, /\/reviews\/file_view\/1\/.*hidden-match\.txt#L1$/, 'View file opens at the first match');
      fileUrl = viewUrl.replace(/#L1$/, '');
      t.equal(
        await page.locator('.report-match-panel td.linenumber a').first().getAttribute('href'),
        `${fileUrl}#L1`,
        'line numbers link to that line'
      );
    });

    await t.test('the first window warns about the match below', async t => {
      await page.goto(`${url}${fileUrl}`);
      await page.waitForSelector('.file-browser-source .snippet');

      const shown = await page.locator('.file-browser-source td.linenumber').count();
      t.ok(shown > 0 && shown < 151, `only a window of the file is shown (${shown} lines)`);
      t.equal(await page.locator('.source-window').count(), 1, 'there is nothing before the first window');
      t.match(await page.innerText('.source-window.has-matches'), /Show next lines · 1 match below/, 'it counts');

      await page.click('.source-window button');
      await page.waitForSelector('.source-window:has-text("Show previous lines · 1 match above")');
      t.ok(Number(await page.locator('td.linenumber').first().innerText()) > 1, 'the next window starts later');
    });

    await t.test('a deep link past the first window highlights its line', async t => {
      await page.goto(`${url}${fileUrl}#L82`);
      await page.waitForSelector('tr.line-target');
      t.equal(await page.innerText('tr.line-target td.linenumber'), '82', 'line 82 is highlighted');
      t.match(await page.innerText('tr.line-target'), /large file lab license marker/, 'it is the match');

      await page.click('button:has-text("Show previous lines")');
      await page.waitForFunction(() => document.querySelector('td.linenumber')?.innerText === '1');
      t.pass('Show previous pages back to the top');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
