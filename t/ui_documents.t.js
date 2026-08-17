#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Derived documents are generated on demand, so the report page has to walk the
// reviewer through it: offer to build them, animate while the job runs, then
// hand over the downloads. This drives that row the way a reviewer does,
// clicking the button once and letting the component's own poll notice the
// finished job - the page is never reloaded in between.
t.test('Cavil UI - report documents', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_documents');
  const {context, page, url, performJobs, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Report page generates its documents on demand', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const row = page.locator('#report-documents');
      const control = row.locator('.report-documents-control');
      await control.waitFor();
      t.match(await control.innerText(), /^Generate$/, 'nothing built yet, so the row offers to build');
      t.equal(await row.locator('a[download]').count(), 0, 'nothing to download yet');

      await control.click();

      // The POST answers with the new state, so the spinner is up before the
      // job has even been picked up by a worker. It is the same control
      // throughout, only its glyph and label change.
      await row.locator('.report-documents-control i.fa-spin').waitFor();
      t.match(await control.innerText(), /^Generating$/, 'the control spins while the job is queued');
      t.equal(await control.getAttribute('aria-busy'), 'true', 'the control reports itself busy');
      t.ok(await row.locator('button.report-documents-control').isDisabled(), 'it cannot be clicked again');

      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();

      // No reload here: the component polls the report state endpoint and
      // swaps itself over to the download on its own
      // One click produced every registered document, and each is offered on its own
      const links = row.locator('a[download]');
      await links.first().waitFor({timeout: 60000});
      await links.nth(1).waitFor();
      t.same(
        await links.evaluateAll(nodes => nodes.map(n => [n.getAttribute('href'), n.getAttribute('download')])),
        [
          ['/documents/1/spdx', '1.spdx.json'],
          ['/documents/1/notice', '1.NOTICE.txt']
        ],
        'both documents are linked and named for a download'
      );
      t.equal(await links.first().innerText(), '1.spdx.json', 'the link is labelled with the file name');
      t.match(
        await row.locator('.report-documents-size').first().innerText(),
        /^[\d.]+\s?\w+$/,
        'the size of the downloaded file is shown beside it'
      );
      t.equal(await row.locator('i.fa-spin').count(), 0, 'the spinner is gone');

      // And it survives a reload, because the state comes down with the rest
      // of the report metadata
      await page.reload();
      await page.waitForSelector('#license-chart');
      await row.locator('a[download]').first().waitFor();
      t.equal(await row.locator('a[download]').count(), 2, 'both downloads are there after a reload');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
