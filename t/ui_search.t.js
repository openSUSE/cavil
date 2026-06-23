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

  try {
    await t.test('Suggestion dropdown and mouse selection', async t => {
      await page.goto(url);

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

      // British spelling "harbour-helm" still finds "harbor-helm"
      await page.locator(input).fill('harbour-helm');
      await page.waitForSelector(`${items}:has-text("harbor-helm")`);
      t.match(await page.innerText(items), /harbor-helm/, 'closest name is suggested despite the typo');
    });

    await t.test('Plain Enter still searches without a suggestion', async t => {
      await page.goto(url);

      // No dropdown selection - Enter searches for the raw query
      await page.locator(input).fill('perl-Mojolicious');
      await page.locator(input).press('Enter');
      await page.waitForURL(`${url}/search?q=perl-Mojolicious`);
      await page.waitForSelector('#review-search tbody > tr:nth-child(1)');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /perl-Mojolicious/);
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
