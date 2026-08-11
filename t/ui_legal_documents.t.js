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
      t.equal(await rows.count(), 3, 'the package own license files are listed, and only those');
      t.match(await rows.nth(0).innerText(), /COPYING/, 'shallowest first, then alphabetical');
      t.match(await rows.nth(1).innerText(), /LICENSE/, 'named');
      t.match(await rows.nth(2).innerText(), /fonts\/tex-gyre\/META-INF\/LICENSE/, 'nested paths are kept in full');
      t.notMatch(await documents.innerText(), /vendor|license\.go/, 'vendored licenses and source are left out');

      // The whole point of the layout: 120 and 4 are different widths, and their digits still end at the
      // same x so the column can be scanned down rather than re-read on every row.
      const [long, short] = await Promise.all(
        [0, 1].map(i =>
          rows
            .nth(i)
            .locator('.legal-document-count')
            .last()
            .evaluate(el => el.getBoundingClientRect().right)
        )
      );
      t.equal(Math.round(long), Math.round(short), 'counts of different widths right-align to one column');

      // The SPDX line resolves, the three lines of novel terms do not - and the report is otherwise clean,
      // which is exactly the case this number exists to surface. Absolute, not a percentage, so a small
      // clause inside a large recognised license body cannot round away to nothing.
      t.match(await rows.nth(1).innerText(), /3 unexplained\s+4 lines/, 'size and unexplained remainder');
      t.match(await rows.nth(0).innerText(), /119 unexplained\s+120 lines/, 'and on the longer document');

      // Bold is the scanning cue for "something here", so it goes on the remainder and not on the size
      t.equal(await rows.nth(1).locator('b').innerText(), '3', 'the unexplained count is the emphasised part');

      // File names follow the report's convention: muted until hovered, not link-blue on arrival
      const link = rows.nth(1).locator('a');
      t.match(await link.getAttribute('href'), /\/reviews\/file_view\/1\//, 'opens in the file browser');
      t.equal(await link.evaluate(el => getComputedStyle(el).color), 'rgb(87, 96, 106)', 'muted like other file names');

      // The name is what the eye hunts for at the end of a long path, so the directory recedes a step
      const nested = rows.nth(2).locator('a');
      const dir = nested.locator('.cavil-path-dir');
      t.equal(await dir.innerText(), 'legal-docs-1.0/fonts/tex-gyre/META-INF/', 'the directory is a part of its own');
      t.equal(
        await dir.evaluate(el => getComputedStyle(el).color),
        'rgb(140, 149, 159)',
        'dimmed a step below the file name it leads to'
      );
      t.equal(await nested.evaluate(el => getComputedStyle(el).color), 'rgb(87, 96, 106)', 'which keeps the weight');

      // Every file in a real package sits under the version directory, so the prefix every row repeats
      // recedes for free - which is most of what made the long TeX Live paths tiring to read.
      t.equal(await link.locator('.cavil-path-dir').innerText(), 'legal-docs-1.0/', 'even a lone shared prefix');
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
