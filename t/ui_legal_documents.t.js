#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The legal documents panel lists the files that state a package's terms with how much of each no known
// license pattern explains. The "legal_documents" fixture carries a LICENSE whose terms are only partly
// recognised, plus a vendored license and a Go file named license.go that must both stay out of it.
await t.test('Cavil UI - legal documents', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'legal_documents';
  const ui = await launchUi('js_ui_legal_documents');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await page.goto(`${url}/reviews/details/1`);
    const documents = page.locator('#legal-documents');
    await documents.waitFor();

    await t.test('lists what Cavil can explain of each file', async t => {
      t.match(await documents.locator('.cavil-notice-heading').innerText(), /Legal documents/, 'panel title');

      const rows = documents.locator('.legal-document-item');
      t.equal(await rows.count(), 1, 'the package license file is listed, and only that');
      t.match(await rows.first().innerText(), /LICENSE/, 'named');
      t.notMatch(await documents.innerText(), /vendor|license\.go/, 'vendored licenses and source are left out');

      // The SPDX line resolves, the three lines of novel terms do not - and the report is otherwise clean,
      // which is exactly the case this number exists to surface. Absolute, not a percentage, so a small
      // clause inside a large recognised license body cannot round away to nothing.
      t.match(await rows.first().innerText(), /4 lines · 3 unexplained/, 'size and unexplained remainder');

      // Bold is the scanning cue for "something here", so it goes on the remainder and not on the size
      t.equal(await rows.first().locator('b').innerText(), '3', 'the unexplained count is the emphasised part');

      // File names follow the report's convention: muted until hovered, not link-blue on arrival
      const link = rows.first().locator('a');
      t.match(await link.getAttribute('href'), /\/reviews\/file_view\/1\//, 'opens in the file browser');
      t.equal(await link.evaluate(el => getComputedStyle(el).color), 'rgb(87, 96, 106)', 'muted like other file names');
    });

    await t.test('nothing grades the declared license', async t => {
      const license = page.locator('#pkg-license');
      t.match(await license.innerText(), /MIT/, 'the declared license is shown as the plain value');
      t.notMatch(await license.innerText(), /declared|confirming|found in the code/i, 'with no annotation');
      t.equal(await page.locator('#declaration-note').count(), 0, 'and no annotation element at all');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    await ui.teardown();
    delete process.env.JS_UI_FIXTURES;
  }
});
