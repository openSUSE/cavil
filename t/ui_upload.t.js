#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// End-to-end flow for the redesigned (Vue) archive upload page. An admin picks
// a single archive, the name is prefilled from the filename, and one button
// uploads it with a progress bar - no package metadata is required. After the
// jobs run, the resulting report is reachable and shows the derived version.
const ARCHIVE = 't/legal-bot/perl-Mojolicious/c7cfdab0e71b0bebfdf8b2dc3badfecd/Mojolicious-7.25.tar.gz';

t.test('Cavil UI - tarball upload', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_upload');
  const {page, context, url, performJobs, errorLogs} = ui;

  try {
    // Establish the admin session (dummy auth picks up 'tester' on first login).
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Upload page renders the drop zone', async t => {
      await page.goto(`${url}/upload`);
      t.equal(await page.innerText('title'), 'Upload archive');
      await page.waitForSelector('.upload-dropzone');
      t.equal(await page.locator('#upload-button').isDisabled(), true, 'upload disabled until a file is chosen');
    });

    await t.test('Selecting an archive prefills the name from the filename', async t => {
      await page.setInputFiles('#upload input[name="tarball"]', ARCHIVE);
      await page.waitForSelector('#selected-file');
      t.match(await page.innerText('#selected-file'), /Mojolicious-7\.25\.tar\.gz/, 'selected file is shown');
      t.equal(await page.inputValue('#upload-name'), 'Mojolicious', 'name prefilled with the version stripped');
      t.equal(await page.locator('#upload-button').isDisabled(), false, 'upload enabled once a file is chosen');
    });

    await t.test('Uploading processes the archive and produces a report', async t => {
      await Promise.all([page.waitForURL(/\/reviews\/details\/\d+$/), page.locator('#upload-button').click()]);
      const id = page.url().match(/\/reviews\/details\/(\d+)$/)[1];
      t.ok(id, 'redirected to the new report');

      // Run unpack -> index -> analyze for the freshly uploaded package.
      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();

      await page.goto(`${url}/reviews/details/${id}`);
      t.equal(await page.innerText('title'), 'Report for Mojolicious', 'report title uses the derived name');

      // The report was generated from the unpacked files (no user-supplied metadata)
      await page.waitForSelector('#license-chart');
      t.ok(await page.locator('#checkout-url a').count(), 'checkout link is shown');

      // Licenses are detected from the archive contents, e.g. Apache-2.0 at risk 5
      await page.waitForSelector('#risk-5');
      t.match(await page.innerText('#risk-5'), /Apache-2\.0/, 'detected Apache-2.0 listed under risk 5');

      // Keyword matches that could not be resolved are surfaced for manual review
      await page.waitForSelector('#unmatched-files');
      t.match(await page.innerText('#unmatched-files'), /unresolved match/, 'unresolved matches are reported');
      t.ok(await page.locator('.risk-unresolved-item').count(), 'at least one unresolved match is listed');

      // No declared license metadata, so the package needs manual review
      t.match(await page.innerText('body'), /Manual review is required/, 'manual review notice is shown');
    });

    t.test('Console errors', t => {
      // Landing on the report immediately after upload polls once while the package is
      // still being processed, which the browser logs as an expected 408.
      const filtered = errorLogs.filter(msg => !/status of 408/.test(msg));
      assertNoUnexpectedConsoleErrors(t, filtered);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
