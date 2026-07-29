#!/usr/bin/env node
import {
  assertNoUnexpectedConsoleErrors,
  expandFileDetails,
  fillInlinePatternBasics,
  launchUi,
  openCreatePatternEditor,
  skipUnlessOnline,
  waitForInlineSnippetEditorClosed
} from './lib/ui_helpers.js';
import t from 'tap';

// Report header / placeholder behaviour for special package states. The
// wrapper exposes /test/obsolete_with_report, /test/obsolete_without_report,
// /test/empty_report and /test/restore_report_state to flip a package into
// each shape and back; this file walks through all three to ensure the
// right notice panel renders. The reindex subtests at the end run a real
// rebuild of the package one job at a time (via /perform_one_job) and never
// reload the page, because noticing a rebuild and recovering from it without
// a reload is the whole point of them.
t.test('Cavil UI - report states', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_report_states');
  const {context, page, performJobs, url, errorLogs} = ui;

  try {
    // Establish the admin session.
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Report notices cover obsolete, unavailable, and empty reports', async t => {
      await page.goto(`${url}/test/obsolete_with_report/1`);
      t.equal(await page.locator('body').innerText(), 'ok');

      await page.goto(`${url}/reviews/details/1`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('[data-obsolete-report-notice]');
      t.ok(
        await page.locator('[data-obsolete-report-notice]').evaluate(el => el.classList.contains('cavil-notice-panel')),
        'obsolete report notice uses CavilNoticePanel'
      );
      t.match(
        await page.locator('[data-obsolete-report-notice]').innerText(),
        /might not exist anymore/,
        'obsolete report warning is shown while the report still exists'
      );
      await page.waitForSelector('#license-chart');
      t.equal(await page.locator('[data-report-unavailable]').count(), 0, 'obsolete report is not unavailable');
      t.equal(await page.locator('[data-empty-report-notice]').count(), 0, 'obsolete report is not treated as empty');

      await page.goto(`${url}/test/restore_report_state/1`);
      t.equal(await page.locator('body').innerText(), 'ok');

      await page.goto(`${url}/test/obsolete_without_report/2`);
      t.equal(await page.locator('body').innerText(), 'ok');

      await page.goto(`${url}/reviews/details/2`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#report-tabs');
      await page.waitForSelector('[data-report-unavailable]');
      t.equal(
        await page.locator('[data-obsolete-report-notice]').count(),
        0,
        'unavailable notice replaces obsolete warning'
      );
      t.ok(
        await page.locator('[data-report-unavailable]').evaluate(el => el.classList.contains('cavil-notice-panel')),
        'unavailable notice uses CavilNoticePanel'
      );
      t.match(
        await page.locator('[data-report-unavailable]').innerText(),
        /no longer available/,
        'missing obsolete report is terminal instead of a spinner'
      );
      t.equal(await page.locator('#ajax-status').count(), 0, 'report pane is not left polling forever');
      t.equal(
        await page.locator('text=No files matching any known license patterns or keywords have been found.').count(),
        0,
        'missing obsolete report does not show the empty report notice'
      );

      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      t.ok(await page.locator('#report-notes-pane.is-active .report-note').count(), 'notes load for obsolete package');

      await page.goto(`${url}/test/restore_report_state/2`);
      t.equal(await page.locator('body').innerText(), 'ok');

      await page.goto(`${url}/test/empty_report/1`);
      t.equal(await page.locator('body').innerText(), 'ok');

      await page.goto(`${url}/reviews/details/1`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('[data-empty-report-notice]');
      t.ok(
        await page.locator('[data-empty-report-notice]').evaluate(el => el.classList.contains('cavil-notice-panel')),
        'empty report notice uses CavilNoticePanel'
      );
      t.match(
        await page.locator('[data-empty-report-notice]').innerText(),
        /No files matching any known license patterns or keywords have been found/,
        'empty report notice is shown'
      );
      t.equal(await page.locator('[data-obsolete-report-notice]').count(), 0, 'empty report is not obsolete');
      t.equal(await page.locator('[data-report-unavailable]').count(), 0, 'empty report is available');

      await page.goto(`${url}/test/restore_report_state/1`);
      t.equal(await page.locator('body').innerText(), 'ok');
    });

    await t.test('Queued reindex keeps the previous report visible with a stale-report notice', async t => {
      // What lights the Reindex button up in production: somebody creates a license pattern, and every
      // report indexed before it may be missing what that pattern would match.
      const patternPage = await context.newPage();
      await patternPage.goto(`${url}/licenses/new_pattern?license-name=Reindex-Button-Test-1.0`);
      await patternPage.waitForSelector('#edit-pattern .cm-editor');
      await patternPage.evaluate(() => {
        const view = document.querySelector('#edit-pattern .cm-editor').cmView;
        view.dispatch({changes: {from: 0, insert: 'unique-reindex-button-test-pattern-body'}});
      });
      await Promise.all([
        patternPage.waitForURL(/\/licenses\/edit_pattern\/\d+/),
        patternPage.locator('#edit-pattern button[type=submit]').click()
      ]);
      // A new pattern also queues a statistics job, drained here so the single step further down is
      // the rebuild and nothing else.
      await patternPage.goto(performJobs, {timeout: 120000});
      await patternPage.close();

      await page.goto(`${url}/reviews/details/1`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      t.equal(await page.locator('[data-reindexing-notice]').count(), 0, 'no stale-report notice before reindexing');
      await page.locator('#reindex_button.btn-outline-primary').waitFor();
      t.equal(
        await page.getAttribute('#reindex_button', 'title'),
        'There are new patterns!',
        'the Reindex button offers the pattern the report has not seen'
      );

      // Click the real Reindex button, which enqueues an index job (left un-drained here). Because
      // indexing has not actually started, the previous report is still in the database, so the reviewer
      // keeps seeing it - now flagged as being replaced. The marker survives the click if the page was
      // never reloaded on the way there.
      await page.evaluate(() => (window.reindexedWithoutReload = true));
      await Promise.all([
        page.waitForResponse(resp => /reindex/.test(resp.url()) && resp.request().method() === 'POST'),
        page.click('#reindex_button')
      ]);

      await page.waitForSelector('#license-chart');
      t.ok(await page.evaluate(() => window.reindexedWithoutReload), 'the reindex started without a page reload');
      await page.waitForSelector('[data-reindexing-notice]');
      t.ok(
        await page.locator('[data-reindexing-notice]').evaluate(el => el.classList.contains('cavil-notice-panel')),
        'stale-report notice uses CavilNoticePanel'
      );
      t.match(
        await page.locator('[data-reindexing-notice]').innerText(),
        /previous report, frozen/,
        'reviewer is told the report is frozen until it is replaced'
      );
      t.ok(await page.locator('#license-chart').count(), 'previous report stays visible while reindex is queued');

      await page.locator('#reindex_button.btn-outline-secondary').waitFor();
      t.equal(
        await page.getAttribute('#reindex_button', 'title'),
        'Reindex has been requested',
        'and the button stops offering what the queued rebuild is about to pick up'
      );
    });

    await t.test('Indexing shows a muted staged bar and takes the file actions away', async t => {
      // Run exactly one job in a second tab: the "index" job claims the package and starts writing the
      // new report beside the old one, leaving its batches in the queue. The reviewer's tab is not
      // reloaded, it has to pick the new stage up from its own state poll.
      const stepPage = await context.newPage();
      await stepPage.goto(`${url}/perform_one_job`, {timeout: 120000});
      t.equal(await stepPage.locator('body').innerText(), 'index', 'the index job ran and claimed the package');
      await stepPage.close();

      const active = page.locator('[data-reindexing-notice] .progress-segment.is-active');
      await active.filter({hasText: 'Indexing'}).waitFor({timeout: 20000});
      t.equal((await active.innerText()).trim(), 'Indexing', 'the staged bar moved on from Queued without a reload');
      t.equal(
        await page.locator('[data-reindexing-notice] .report-progress-compact').count(),
        1,
        'the bar beside a readable report is the compact variant'
      );
      t.equal(
        await page.locator('[data-reindexing-notice] .progress-meta').count(),
        0,
        'and drops the "Preparing report" chrome that would compete with the report'
      );
      t.ok(await page.locator('#license-chart').count(), 'the previous report is still there to read');

      // Everything that would write to the report the reviewer is looking at is gone from the file
      // previews, while the file itself stays readable.
      const fileHref = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = fileHref.replace('#file-', '');
      await expandFileDetails(page, fileId);
      t.ok(await page.locator(`#file-details-${fileId} table.snippet tr`).count(), 'the file is still readable');
      t.equal(await page.locator(`#file-details-${fileId} td.actions`).count(), 0, 'the line action menus are gone');
      t.equal(
        await page.locator(`#file-details-${fileId} td.quick-actions`).count(),
        0,
        'and so is the quick "create pattern" button'
      );
    });

    // Opened while the rebuild runs and left open across the next two subtests, because the file browser
    // has to notice the end of the rebuild by itself just like the report page does.
    const browserPage = await context.newPage();

    await t.test('The file browser pauses pattern work for the same rebuild', async t => {
      // A reviewer who walks into the checkout mid-rebuild gets the same answer the report page gives.
      // The state rides along with the very first payload, so the actions never appear and then vanish
      // from under the cursor.
      await browserPage.goto(`${url}/reviews/file_view/1/Mojolicious-7.25/lib/Mojolicious.pm`);
      await browserPage.waitForSelector('.file-browser-source table.snippet');
      t.match(
        await browserPage.innerText('.file-browser-source'),
        /package Mojolicious;/,
        'the file itself is still readable'
      );

      await browserPage.waitForSelector('[data-reindexing-notice]');
      t.match(
        await browserPage.innerText('[data-reindexing-notice]'),
        /Pattern creation is frozen/,
        'the reviewer is told why the browser went quiet'
      );
      t.equal(
        (await browserPage.locator('[data-reindexing-notice] .progress-segment.is-active').innerText()).trim(),
        'Indexing',
        'and sees the same stage as on the report page'
      );
      t.equal(
        await browserPage.locator('[data-reindexing-notice] .report-progress-compact').count(),
        1,
        'in the same compact bar'
      );
      t.equal(
        await browserPage.locator('.file-browser-source td.actions').count(),
        0,
        'the line action menus are gone'
      );
      t.equal(
        await browserPage.locator('.file-browser-source td.quick-actions').count(),
        0,
        'and so is the quick "create pattern" button'
      );
    });

    await t.test('The finished rebuild replaces the report on its own', async t => {
      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();

      // No reload: the state poll sees the rebuild end and fetches the new report in its place.
      await page.locator('[data-reindexing-notice]').waitFor({state: 'detached', timeout: 30000});
      await page.waitForSelector('#license-chart');
      t.ok(await page.locator('#filelist-snippets a.file-link').count(), 'the new report is complete');

      const fileHref = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = fileHref.replace('#file-', '');
      await expandFileDetails(page, fileId);
      t.ok(await page.locator(`#file-details-${fileId} td.actions`).count(), 'and can be worked on again');

      // The button answers for the new report, not the one that was on screen when the page was opened:
      // the pattern it was advertising is in, so there is nothing left to offer.
      await page.locator('#reindex_button[title="There are no new patterns"]').waitFor({timeout: 20000});
      t.ok(
        await page.locator('#reindex_button.btn-outline-secondary').count(),
        'the Reindex button settles down again without a reload'
      );
    });

    await t.test('The file browser opens back up once the new report lands', async t => {
      // No reload here either. The browser watches the same state endpoint, and when the promote lands it
      // fetches the whole path again: the new report has new matched file rows, so the ids this page was
      // holding are stale.
      await browserPage.locator('[data-reindexing-notice]').waitFor({state: 'detached', timeout: 30000});
      await browserPage.waitForSelector('.file-browser-source table.snippet');
      t.ok(
        await browserPage.locator('.file-browser-source td.actions').count(),
        'patterns can be created from the checkout again'
      );
      await browserPage.close();
    });

    await t.test('A rebuild somebody else starts pauses a batch that is still being filled', async t => {
      // A reviewer stages a pattern the usual way, and while the batch is still open the package is
      // reindexed from somewhere else - in production that is a pattern created against a completely
      // different report. The staged work is the reviewer's, so it is kept exactly as it is; it just
      // cannot be submitted against a report that is about to be replaced.
      const fileHref = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = fileHref.replace('#file-', '');
      await expandFileDetails(page, fileId);
      await openCreatePatternEditor(page, fileId);
      await fillInlinePatternBasics(page, 'Paused-By-Rebuild-1.0');
      await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').click();
      await waitForInlineSnippetEditorClosed(page);
      await page.waitForSelector('#pending-actions-widget');

      const otherPage = await context.newPage();
      await otherPage.goto(`${url}/reviews/details/1`);
      await otherPage.waitForSelector('#license-chart');
      await Promise.all([
        otherPage.waitForResponse(resp => /reindex/.test(resp.url()) && resp.request().method() === 'POST'),
        otherPage.click('#reindex_button')
      ]);
      await otherPage.close();

      // A settled report keeps a slow watch of its own, so the reviewer sees the notice appear instead
      // of finding out when the batch is refused.
      await page.locator('[data-reindexing-notice]').waitFor({timeout: 25000});

      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      t.match(
        await page.innerText('#pending-actions-widget'),
        /Paused-By-Rebuild-1.0/,
        'the staged pattern is still in the batch'
      );
      t.match(
        await page.innerText('#pending-actions-widget .pending-actions-paused'),
        /Waiting for the new report/,
        'the widget explains why it is waiting'
      );
      t.equal(await page.locator('#pending-actions-submit').isDisabled(), true, 'and the batch cannot be submitted');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
