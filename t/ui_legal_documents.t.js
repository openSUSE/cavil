#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The "legal_documents" fixture has a partly recognised LICENSE, a fully recognised one, and a vendored
// license plus a Go file named license.go that must both stay out. Its second package has nothing left
// over anywhere, which is the common case and a different panel.
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

      t.equal(await rows.count(), 6, 'the package own license files are listed, and only those');
      t.notMatch(await documents.innerText(), /vendor|license\.go/, 'vendored licenses and source are left out');
      t.match(
        (await rows.allInnerTexts()).join('|'),
        /COPYING.*COPYRIGHT.*LICENSE.*LICENSE\.MIT.*LICENSE\.enterprise.*fonts\/tex-gyre/s,
        'shallowest first, then alphabetical'
      );

      // Counts of different widths, and one row with no remainder at all, still share one column
      const sizes = await documents
        .locator('.legal-document-total .legal-document-count')
        .evaluateAll(els => els.map(el => Math.round(el.getBoundingClientRect().right)));
      t.equal(sizes.length, 6, 'every row states its size');
      t.equal(new Set(sizes).size, 1, 'and they right-align to one column');

      // The SPDX line resolves, the three lines of novel terms do not - and the report is otherwise clean,
      // which is exactly the case this number exists to surface. Absolute, not a percentage, so a small
      // clause inside a large recognised license body cannot round away to nothing.
      const license = rowFor('legal-docs-1.0/LICENSE');
      t.match(await license.innerText(), /4 lines\s+3 unknown/, 'the size, then what is left of it');
      t.match(await rowFor('legal-docs-1.0/COPYING').innerText(), /120 lines\s+119 unknown/, 'and on a longer one');

      // Bold is the scanning cue for "something here", so it goes on the remainder and not on the size
      t.equal(await license.locator('b').innerText(), '3', 'the remainder is the emphasised part');

      // Five blocks for a file with nothing recognised in it, four while any of it is matched
      const filled = row => row.locator('.legal-document-block.is-unknown').count();
      t.equal(await license.locator('.legal-document-block').count(), 5, 'the mark is five blocks');
      t.equal(await filled(rowFor('legal-docs-1.0/COPYING')), 4, '119 of 120 lines is not the whole file');
      t.equal(await filled(rowFor('legal-docs-1.0/COPYRIGHT')), 5, 'a document that matched nothing is');
      t.equal(await filled(rowFor('legal-docs-1.0/LICENSE.enterprise')), 1, 'and a clause on a stock body is one');
      t.equal(
        await license.locator('.legal-document-unexplained').getAttribute('title'),
        '3 of 4 lines unknown',
        'and hovering states the ratio the blocks stand for'
      );

      // Hidden rather than reserved, so no row carries dead space behind its mark
      const edges = await license
        .locator('.legal-document-unexplained, .legal-document-meter')
        .evaluateAll(els => els.map(el => Math.round(el.getBoundingClientRect().right)));
      t.equal(new Set(edges).size, 1, 'the mark ends where the slot does');

      const covered = rowFor('legal-docs-1.0/LICENSE.MIT').locator('.legal-document-unexplained');
      t.notOk(await covered.isVisible(), 'a file with nothing left over shows nothing');
      t.ok(await covered.evaluate(el => el.getBoundingClientRect().width > 0), 'but still holds the column open');

      // The rows say what the number is, so nothing has to preface them
      t.equal(await documents.locator('.cavil-notice-summary').count(), 0, 'and nothing prefaces the list');

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

    // The common case in production: a column no row fills would read as missing data
    await t.test('a package Cavil recognises completely just lists its documents', async t => {
      await page.goto(`${url}/reviews/details/2`);
      const clean = page.locator('#legal-documents');
      await clean.waitFor();

      t.equal(await clean.locator('.legal-document-item').count(), 2, 'both documents are listed');
      t.match(await clean.innerText(), /COPYING.*14 lines.*LICENSE.*1 line/s, 'each with nothing but its size');
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
