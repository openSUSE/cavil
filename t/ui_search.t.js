#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Package search: the navbar autocomplete (PackageSearch.vue) that predicts
// package names via the /package/autocomplete endpoint (trigram + substring
// blend), plus the search results page it navigates to. Exercises the real
// user flow - typing, the suggestion dropdown, mouse and keyboard selection,
// and typo tolerance - rather than poking the endpoint directly.
t.test('Cavil UI - package search', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_search');
  const {page, url, errorLogs} = ui;

  const input = '#cavil-package-search input';
  const items = '#cavil-package-search .autocomplete-item';
  const trigger = '#cavil-package-search .cavil-package-search-trigger';
  const openPackageSearch = async () => {
    await page.locator(trigger).click();
    await page.locator(input).waitFor({state: 'visible'});
  };
  const isFocused = selector => page.locator(selector).evaluate(element => element === document.activeElement);

  try {
    await t.test('Suggestion dropdown and mouse selection', async t => {
      await page.goto(url);
      t.notOk(await page.locator(input).isVisible(), 'package search starts collapsed');
      await openPackageSearch();
      t.ok(await isFocused(input), 'opening package search focuses the input');

      await page.locator(input).press('Escape');
      t.notOk(await page.locator(input).isVisible(), 'Escape collapses package search');
      t.ok(await isFocused(trigger), 'Escape restores focus to the trigger');
      await openPackageSearch();

      // Typing a prefix predicts the matching package name
      await page.locator(input).fill('perl-Moj');
      await page.waitForSelector(`${items}:has-text("perl-Mojolicious")`);
      t.equal(await page.locator(items).count(), 1, 'only the matching package is suggested');

      // Clicking a suggestion runs the search
      await page.locator(items).filter({hasText: 'perl-Mojolicious'}).click();
      await page.waitForURL(`${url}/search?q=perl-Mojolicious`);
      t.equal(await page.innerText('title'), 'Search Results');
      await page.waitForSelector('#review-search tbody > tr:nth-child(1)');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /perl-Mojolicious/);

      // The search box keeps the term on the results page
      t.equal(await page.locator(input).inputValue(), 'perl-Mojolicious');
    });

    await t.test('Keyboard navigation', async t => {
      await page.goto(url);
      await openPackageSearch();

      await page.locator(input).fill('harbo');
      await page.waitForSelector(`${items}:has-text("harbor-helm")`);

      // Arrow down highlights the first suggestion, Enter selects it
      await page.locator(input).press('ArrowDown');
      await page.waitForSelector(`${items}.active:has-text("harbor-helm")`);
      await page.locator(input).press('Enter');

      await page.waitForURL(`${url}/search?q=harbor-helm`);
      await page.waitForSelector('#review-search tbody > tr:nth-child(1)');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /harbor-helm/);
    });

    await t.test('Typo tolerance (trigram)', async t => {
      await page.goto(url);
      await openPackageSearch();

      // British spelling "harbour-helm" still finds "harbor-helm"
      await page.locator(input).fill('harbour-helm');
      await page.waitForSelector(`${items}:has-text("harbor-helm")`);
      t.match(await page.innerText(items), /harbor-helm/, 'closest name is suggested despite the typo');
    });

    await t.test('Plain Enter still searches without a suggestion', async t => {
      await page.goto(url);
      await openPackageSearch();

      // No dropdown selection - Enter searches for the raw query
      await page.locator(input).fill('perl-Mojolicious');
      await page.locator(input).press('Enter');
      await page.waitForURL(`${url}/search?q=perl-Mojolicious`);
      await page.waitForSelector('#review-search tbody > tr:nth-child(1)');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /perl-Mojolicious/);
    });

    await t.test('A bare numeric id jumps straight to that package report', async t => {
      // Review notes cite raw package ids; grab a real one from the results page, then look it up.
      await page.goto(`${url}/search?q=perl-Mojolicious`);
      const href = await page.getAttribute('#review-search a[href^="/reviews/details/"]', 'href');
      const id = href.match(/\/reviews\/details\/(\d+)/)[1];

      // The report page is logged-in only (the wrapper's dummy auth creates the admin "tester").
      await page.goto(url);
      await page.click('text=Login');
      await openPackageSearch();
      await page.locator(input).fill(id);
      await page.locator(input).press('Enter');
      await page.waitForURL(`${url}/reviews/details/${id}`);
      t.pass('numeric id navigates to the report, not a name search');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
