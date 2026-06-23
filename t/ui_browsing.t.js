#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, openAccountMenu, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Admin browsing surface: the read-mostly pages an admin clicks through
// before doing real work. Login, the menubar, the basic list pages, and
// the account-menu landing pages (Missing Licenses, Statistics, ...). This
// file does not create or mutate patterns, notes, or reviews - those belong
// in the dedicated subject files.
t.test('Cavil UI - admin browsing', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_browsing');
  const {page, url, errorLogs} = ui;

  try {
    await t.test('Login', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Login');
      t.equal(await page.innerText('title'), 'List open reviews');
      await openAccountMenu(page);
      await page.click('text=Logout');
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Login');
      t.equal(await page.innerText('title'), 'List open reviews');
    });

    await t.test('Minion dashboard', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text="Minion Dashboard"');
      t.match(await page.innerText('title'), /Minion/);
      await page.click('text=Back to Site');
      t.equal(await page.innerText('title'), 'List open reviews');
    });

    await t.test('Navigation (logged in)', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Open Reviews');
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Recently Reviewed');
      t.equal(await page.innerText('title'), 'List recent reviews');
      await page.click('text=Products');
      t.equal(await page.innerText('title'), 'List products');
      await page.click('text=Licenses');
      t.equal(await page.innerText('title'), 'List licenses');
    });

    await t.test('Open reviews (logged in)', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.waitForSelector('#open-reviews tbody > tr:nth-child(10)');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), /Artistic/);

      await page.click('text=Next');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'test#7');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-UI-Test7');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'not yet imported');

      await page.click('text=Previous');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), /Artistic/);
    });

    await t.test('Reports', async t => {
      await page.goto(url);
      await page.click('text=Unknown');
      t.equal(await page.innerText('title'), 'Report for harbor-helm');
      await page.click('text=Open Reviews');
      t.equal(await page.innerText('title'), 'List open reviews');

      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
    });

    await t.test('Licenses', async t => {
      await page.goto(url);
      await page.click('text=Licenses');
      t.equal(await page.innerText('title'), 'List licenses');
      await page.click('text=Artistic-2.0');
      t.equal(await page.innerText('title'), 'License details of Artistic-2.0');
      await page.waitForSelector('#license-details .license-pattern-card');
      t.match(await page.innerText('#license-details .license-details-header'), /Artistic-2.0/);
      t.match(await page.innerText('#license-details .license-details-header'), /patterns/);
      t.ok(
        (await page.locator('#license-details button[data-action="edit-pattern-inline"]').count()) > 0,
        'admin sees inline edit buttons'
      );

      const initialCards = await page.locator('#license-details .license-pattern-card').count();
      t.ok(initialCards > 0, 'license detail has pattern cards');
      await page.locator('#license-details input[placeholder="Filter patterns"]').fill('this-filter-matches-nothing');
      await page.waitForSelector('#license-details .license-empty-state');
      t.equal(await page.locator('#license-details .license-pattern-card').count(), 0, 'filter can hide all cards');
      await page.locator('#license-details input[placeholder="Filter patterns"]').fill('');
      await page.waitForFunction(
        count => document.querySelectorAll('#license-details .license-pattern-card').length === count,
        initialCards
      );

      const spdx = await page.locator('#license-details input[name="spdx"]').inputValue();
      await page.locator('#license-details input[name="spdx"]').fill(spdx);
      await page.locator('#license-details .license-spdx-form button[type="submit"]').click();
      await page.waitForSelector('#license-details .toast-item.toast-success');
      t.match(await page.innerText('#license-details .toast-item'), /patterns updated/);
    });

    await t.test('Search (logged in)', async t => {
      await page.goto(url);
      await page.locator('[placeholder="Search packages"]').click();
      await page.locator('[placeholder="Search packages"]').fill('perl-Mojolicious');
      await page.locator('[placeholder="Search packages"]').press('Enter');
      await page.waitForURL(`${url}/search?q=perl-Mojolicious`);
      t.equal(await page.innerText('title'), 'Search Results');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /perl-Mojolicious/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(6)'), /GPL/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(5)'), /perl-Mojolicious/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(6)'), /Artistic/);
    });

    await t.test('File list cap per license (min_files_short_report)', async t => {
      // The Apache-2.0 bucket has been inflated to 102 unique files by the test
      // fixture. The in-bucket file list must be capped to
      // min_files_short_report + 1 = 21 to keep huge reports navigable.
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const apache = page.locator('#risk-5 > li').filter({hasText: 'Apache-2.0'}).first();
      t.match(await apache.innerText(), /102 files/);
      t.equal(await apache.locator('a.file-link').count(), 21);
      t.match(await apache.textContent(), /81 more/);
    });

    await t.test('Large unresolved report omits inline preview indicator', async t => {
      // mojo#1 has only a handful of unresolved matches, well under the
      // max_expanded_files cap - the indicator must stay out of the DOM.
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      t.equal(
        await page.locator('#hidden-previews-notice').count(),
        0,
        'no indicator when missed-file count is under the cap'
      );

      // synthetic-many-unresolved is a fixture package with 110 files, each
      // containing one unresolved keyword match (real index pipeline, real
      // sources). Navigate via the priority-1 open-reviews page -> row link
      // so we cover the actual user flow, not just the report URL. The
      // report has no license matches, so there's no #license-chart to wait
      // on - wait for the unmatched-files block to confirm the report loaded.
      await page.goto(url);
      await page.selectOption('select.cavil-pkg-priority', '1');
      await page.locator('#cavil-pkg-filter input[placeholder="Filter"]').fill('synth');
      const synthRow = page.locator('#open-reviews tbody > tr').filter({hasText: 'zzz_synth#1'}).first();
      await synthRow.waitFor();
      await synthRow.locator('a[href^="/reviews/details/"]').click();
      t.equal(await page.innerText('title'), 'Report for synthetic-many-unresolved');
      await page.waitForSelector('#unmatched-files');
      t.match(await page.innerText('#unmatched-files'), /110 files/);
      t.equal(await page.locator('#hidden-previews-notice').count(), 0, 'inline preview indicator is not shown');
    });

    await t.test('Missing Licenses', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Missing Licenses');
      t.equal(await page.innerText('title'), 'Missing Licenses');
      await page.waitForSelector('#missing-licenses > div > div:nth-child(2)');
      t.match(
        await page.innerText('#missing-licenses > div > div:nth-child(2)'),
        /All caught up!\s+No missing licenses have been flagged/
      );
    });

    await t.test('Change Proposals', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Change Proposals');
      t.equal(await page.innerText('title'), 'Change Proposals');
      await page.waitForSelector('#proposed-patterns > div > div:nth-child(3)');
      t.match(
        await page.innerText('#proposed-patterns > div > div:nth-child(3)'),
        /All caught up!\s+No proposed changes are waiting for review/
      );
    });

    await t.test('Statistics', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Statistics');
      t.equal(await page.innerText('title'), 'Statistics');
      await page.waitForSelector('#statistics .stats-body');
      t.equal(await page.innerText('#statistics .stats-body'), '25');
    });

    await t.test('API Keys', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=API Keys');
      t.equal(await page.innerText('title'), 'API Keys');
      await page.waitForSelector('#api-keys tbody > tr:nth-child(1)');
      t.equal(await page.innerText('#api-keys tbody > tr:nth-child(1) > td:nth-child(1)'), 'No API keys found.');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
