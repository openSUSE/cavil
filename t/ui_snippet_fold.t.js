#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// A folded snippet is one that the similarity scorer resolved to a license without a human writing
// a pattern. In the report it must behave like any other resolved license: it appears in the risk
// list, and opening its file shows the folded region highlighted as that license (not as a black
// "unresolved snippet" row). The synthetic "snippet_fold" fixture folds every snippet of the
// package-with-snippets report into GPL (risk 5).
t.test('Cavil UI - snippet fold-in', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'snippet_fold';
  const ui = await launchUi('js_ui_snippet_fold');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('folded snippet is listed under its license and highlighted in the source', async t => {
      await page.goto(`${url}/reviews/details/1`);
      await page.waitForSelector('#license-chart');

      // GPL (risk 5) is present only because the snippets folded into it
      const gpl = page.locator('#risk-5 > li').filter({hasText: 'GPL'}).first();
      await gpl.waitFor();
      t.ok(await gpl.count(), 'folded GPL license appears in the risk-5 bucket');

      // Expand the license and open its file
      await gpl.locator('a[data-bs-toggle="collapse"]').click();
      const fileLink = gpl.locator('a.file-link[href^="#file-"]').first();
      await fileLink.waitFor();
      const fileId = (await fileLink.getAttribute('href')).replace('#file-', '');

      await fileLink.click();
      await page.waitForSelector(`#file-details-${fileId} table.snippet`);

      // The folded region renders as a license match (risk-5), not as an unresolved snippet (risk-9)
      const details = page.locator(`#file-details-${fileId}`);
      await details.locator('tr.risk-5').first().waitFor();
      t.ok(await details.locator('tr.risk-5').count(), 'folded region is highlighted as the license');
      t.equal(await details.locator('tr.risk-9').count(), 0, 'folded region is not shown as an unresolved snippet');
    });

    await t.test('folded snippet is also highlighted in the file browser', async t => {
      await page.goto(`${url}/reviews/file_view/1/README`);
      const src = page.locator('.file-browser-source');
      await src.locator('table.snippet').waitFor();
      await src.locator('tr.risk-5').first().waitFor();
      t.ok(await src.locator('tr.risk-5').count(), 'folded region shown as the license in the file browser');
      t.equal(await src.locator('tr.risk-9').count(), 0, 'not shown as an unresolved snippet in the file browser');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});

// Boilerplate clearing resolves recognized license body text WITHOUT asserting a license: the
// snippets drop out of the unresolved list and nothing new appears in the license list. The
// "snippet_clear" fixture makes every snippet a zero-margin match of a synthetic "Clear-Test"
// license, so it can only clear (never fold) and its name must never show up.
t.test('Cavil UI - snippet boilerplate-clear', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'snippet_clear';
  const ui = await launchUi('js_ui_snippet_clear');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('cleared snippets leave no unresolved matches and assert no license', async t => {
      await page.goto(`${url}/reviews/details/1`);
      await page.waitForSelector('#license-chart');

      t.equal(await page.locator('#unmatched-files').count(), 0, 'no unresolved-matches section remains');
      t.equal(await page.locator('text=Clear-Test').count(), 0, 'clearing did not assert a license');
    });

    await t.test('file browser shows the cleared region as resolved, not unresolved', async t => {
      await page.goto(`${url}/reviews/file_view/1/README`);
      const src = page.locator('.file-browser-source');
      await src.locator('table.snippet').waitFor();
      t.equal(await src.locator('tr.risk-9').count(), 0, 'no unresolved (risk 9) lines after clearing');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
