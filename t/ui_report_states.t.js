#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Report header / placeholder behaviour for special package states. The
// wrapper exposes /test/obsolete_with_report, /test/obsolete_without_report,
// /test/empty_report and /test/restore_report_state to flip a package into
// each shape and back; this file walks through all three to ensure the
// right notice panel renders.
t.test('Cavil UI - report states', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_report_states');
  const {page, url, errorLogs} = ui;

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

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
