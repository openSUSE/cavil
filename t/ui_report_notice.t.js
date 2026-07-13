#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The "why this needs review" box summarizes the diff against the closest
// previous review. When that diff introduces new unresolved matches, the box
// lists up to five of the affected files by name; each name looks like plain
// text but is a link that opens the same inline file preview as the Risk 9
// "unresolved matches" section further down. The "report_notice" fixture builds
// two synthetic versions of one package through the real pipeline: version 1 is
// accepted, version 2 (id 2) adds eight brand-new unresolved files.
t.test('Cavil UI - new unresolved matches notice', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'report_notice';
  const ui = await launchUi('js_ui_report_notice');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('box lists up to five new unresolved files with a "more" summary', async t => {
      await page.goto(`${url}/reviews/details/2`);
      await page.waitForSelector('#review-information');

      const box = await page.innerText('#review-information');
      t.match(box, /New unresolved matches in 8 files/, 'box shows the full count of new unresolved files');
      t.match(box, /\+ 3 more/, 'box summarizes the files beyond the first five');

      // The file names become links once the ReportDetails component has loaded
      // its file list (the two components fetch independently).
      await page.waitForSelector('#review-information a.review-information-file');
      const links = page.locator('#review-information a.review-information-file');
      t.equal(await links.count(), 5, 'exactly five files are listed as links');
    });

    await t.test('file names look like flat text until hovered', async t => {
      const firstLink = page.locator('#review-information a.review-information-file').first();
      const decoration = await firstLink.evaluate(el => getComputedStyle(el).textDecorationLine);
      t.equal(decoration, 'none', 'links are not underlined at rest');

      // Only the file name is inside the link, so the hover underline never
      // covers the leading indentation.
      const text = await firstLink.evaluate(el => el.textContent);
      t.equal(text, text.trim(), 'link wraps only the file name, not surrounding whitespace');
    });

    await t.test('clicking a file name scrolls to its inline preview like the Risk 9 list', async t => {
      const firstLink = page.locator('#review-information a.review-information-file').first();
      const fileId = (await firstLink.getAttribute('href')).replace('#file-', '');

      // The very same file is also listed in the lower Risk 9 unresolved section
      t.ok(
        (await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).count()) > 0,
        'the file also appears in the Risk 9 unresolved list'
      );

      // The preview for a missed file is rendered from the start (the Risk 9
      // section expands them), so the observable effect of clicking the box link
      // is that the report scrolls down to that file - the same navigation the
      // Risk 9 file links perform.
      await page.waitForSelector(`#file-details-${fileId} table.snippet`);
      await page.evaluate(() => window.scrollTo(0, 0));
      await firstLink.click();
      await page.waitForFunction(() => window.scrollY > 50, null, {timeout: 5000});
      t.ok(await page.evaluate(() => window.scrollY) > 0, 'clicking the file name scrolls the report to its preview');

      // The link keeps focus after the click, but a mouse click must not leave
      // it underlined (focus-visible only reacts to keyboard focus). Move the
      // pointer off the link first so we measure the focus state, not hover.
      await page.mouse.move(0, 0);
      const decoration = await firstLink.evaluate(el => getComputedStyle(el).textDecorationLine);
      t.equal(decoration, 'none', 'clicked link is not left underlined once the pointer leaves');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
