#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The legal documents panel lists the files that state a package's terms with the lines of each no known
// license pattern matched. The "legal_documents" fixture carries a LICENSE whose terms are only partly
// recognised, one Cavil recognises completely, and a vendored license and a Go file named license.go that
// must both stay out of it. Its second package has nothing left over anywhere, which is the common case
// and a different panel.
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

      // Located by path rather than index, so adding a document to the fixture does not renumber the rest
      const rows = documents.locator('.legal-document-item');
      const paths = await documents.locator('.cavil-path').allTextContents();
      const rowFor = path => rows.nth(paths.indexOf(path));

      t.equal(await rows.count(), 5, 'the package own license files are listed, and only those');
      t.notMatch(await documents.innerText(), /vendor|license\.go/, 'vendored licenses and source are left out');
      t.match(
        (await rows.allInnerTexts()).join('|'),
        /COPYING.*COPYRIGHT.*LICENSE.*LICENSE\.MIT.*fonts\/tex-gyre/s,
        'shallowest first, then alphabetical'
      );

      // The whole point of the layout: 120, 6 and 4 are different widths and one row has no remainder at
      // all, and every line count still ends at the same x, so the column can be scanned down rather than
      // re-read on every row.
      const sizes = await documents
        .locator('.legal-document-total .legal-document-count')
        .evaluateAll(els => els.map(el => Math.round(el.getBoundingClientRect().right)));
      t.equal(sizes.length, 5, 'every row states its size');
      t.equal(new Set(sizes).size, 1, 'and they right-align to one column');

      // The SPDX line resolves, the three lines of novel terms do not - and the report is otherwise clean,
      // which is exactly the case this number exists to surface. Absolute, not a percentage, so a small
      // clause inside a large recognised license body cannot round away to nothing.
      const license = rowFor('legal-docs-1.0/LICENSE');
      t.match(await license.innerText(), /4 lines\s+3 unrecognised/, 'the size, then what is left of it');
      t.match(
        await rowFor('legal-docs-1.0/COPYING').innerText(),
        /120 lines\s+119 unrecognised/,
        'and on a longer one'
      );

      // Bold is the scanning cue for "something here", so it goes on the remainder and not on the size
      t.equal(await license.locator('b').innerText(), '3', 'the remainder is the emphasised part');

      // A recognised file's row simply stops after its size. The slot stays behind it, empty, because the
      // rows either side of it hang their line counts off its width.
      const covered = rowFor('legal-docs-1.0/LICENSE.MIT').locator('.legal-document-unexplained');
      t.equal(await covered.innerText(), '', 'a file with nothing left over says nothing');
      t.ok(await covered.evaluate(el => el.getBoundingClientRect().width > 0), 'but still holds the column open');

      // Said once for the panel, rather than a word on every row
      t.match(
        await documents.locator('.cavil-notice-summary').innerText(),
        /lines no known license matched/,
        'the counts are explained where they are introduced'
      );

      // File names follow the report's convention: muted until hovered, not link-blue on arrival
      const link = license.locator('a');
      t.match(await link.getAttribute('href'), /\/reviews\/file_view\/1\//, 'opens in the file browser');
      t.equal(await link.evaluate(el => getComputedStyle(el).color), 'rgb(87, 96, 106)', 'muted like other file names');

      // Cavil's marker for its own normalised copy never distinguishes two rows here - the original is
      // not in the file list at all - so it is dropped rather than dimmed, sparing every reader the job
      // of mentally stripping it. The real path stays available in the title.
      const processed = rowFor('legal-docs-1.0/COPYRIGHT');
      t.equal(await processed.locator('.cavil-path-name').innerText(), 'COPYRIGHT', 'the name reads as the real one');
      t.equal(
        await processed.locator('.cavil-path').getAttribute('title'),
        'legal-docs-1.0/COPYRIGHT.processed',
        'and the copy that was actually indexed is still recoverable'
      );
      t.equal(
        await rowFor('legal-docs-1.0/LICENSE').locator('.cavil-path').getAttribute('title'),
        null,
        'a path with nothing hidden carries no title'
      );

      // Both parts light up together, or a dimmed one reads as unclickable
      await processed.locator('a').hover();
      const hovered = await Promise.all(
        ['.cavil-path-dir', '.cavil-path-name'].map(part =>
          processed.locator(part).evaluate(el => getComputedStyle(el).color)
        )
      );
      t.strictSame(hovered, Array(2).fill('rgb(5, 80, 174)'), 'hovering turns the whole path link-blue');

      // The name is what the eye hunts for at the end of a long path, so the directory recedes a step
      const nested = rowFor('legal-docs-1.0/fonts/tex-gyre/META-INF/LICENSE').locator('a');
      const dir = nested.locator('.cavil-path-dir');
      t.equal(await dir.innerText(), 'legal-docs-1.0/fonts/tex-gyre/META-INF/', 'the directory is a part of its own');

      // Screenshotting real paths showed the separation has to come from darkening the name, not from
      // fading the directory: faded reads as washed out, and the directory is the half that matters.
      t.equal(
        await dir.evaluate(el => getComputedStyle(el).color),
        'rgb(110, 119, 129)',
        'the directory stays legible, one step below the muted default'
      );
      t.equal(
        await nested.locator('.cavil-path-name').evaluate(el => getComputedStyle(el).color),
        'rgb(36, 41, 47)',
        'while the name carries the contrast'
      );

      // Every file in a real package sits under the version directory, so the prefix every row repeats
      // recedes for free - which is most of what made the long TeX Live paths tiring to read.
      t.equal(await link.locator('.cavil-path-dir').innerText(), 'legal-docs-1.0/', 'even a lone shared prefix');
    });

    // Shares this fixture: ISC is only in vendor/helper, MIT and Apache-2.0 are in shipped code.
    await t.test('the license list says when a license is only in uninteresting places', async t => {
      const scoped = page.locator('.risk-license-item', {has: page.locator('.risk-license-scope')});
      t.equal(await scoped.count(), 1, 'exactly the one license that never touches shipped code');
      t.match(await scoped.innerText(), /ISC/, 'the vendored-only license');
      t.match(await scoped.locator('.risk-license-scope').innerText(), /^only in vendored files$/, 'says where');

      // A location, not a verdict: a wrong "vendored" that read as "ignore this" would hide a real license
      t.notMatch(await scoped.innerText(), /ignore|safe|skip/i, 'and never what to do about it');
    });

    // The common case in production, and the reason the remainder is a property of the report rather than
    // of a row: a reserved column no row fills, under a sentence defining a count that never appears,
    // leaves a reader working out what is missing from a panel that has nothing to report.
    await t.test('a package Cavil recognises completely just lists its documents', async t => {
      await page.goto(`${url}/reviews/details/2`);
      const clean = page.locator('#legal-documents');
      await clean.waitFor();

      t.equal(await clean.locator('.legal-document-item').count(), 2, 'both documents are listed');
      t.match(await clean.innerText(), /COPYING.*6 lines.*LICENSE.*1 line/s, 'each with nothing but its size');
      t.equal(await clean.locator('.legal-document-unexplained').count(), 0, 'no slot for a count no row has');
      t.equal(await clean.locator('.cavil-notice-summary').count(), 0, 'and no sentence explaining one');

      // "1 line" is narrower than "6 lines", so the digits align only because the count is a box of its own
      const sizes = await clean
        .locator('.legal-document-count')
        .evaluateAll(els => els.map(el => Math.round(el.getBoundingClientRect().right)));
      t.equal(new Set(sizes).size, 1, 'a lone document and a singular line count still share the column');
    });

    await page.goto(`${url}/reviews/details/1`);
    await page.locator('#legal-documents').waitFor();

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
