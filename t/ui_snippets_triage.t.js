#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The Classify Snippets page lets reviewers triage folding decisions: filter by fold / clear status
// (read from the stored file_snippets.resolution column) and full-text search the snippet bodies for
// phrases we never want folded. The "snippet_triage" fixture seeds 12 would-fold snippets (one a
// Non-Commercial stemming case), 1 would-clear (zero margin), and 1 unresolved (low similarity).
t.test('Cavil UI - snippet triage filters and search', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'snippet_triage';
  const ui = await launchUi('js_ui_snippet_triage');
  const {page, url, errorLogs} = ui;

  const metaResponse = () => page.waitForResponse(r => r.url().includes('/snippets/meta'));
  const open = async () => {
    await Promise.all([metaResponse(), page.goto(`${url}/snippets`)]);
    await page.waitForSelector('.cavil-snippet-resolution');
  };
  const setResolution = async value =>
    Promise.all([metaResponse(), page.selectOption('.cavil-snippet-resolution', value)]);
  const search = async term => {
    await page.fill('.cavil-snippet-search', term);
    await metaResponse();
  };
  const containers = () => page.locator('.snippet-container');
  const rowsWith = txt => page.locator(`.snippet-container:has-text("${txt}")`).count();
  // Wait for the list to actually re-render with a known row before asserting which rows are absent
  // (the meta response resolving does not mean Vue has painted yet).
  const waitForRow = txt => page.locator(`.snippet-container:has-text("${txt}")`).first().waitFor();

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('folded filter shows only would-fold snippets', async t => {
      await open();
      await setResolution('fold');
      await waitForRow('fold marker');
      t.ok((await rowsWith('fold marker')) > 0, 'folded rows are shown');
      t.equal(await rowsWith('cleared boilerplate'), 0, 'cleared rows are hidden');
      t.equal(await rowsWith('unresolved random noise'), 0, 'unresolved rows are hidden');
    });

    await t.test('cleared filter shows only would-clear snippets', async t => {
      await open();
      await setResolution('clear');
      await waitForRow('cleared boilerplate');
      t.ok((await rowsWith('cleared boilerplate')) > 0, 'cleared rows are shown');
      t.equal(await rowsWith('fold marker'), 0, 'folded rows are hidden');
    });

    await t.test('full-text search narrows by lexeme, including stemming', async t => {
      await open();
      await search('boilerplate');
      await waitForRow('cleared boilerplate');
      t.ok((await rowsWith('cleared boilerplate')) > 0, 'the matching snippet is shown');
      t.equal(await rowsWith('fold marker'), 0, 'snippets without the term are hidden');

      await open();
      await search('commercial'); // stems to match "Non-Commercial"
      await waitForRow('Non-Commercial');
      t.ok((await rowsWith('Non-Commercial')) > 0, 'a stemmed term matches Non-Commercial');
    });

    await t.test('a no-match search shows the empty state', async t => {
      await open();
      await search('zzzdefinitelynotpresent');
      await page.waitForSelector('#snippets-empty');
      t.equal(await containers().count(), 0, 'no snippet rows remain');
    });

    await t.test('fold filter and search compose (the proactive-audit path)', async t => {
      await open();
      await setResolution('fold');
      await search('marker');
      await waitForRow('fold marker');
      t.ok((await rowsWith('fold marker')) > 0, 'folded rows containing the term are shown');
      t.equal(await rowsWith('cleared boilerplate'), 0, 'the cleared row is excluded by the fold filter');
    });

    await t.test('keyset load-more with no exact total', async t => {
      await open();
      await setResolution('fold');
      await waitForRow('fold marker');
      t.equal(await page.locator('text=snippets found').count(), 0, 'no exact total is shown');

      // Keyset "load more" pulls the rest in as the reviewer scrolls; the page is filled one keyset
      // page at a time (10 cap is asserted in the backend test) until all 12 folded rows are present.
      await page.waitForFunction(
        () => {
          window.scrollTo(0, document.documentElement.scrollHeight);
          window.dispatchEvent(new Event('scroll'));
          return document.querySelectorAll('.snippet-container').length >= 12;
        },
        null,
        {timeout: 20000}
      );
      t.equal(await containers().count(), 12, 'load-more eventually shows all folded rows');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
