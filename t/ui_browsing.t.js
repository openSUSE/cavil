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

    await t.test('Products (grouping and curator annotation)', async t => {
      // Report metadata collapses a package's codestreams into the curated product name (pristine state,
      // checked before any mutation below so it does not depend on test ordering)
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      t.ok(
        (await page.locator('.report-metadata-list a', {hasText: 'Multi-Linux Manager'}).count()) > 0,
        'report shows the curated product name'
      );

      // The annotated codestreams collapse into one deliverable row; the unannotated one stays a singleton
      await page.goto(url);
      await page.click('text=Products');
      t.equal(await page.innerText('title'), 'List products');
      await page.waitForSelector('#known-products tbody > tr');
      const mlm = page.locator('#known-products tbody > tr').filter({hasText: 'Multi-Linux Manager'}).first();
      await mlm.waitFor();
      t.match(await mlm.innerText(), /codestreams/, 'annotated codestreams collapse into one group');
      t.equal(
        await page.locator('#known-products tbody > tr').filter({hasText: 'openSUSE:Factory'}).count(),
        1,
        'unannotated codestream stays a singleton'
      );

      // Product links navigate in-page, not in a new tab
      t.equal(await mlm.locator('a[target="_blank"]').count(), 0, 'listing links stay in the same tab');

      // Toggling the grouping chip off switches to a flat view with each codestream's product exposed
      await Promise.all([
        page.waitForResponse(
          resp => /\/pagination\/products\/known/.test(resp.url()) && resp.url().includes('grouped=false')
        ),
        page.click('#cavil-products-grouped')
      ]);
      const flatRow = page.locator('#known-products tbody > tr').filter({hasText: 'MLM51:Update'}).first();
      await flatRow.waitFor();
      t.match(await flatRow.innerText(), /Multi-Linux Manager/, 'flat view exposes each codestream product');

      // Back to the default grouped view for the drill-down
      await page.goto(url);
      await page.click('text=Products');
      await page.waitForSelector('#known-products tbody > tr');
      const grouped = page.locator('#known-products tbody > tr').filter({hasText: 'Multi-Linux Manager'}).first();
      await grouped.waitFor();

      // Drilling into the group: the aggregate page has no annotation form but lists its member codestreams
      await grouped.locator('a').first().click();
      await page.waitForSelector('#product-reviews .cavil-codestreams');
      t.equal(await page.locator('#cavil-product-annotation').count(), 0, 'group page has no annotation form');
      await page.click('.cavil-codestreams > summary');
      t.equal(await page.locator('.cavil-codestreams a').count(), 2, 'group lists its member codestreams');

      // From a member codestream the annotation is editable and pre-filled with the current product
      await page.locator('.cavil-codestreams a').filter({hasText: 'MLM51:Update'}).first().click();
      await page.waitForSelector('#cavil-product-annotation');
      t.equal(await page.inputValue('#cavil-product-annotation'), 'Multi-Linux Manager', 'annotation is pre-filled');

      // Clearing the annotation returns the codestream to the listing as its own row (no dead end)
      await page.fill('#cavil-product-annotation', '');
      await Promise.all([
        page.waitForResponse(resp => /\/products\/.*\/annotation/.test(resp.url())),
        page.click('#cavil-save-annotation')
      ]);
      await page.waitForSelector('#cavil-save-annotation .fa-check');
      await page.goto(url);
      await page.click('text=Products');
      await page.waitForSelector('#known-products tbody > tr');
      t.equal(
        await page.locator('#known-products tbody > tr').filter({hasText: 'MLM51:Update'}).count(),
        1,
        'cleared codestream reappears as its own row'
      );

      // A curator can also set an annotation on a standalone codestream
      await page.goto(`${url}/products/openSUSE:Factory`);
      await page.waitForSelector('#cavil-product-annotation');
      await page.fill('#cavil-product-annotation', 'Tumbleweed Family');
      await Promise.all([
        page.waitForResponse(resp => /\/products\/.*\/annotation/.test(resp.url())),
        page.click('#cavil-save-annotation')
      ]);
      await page.waitForSelector('#cavil-save-annotation .fa-check');
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
      await page.waitForFunction(() => {
        const row = document.querySelector('#review-search tbody > tr:nth-child(1)');
        return row && !/Loading reviews/.test(row.textContent);
      });
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
      await page.locator('#open-reviews-filter-input').fill('synth');
      await Promise.all([
        page.waitForResponse(
          resp => /\/pagination\/reviews\/open/.test(resp.url()) && resp.url().includes('filter=synth')
        ),
        page.locator('#open-reviews-filter-input').press('Enter')
      ]);
      const synthRow = page.locator('#open-reviews tbody > tr').filter({hasText: 'zzz_synth#1'}).first();
      await synthRow.waitFor();
      await synthRow.locator('a[href^="/reviews/details/"]').click();
      t.equal(await page.innerText('title'), 'Report for synthetic-many-unresolved');
      await page.waitForSelector('#unmatched-files');
      t.match(await page.innerText('#unmatched-files'), /110 files/);
      t.equal(await page.locator('#hidden-previews-notice').count(), 0, 'inline preview indicator is not shown');
    });

    await t.test('Missing Licenses', async t => {
      // ui_fixtures seeds one new-license proposal, so the landing page renders that card (the full
      // approve/dismiss/edit flow lives in ui_patterns). This is a read-only presence check.
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Missing Licenses');
      t.equal(await page.innerText('title'), 'Missing Licenses');
      await page.waitForSelector('#missing-licenses .change-container');
      t.match(
        await page.innerText('#missing-licenses .change-header'),
        /Proposed license by/,
        'renders the seeded proposal card'
      );
    });

    await t.test('Change Proposals', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Change Proposals');
      t.equal(await page.innerText('title'), 'Change Proposals');
      await page.waitForFunction(() =>
        /All caught up!\s+No proposed changes are waiting for review/.test(document.body.innerText)
      );
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
      await page.waitForSelector('#statistics .stats-dashboard');
      t.equal(await page.locator('#statistics .stats-donut-tile').count(), 2, 'renders the donut tiles');
      t.equal(await page.locator('#statistics .stats-activity-tile').count(), 2, 'renders the activity tiles');
      t.equal(await page.locator('#statistics .stats-number-tile').count(), 5, 'renders the number tiles');
      t.match(await page.innerText('#statistics'), /Package activity/i);
      t.match(await page.innerText('#statistics'), /Review automation/i);
      t.match(await page.innerText('#statistics'), /Packages/i);
      t.match(await page.innerText('#statistics'), /Subcomponents/i);
      t.match(await page.innerText('#statistics'), /Embargoed Packages/i);
      t.match(await page.innerText('#statistics'), /Snippets/i);
      t.match(await page.innerText('#statistics'), /License Patterns/i);
      t.match(await page.innerText('#statistics'), /Unresolved Matches/i);

      await page.locator('#statistics .stats-scope-toggle button', {hasText: 'Month'}).click();
      t.match(
        await page.locator('#statistics .stats-donut-tile').filter({hasText: 'Review automation'}).innerText(),
        /performed reviews/
      );
      t.ok(
        await page.locator('#statistics .stats-scope-toggle button.active', {hasText: 'Month'}).isVisible(),
        'can switch review automation to monthly stats'
      );
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
