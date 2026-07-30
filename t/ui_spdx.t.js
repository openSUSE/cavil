#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// SPDX reports are generated on demand (always_generate_spdx_reports is off),
// so the report page has to walk the reviewer through it: offer to build one,
// animate while the job runs, then hand over a download. This drives that row
// the way a reviewer does, clicking the button and letting the component's own
// poll notice the finished job - the page is never reloaded in between.
t.test('Cavil UI - SPDX download', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_spdx');
  const {context, page, url, performJobs, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Report page generates an SPDX report on demand', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const row = page.locator('#spdx-report');
      const control = row.locator('.spdx-download-control');
      await control.waitFor();
      t.match(await control.innerText(), /^Generate$/, 'no report yet, so the row offers to build one');
      t.equal(await row.locator('a[download]').count(), 0, 'nothing to download yet');

      await control.click();

      // The POST answers with the new state, so the spinner is up before the
      // job has even been picked up by a worker. It is the same control
      // throughout, only its glyph and label change.
      await row.locator('.spdx-download-control i.fa-spin').waitFor();
      t.match(await control.innerText(), /^Generating$/, 'the control spins while the job is queued');
      t.equal(await control.getAttribute('aria-busy'), 'true', 'the control reports itself busy');
      t.ok(await row.locator('button.spdx-download-control').isDisabled(), 'it cannot be clicked again');

      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();

      // No reload here: the component polls the report state endpoint and
      // swaps itself over to the download on its own
      const link = row.locator('a[download]');
      await link.waitFor({timeout: 60000});
      t.equal(await link.getAttribute('href'), '/spdx/1', 'download points at the report');
      t.equal(await link.getAttribute('download'), '1.spdx.json', 'saved under the package id');
      t.equal(await link.innerText(), '1.spdx.json', 'the link is labelled with the file name');
      t.match(
        await row.locator('.spdx-download-size').innerText(),
        /^[\d.]+\s?\w+$/,
        'the size of the downloaded file is shown beside it'
      );
      t.equal(await row.locator('i.fa-spin').count(), 0, 'the spinner is gone');

      // And it survives a reload, because the state comes down with the rest
      // of the report metadata
      await page.reload();
      await page.waitForSelector('#license-chart');
      await row.locator('a[download]').waitFor();
      t.equal(await row.locator('a[download]').innerText(), '1.spdx.json', 'the download is there after a reload');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
