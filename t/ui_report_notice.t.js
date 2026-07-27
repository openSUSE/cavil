#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The "why this needs review" box summarizes the diff against the closest
// previous review as plain text (including a count of new unresolved matches).
// The individual new files are flagged with a "new" badge in the Risk 9
// unresolved-matches section, driven by the structured diff report stored at
// analyze time - complete coverage, alongside each file's similarity and
// estimated risk. New licenses get the same badge in their risk bucket. The
// "report_notice" fixture builds two synthetic versions of one package through
// the real pipeline: version 1 is accepted, version 2 (id 2) adds eight
// brand-new unresolved files and one brand-new Apache-2.0 license. A second
// package (ids 3 and 4) covers the zero-delta notice.
t.test('Cavil UI - new unresolved matches badges', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'report_notice';
  const ui = await launchUi('js_ui_report_notice');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');
    await page.goto(`${url}/reviews/details/2`);
    await page.waitForSelector('#review-information');

    await t.test('box summarizes the diff as plain text, with no file links', async t => {
      // Only the compared report id is a link; the individual files are not

      const box = await page.innerText('#review-information');
      t.match(box, /New unresolved matches in 8 files/, 'box shows the full count of new unresolved files');
      t.equal(await page.locator('#review-information a').count(), 1, 'box links nothing but the compared report');
    });

    await t.test('the compared report id is a link that opens in a new tab', async t => {
      const box = await page.innerText('#review-information');
      t.match(box, /Diff to closest match 1/, 'box names the closest match');

      const link = page.locator('#review-information a');
      t.equal((await link.innerText()).trim(), '1', 'the package id itself is the link');
      t.equal(await link.getAttribute('href'), '/reviews/details/1', 'link points at the compared report');
      t.equal(await link.getAttribute('target'), '_blank', 'link opens in another tab');

      const [popup] = await Promise.all([page.waitForEvent('popup'), link.click()]);
      await popup.waitForSelector('.report-metadata-name');
      t.match(popup.url(), /\/reviews\/details\/1$/, 'the new tab shows the compared report');
      t.match(await popup.innerText('.report-metadata-name'), /report-notice/, 'it is a real report page');
      await popup.close();
    });

    await t.test('every new unresolved file is badged in the Risk 9 section', async t => {
      await page.waitForSelector('#filelist-snippets .risk-new');
      const rows = page.locator('#filelist-snippets .risk-unresolved-item');
      const badges = page.locator('#filelist-snippets .risk-new');
      t.equal(await rows.count(), 8, 'all eight unresolved files are listed');
      t.equal(await badges.count(), 8, 'all eight are badged "new" (complete coverage, no cap)');
      t.equal((await badges.first().innerText()).trim().toLowerCase(), 'new', 'badge reads "new"');

      // The badge sits alongside the similarity + estimated-risk already shown
      const firstRow = rows.first();
      t.ok(await firstRow.locator('.risk-unresolved-match').count(), 'row still shows similarity');
      t.ok(await firstRow.locator('.risk-unresolved-estimate').count(), 'row still shows estimated risk');
    });

    await t.test('a new license is badged in its risk bucket', async t => {
      const apacheRow = page
        .locator('.risk-license-item')
        .filter({has: page.locator('.risk-license-name', {hasText: 'Apache-2.0'})});
      await apacheRow.first().waitFor();
      t.equal(await apacheRow.locator('.risk-new').count(), 1, 'the brand-new Apache-2.0 license is badged "new"');
    });

    // The other notice shape that names an older review by id
    await t.test('the "no significant difference" notice links its id too', async t => {
      await page.goto(`${url}/reviews/details/4`);
      await page.waitForSelector('#review-information');

      const box = await page.innerText('#review-information');
      t.match(box, /Not found any significant difference against 3/, 'box names the review it matched');

      const link = page.locator('#review-information a');
      t.equal(await link.count(), 1, 'the id is the only link');
      t.equal((await link.innerText()).trim(), '3', 'the package id itself is the link');
      t.equal(await link.getAttribute('href'), '/reviews/details/3', 'link points at the matched report');
      t.equal(await link.getAttribute('target'), '_blank', 'link opens in another tab');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
