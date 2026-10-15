#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Derived documents are generated on demand and each on its own, an SBOM can take hours while a dossier takes
// seconds. So every document is a row: clicking it builds it, it spins while the job runs and turns into the download
// when it is ready. This drives those rows the way a reviewer does, letting the component's own poll notice the
// finished jobs - the page is never reloaded in between.
t.test('Cavil UI - report documents', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_documents');
  const {context, page, url, performJobs, errorLogs} = ui;

  const drain = async () => {
    const drainPage = await context.newPage();
    await drainPage.goto(performJobs, {timeout: 120000});
    await drainPage.close();
  };

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Every document is a row of its own', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const row = page.locator('#report-documents');
      await row.locator('.report-documents-control').first().waitFor();
      t.same(
        await row.locator('.report-documents-control').allInnerTexts(),
        ['1.spdx.json', '1.NOTICE.txt', '1.dossier.md'],
        'one control per document, labelled with the file it gets'
      );
      t.equal(await row.locator('a[download]').count(), 0, 'nothing built yet');
      t.equal(
        await row.locator('button i.fa-file-circle-plus').count(),
        3,
        'each says so with its icon, rather than leaving it to the missing size'
      );
      t.equal(await row.locator('.report-documents-note').count(), 0, 'and nothing else');
      t.equal(await row.locator('button.report-documents-control:disabled').count(), 0, 'every one can be asked for');
    });

    await t.test('Asking for the dossier builds the dossier alone', async t => {
      const row = page.locator('#report-documents');
      const dossier = row.locator('button.report-documents-control', {hasText: '1.dossier.md'});
      await dossier.click();

      // The POST answers with the new state, so the spinner is up before a worker has even picked up the job
      await dossier.locator('i.fa-spin').waitFor();
      t.equal(await dossier.getAttribute('aria-busy'), 'true', 'its row reports itself busy');
      t.ok(await dossier.isDisabled(), 'and cannot be clicked again');
      t.equal(await row.locator('i.fa-spin').count(), 1, 'no other row spins');
      t.equal(await row.locator('button i.fa-file-circle-plus').count(), 2, 'its icon is now the spinner');

      await drain();
      const link = row.locator('a[download]');
      await link.first().waitFor({timeout: 60000});
      t.same(
        await link.evaluateAll(nodes => nodes.map(n => [n.getAttribute('href'), n.getAttribute('download')])),
        [['/documents/1/dossier', '1.dossier.md']],
        'it is now a link, and the only one'
      );
      t.match(await row.locator('.report-documents-size').innerText(), /^[\d.]+\s?\w+$/, 'with its size beside it');
      t.equal(await row.locator('button.report-documents-control').count(), 2, 'the others still wait to be asked');
      t.equal(
        await row.locator('a[download] i.fa-file-arrow-down').count(),
        1,
        'the ready one shows the download icon'
      );
      t.equal(await row.locator('button i.fa-file-circle-plus').count(), 2, 'the others still the generate icon');

      const download = page.waitForEvent('download');
      await link.click();
      t.equal((await download).suggestedFilename(), '1.dossier.md', 'and it downloads');
    });

    await t.test('Several documents can be asked for at once', async t => {
      const row = page.locator('#report-documents');
      await row.locator('button.report-documents-control', {hasText: '1.spdx.json'}).click();
      await row.locator('button.report-documents-control', {hasText: '1.NOTICE.txt'}).click();
      await t.resolves(
        page.waitForFunction(() => document.querySelectorAll('#report-documents i.fa-spin').length === 2),
        'both rows spin'
      );

      await drain();
      await page.waitForFunction(() => document.querySelectorAll('#report-documents a[download]').length === 3, null, {
        timeout: 60000
      });
      await t.resolves(
        page.waitForFunction(() => document.querySelectorAll('#report-documents i.fa-spin').length === 0),
        'the spinners are gone'
      );

      // And it survives a reload, because the state comes down with the rest of the report metadata
      await page.reload();
      await page.waitForSelector('#license-chart');
      await row.locator('a[download]').first().waitFor();
      t.equal(await row.locator('a[download]').count(), 3, 'all downloads are there after a reload');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
