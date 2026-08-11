#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The declaration check annotates the report rather than interrupting it: a short muted note on the
// License row with the licenses behind it listed right underneath, a quiet pill in the risk breakdown,
// and the package's legal documents listed with whatever text no license pattern explains. The
// "declaration" fixture declares MIT while shipping GPL-2.0-only, vendors Apache-2.0, and carries a
// LICENSE whose terms are only partly recognised.
await t.test('Cavil UI - license declaration', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'declaration';
  const ui = await launchUi('js_ui_declaration');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await page.goto(`${url}/reviews/details/1`);
    const note = page.locator('#declaration-note');
    await note.waitFor();

    await t.test('names the possibly missing licenses, and nothing else', async t => {
      t.match(await page.locator('#pkg-license').innerText(), /MIT/, 'the declared license is still the value');
      // Worded as a lead to confirm, not as a defect: the check cannot always tell a bundled component
      // from shipped code, so it must not tell a packager their declaration is wrong.
      t.equal(
        await note.innerText(),
        'also found in the code, worth confirming: GPL-2.0-only',
        'the annotation names the identifier a packager would go and check'
      );
      t.notMatch(await note.innerText(), /not declared|missing|wrong|should/i, 'and does not assert a defect');

      // Identifiers only. A file count would not change what they look at, they know their own code; and
      // the other halves of the check are package file concerns that belong in the text report.
      t.notMatch(await note.innerText(), /file/, 'no file counts');
      t.notMatch(await note.innerText(), /engine\.c/, 'no file paths');
      t.notMatch(await note.innerText(), /Apache-2\.0/, 'the vendored license is not a missing license');
      t.notMatch(await note.innerText(), /vendored|not found/, 'no package file concerns on the License row');
    });

    await t.test('reads as an annotation rather than a second value', async t => {
      // Muted, on its own line under the declared license so it does not compete with it, and no panel
      const [color, display] = await note.evaluate(el => [getComputedStyle(el).color, getComputedStyle(el).display]);
      t.equal(color, 'rgb(140, 149, 159)', 'rendered in the muted metadata grey');
      t.equal(display, 'block', 'sits on its own line below the license');
      t.equal(await page.locator('.cavil-notice-panel-warning').count(), 0, 'no warning panel is raised');

      // Plain wrapping text, not a list or a grid: a package that misses dozens of licenses names all of
      // them and simply grows, rather than restructuring the row or hiding the tail behind a count
      t.equal(await page.locator('#pkg-license ul, #pkg-license li').count(), 0, 'no list markup in the row');
    });

    await t.test('the declaration stays out of the license report', async t => {
      // It is a statement about the package file, so it annotates the declared license and stops there.
      // The Licenses section reports what the code carries and stays free of package file concerns.
      await page.locator('.risk-license-item').first().waitFor();
      t.equal(await page.locator('.risk-undeclared').count(), 0, 'no declaration marker in the risk breakdown');
      t.notMatch(
        await page.locator('.report-tab-content').innerText(),
        /worth confirming|undeclared/i,
        'and nothing about the declaration anywhere in the report itself'
      );
    });

    await t.test('legal documents list what Cavil can explain of each file', async t => {
      const documents = page.locator('#legal-documents');
      await documents.waitFor();

      t.match(await documents.locator('.cavil-notice-heading').innerText(), /Legal documents/, 'panel title');

      const rows = documents.locator('.legal-document-item');
      t.equal(await rows.count(), 1, 'the package license file is listed');
      t.match(await rows.first().innerText(), /LICENSE/, 'named');

      // The SPDX line resolves, the three lines of novel terms do not - and the report is otherwise clean,
      // which is exactly the case this number exists to surface. Absolute, not a percentage, so a small
      // clause inside a large recognised license body cannot round away to nothing.
      t.match(await rows.first().innerText(), /4 lines · 3 unexplained/, 'size and unexplained remainder');

      // File names follow the report's convention: muted until hovered, not link-blue on arrival
      const link = rows.first().locator('a');
      t.match(await link.getAttribute('href'), /\/reviews\/file_view\/1\//, 'opens in the file browser');
      t.equal(await link.evaluate(el => getComputedStyle(el).color), 'rgb(87, 96, 106)', 'muted like other file names');
    });

    await t.test('the copied files list is left alone beside it', async t => {
      // Two independently sourced facts: what the packager installs, and what Cavil detected. They are
      // deliberately not cross-referenced, because a missing copied-files entry could equally be a macro
      // Cavil could not resolve.
      const panels = await page.locator('.cavil-notice-heading').allInnerTexts();
      t.ok(panels.some(title => /Legal documents/.test(title)), 'the detected list is present');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    await ui.teardown();
    delete process.env.JS_UI_FIXTURES;
  }
});
