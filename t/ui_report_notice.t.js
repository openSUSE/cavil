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
// brand-new unresolved files and one brand-new Apache-2.0 license.
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
      const box = await page.innerText('#review-information');
      t.match(box, /New unresolved matches in 8 files/, 'box shows the full count of new unresolved files');
      t.equal(await page.locator('#review-information a').count(), 0, 'box has no links (plain-text summary)');
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

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
