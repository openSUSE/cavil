#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Review search: the navbar autocomplete (PackageSearch.vue) that predicts
// package names via the /package/autocomplete endpoint (trigram + substring
// blend), plus the search results page it navigates to. Exercises the real
// user flow - typing, the suggestion dropdown, mouse and keyboard selection,
// and typo tolerance - rather than poking the endpoint directly.
t.test('Cavil UI - review search', skipUnlessOnline, async t => {
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
      t.notOk(await page.locator(input).isVisible(), 'review search starts collapsed');
      await openPackageSearch();
      t.ok(await isFocused(input), 'opening review search focuses the input');

      await page.locator(input).press('Escape');
      t.notOk(await page.locator(input).isVisible(), 'Escape collapses review search');
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

    await t.test('Any cited id lists every review it may refer to', async t => {
      const rows = '#review-search tbody > tr';
      const ids = name => page.locator(rows).filter({hasText: name}).locator('td:nth-child(6)');

      // The Cavil id of perl-UI-Test1 is also the number in perl-UI-Test3's link and a closed request of harbor-helm
      await page.goto(`${url}/search?q=perl-UI-Test1`);
      const id = (await ids('perl-UI-Test1').locator('.cavil-list-token').innerText()).match(/cavil#(\d+)/)[1];
      await openPackageSearch();
      await page.locator(input).fill(id);
      await page.locator(input).press('Enter');
      await page.waitForURL(`${url}/search?q=${id}`);
      await page.waitForSelector(`${rows}:nth-child(3) > td:nth-child(6)`);
      t.equal(await page.locator(rows).count(), 3, 'every candidate listed, no jump to a report');
      t.equal(await ids('perl-UI-Test1').locator('.cavil-list-token.is-matched').innerText(), `cavil#${id}`);
      t.equal(await ids('perl-UI-Test3').locator('.cavil-search-link.is-matched').innerText(), `test#${id}`);
      t.equal(await ids('harbor-helm').locator('.cavil-search-link.is-matched.is-closed').innerText(), `ibs#${id}`);
      t.match(await ids('harbor-helm').innerText(), /obs#123456/, 'primary link shown too');
      t.match(await page.innerText(`${rows}:nth-child(3)`), /harbor-helm/, 'closed match listed last');

      // Extra words narrow when they fit a candidate, and are ignored when they fit none
      await page.goto(`${url}/search?q=${encodeURIComponent(`ibs#${id}`)}`);
      await page.waitForSelector(`${rows}:nth-child(1) > td:nth-child(6)`);
      t.equal(await page.locator(rows).count(), 1, 'link prefix narrows to the request');
      t.match(await page.innerText(`${rows}:nth-child(1) > td:nth-child(5)`), /harbor-helm/);

      await page.goto(`${url}/search?q=${encodeURIComponent('SR#123456')}`);
      await page.waitForSelector(`${rows}:nth-child(1) > td:nth-child(6)`);
      t.equal(await page.locator(rows).count(), 1, 'unknown word "SR" is ignored');
      t.match(await page.innerText(`${rows}:nth-child(1) > td:nth-child(5)`), /harbor-helm/);
    });

    await t.test('Long links wrap inside the Ids column instead of overlapping the report', async t => {
      await page.route('**/pagination/search/**', async route => {
        const response = await route.fetch();
        const data = await response.json();
        data.page[0].links = [
          {
            text: 'ssd#pool/aws-nitro-enclaves-cli!12',
            label: 'SUSE',
            url: 'https://src.suse.de/pool/aws-nitro-enclaves-cli/pulls/12',
            active: true
          }
        ];
        await route.fulfill({response, json: data});
      });
      await page.goto(`${url}/search?q=perl-Mojolicious`);
      const cell = page.locator('#review-search tbody > tr:nth-child(1) > td:nth-child(6)');
      await cell.locator('.cavil-search-link').waitFor();
      const {pill, report} = await cell.evaluate(td => ({
        pill: td.querySelector('.cavil-external-link').getBoundingClientRect().right,
        report: td.nextElementSibling.getBoundingClientRect().left
      }));
      t.ok(pill <= report, 'link stays left of the report column');
      t.match(await cell.innerText(), /cli!12/, 'request number stays visible');
      await page.unroute('**/pagination/search/**');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
