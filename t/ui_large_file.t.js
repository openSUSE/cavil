#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The standalone file browser no longer withholds a file that is over the size
// budget: it shows the top of the file (where license matches usually live) and
// appends an end-of-file marker. The marker also tells a reviewer whether any
// license or unresolved matches remain past the cut, so they know when the part
// they cannot see still needs attention. The "large_file" fixture (one package,
// id 1) has the browser budget lowered to 2000 bytes and two files that both
// exceed it: top-heavy.txt keeps its only match in the shown header, while
// hidden-match.txt repeats the match far below the cut.
t.test('Cavil UI - large file browser truncation', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'large_file';
  const ui = await launchUi('js_ui_large_file');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');
    await page.goto(`${url}/reviews/details/1`);
    await page.waitForSelector('.report-metadata-name');
    t.match(await page.innerText('.report-metadata-name'), /large-file/, 'the fixture report loaded');

    // The file browser is reached through a file's "open file" link on the
    // report; read those hrefs (while still on the report) rather than
    // hand-building the URLs.
    const browserUrl = async name => {
      const link = page.locator('a[id^="expand-link-"]', {hasText: name}).first();
      await link.waitFor({state: 'attached'});
      return link.getAttribute('href');
    };
    const topHeavyUrl = await browserUrl('top-heavy.txt');
    const hiddenMatchUrl = await browserUrl('hidden-match.txt');

    await t.test('a match still in view reassures that nothing waits below', async t => {
      await page.goto(`${url}${topHeavyUrl}`);
      await page.waitForSelector('.file-browser-source .snippet');

      // Only the top of the file is rendered, not all 151 lines
      const shown = await page.locator('.file-browser-source td.linenumber').count();
      t.ok(shown > 0 && shown < 151, `only the top of the file is shown (${shown} lines)`);

      const marker = page.locator('.source-truncation');
      t.equal(await marker.count(), 1, 'the end-of-file marker is shown');
      t.equal(await page.locator('.source-truncation.has-matches-below').count(), 0, 'the marker is the calm variant');
      t.match(await marker.innerText(), /shortened to the first .* - no further matches below/, 'it reassures');
    });

    await t.test('a match past the cut warns that matches remain below', async t => {
      await page.goto(`${url}${hiddenMatchUrl}`);
      await page.waitForSelector('.file-browser-source .snippet');

      const marker = page.locator('.source-truncation.has-matches-below');
      t.equal(await marker.count(), 1, 'the marker turns to its warning variant');
      t.match(await marker.innerText(), /shortened to the first .* - 1 more match below/, 'it counts the hidden match');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
