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

      // The mark is what gets scanned, so it is the thing that has to share a column, including on a row
      // with nothing to mark
      const marks = await documents
        .locator('.legal-document-meter')
        .evaluateAll(els => els.map(el => Math.round(el.getBoundingClientRect().right)));
      t.equal(marks.length, 6, 'every row carries the mark');
      t.equal(new Set(marks).size, 1, 'and they right-align to one column');

      // The SPDX line resolves, the three lines of novel terms do not - and the report is otherwise clean,
      // which is exactly the case this number exists to surface. Absolute, not a percentage, so a small
      // clause inside a large recognised license body cannot round away to nothing.
      const license = rowFor('legal-docs-1.0/LICENSE');
      t.match(await license.innerText(), /1 of 4 lines/, 'one annotation, not two counts to compare');
      t.match(await rowFor('legal-docs-1.0/COPYING').innerText(), /1 of 120 lines/, 'and on a longer one');
      t.match(await rowFor('legal-docs-1.0/LICENSE.MIT').innerText(), /\s14 lines/, 'a covered file states its size');

      // The mark is the scanning cue now, so no weight is spent on making the count stand out
      t.equal(await license.locator('b').count(), 0, 'nothing in the row is emphasised');

      // A flex child with no text of its own stretches to the row and hangs from the top unless told to
      // sit on the baseline
      const offCentre = await license.evaluate(el => {
        const middle = selector => {
          const box = el.querySelector(selector).getBoundingClientRect();
          return box.top + box.height / 2;
        };
        return Math.abs(middle('.legal-document-tally') - middle('.legal-document-block'));
      });
      t.ok(offCentre <= 1.5, 'the mark sits on the annotation rather than above it');

      // The blocks fill for what Cavil recognised, so none at all is the document it could not read
      const filled = row => row.locator('.legal-document-block.is-covered').count();
      t.equal(await license.locator('.legal-document-block').count(), 5, 'the mark is five blocks');
      t.equal(await filled(rowFor('legal-docs-1.0/COPYING')), 1, '1 of 120 lines is barely any of the file');
      t.equal(await filled(rowFor('legal-docs-1.0/COPYRIGHT')), 0, 'a document that matched nothing fills none');
      t.equal(await filled(rowFor('legal-docs-1.0/LICENSE.enterprise')), 4, 'a clause on a stock body leaves four');
      t.equal(
        await license.locator('.legal-document-lines').getAttribute('title'),
        '1 of 4 lines recognised',
        'and hovering names what the blocks stand for'
      );

      const covered = rowFor('legal-docs-1.0/LICENSE.MIT');
      t.equal(await filled(covered), 5, 'a file Cavil read completely fills every block');
      t.equal(await covered.locator('.legal-document-block').count(), 5, 'rather than nothing at all');

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

    // Shares this fixture: ISC is only in vendor/helper, Zlib only in build files, MIT and Apache-2.0 are in
    // shipped code.
    await t.test('the license list says when a license is only in uninteresting places', async t => {
      const scoped = page.locator('.risk-license-item', {has: page.locator('.risk-license-scope')});
      t.equal(await scoped.count(), 2, 'exactly the licenses that never touch shipped code');
      const isc = scoped.filter({hasText: 'ISC'});
      t.match(await isc.locator('.risk-license-scope').innerText(), /^only in vendored files$/, 'vendored');
      const zlib = scoped.filter({hasText: 'Zlib'});
      t.match(await zlib.locator('.risk-license-scope').innerText(), /^only in build files$/, 'build files');

      // A location, not a verdict: a wrong "vendored" that read as "ignore this" would hide a real license
      t.notMatch((await scoped.allInnerTexts()).join('|'), /ignore|safe|skip/i, 'and never what to do about it');
    });

    // The common case in production: a column no row fills would read as missing data
    await t.test('a package Cavil recognises completely just lists its documents', async t => {
      await page.goto(`${url}/reviews/details/2`);
      const clean = page.locator('#legal-documents');
      await clean.waitFor();

      t.equal(await clean.locator('.legal-document-item').count(), 2, 'both documents are listed');
      t.match(await clean.innerText(), /COPYING.*14 lines.*LICENSE.*1 line/s, 'each with nothing but its size');
      // The mark is permanent now, so the vocabulary is learned once rather than appearing on bad packages
      t.equal(await clean.locator('.legal-document-meter').count(), 2, 'both rows still carry the mark');
      t.equal(await clean.locator('.legal-document-block.is-covered').count(), 10, 'filled, because both are read');
      t.equal(await clean.locator('.cavil-notice-summary').count(), 0, 'and no sentence explaining one');

      // With no mark to hang off, the annotations are what has to end in one column
      const tallies = await clean
        .locator('.legal-document-tally')
        .evaluateAll(els => els.map(el => Math.round(el.getBoundingClientRect().right)));
      t.equal(new Set(tallies).size, 1, 'a singular line count ends where the others do');
    });

    await page.goto(`${url}/reviews/details/1`);
    await page.locator('#legal-documents').waitFor();

    await t.test('a package with more documents than the preview can show all of them', async t => {
      await page.goto(`${url}/reviews/details/3`);
      const many = page.locator('#legal-documents');
      await many.waitFor();
      const toggle = many.locator('.list-more-toggle button');

      t.equal(await many.locator('.legal-document-item').count(), 10, 'the list opens on the first 10');
      t.equal(await many.locator('.cavil-notice-heading-note').count(), 0, 'with nothing left out');
      t.equal((await toggle.innerText()).trim(), 'Show 20 more', 'the rest is a click away');

      await toggle.click();
      await many.locator('.legal-document-item').nth(29).waitFor();
      t.equal(await many.locator('.legal-document-item').count(), 30, 'and all of them are listed');
      t.equal((await toggle.innerText()).trim(), 'Show top 10', 'the button collapses again');

      await toggle.click();
      await many.locator('.legal-document-item').nth(10).waitFor({state: 'detached'});
      t.equal(await many.locator('.legal-document-item').count(), 10, 'back to the first 10');
    });

    await page.goto(`${url}/reviews/details/1`);
    await page.locator('#legal-documents').waitFor();

    await t.test('a long packager notice is clamped until asked for', async t => {
      const notices = page.locator('#spec-legal-review-notices');
      const items = notices.locator('.cavil-notice-item');
      const toggle = notices.locator('.list-more-toggle button');

      // Read right after the comment, before the documents they are often about
      const before = await notices.evaluate(el => {
        const documents = document.querySelector('#legal-documents');
        return Boolean(el.compareDocumentPosition(documents) & Node.DOCUMENT_POSITION_FOLLOWING);
      });
      t.ok(before, 'the notices come before the legal documents');
      t.equal(await items.count(), 2, 'both notices are listed');
      t.equal(await items.nth(0).innerText(), 'The enterprise terms do not apply to this build', 'short one as is');
      t.equal(await toggle.count(), 1, 'only the long one has a toggle');
      t.equal((await toggle.innerText()).trim(), 'Show full notice (8 lines)', 'which says how long it is');
      const overflows = () => items.nth(1).evaluate(el => el.scrollHeight > el.clientHeight);
      t.ok(await overflows(), 'the end is cut off');

      await toggle.click();
      await notices.locator('.legal-review-notice-clamped').waitFor({state: 'detached'});
      t.notOk(await overflows(), 'all of it shows');
      t.equal((await toggle.innerText()).trim(), 'Show less', 'the button collapses again');

      await toggle.click();
      t.equal((await toggle.innerText()).trim(), 'Show full notice (8 lines)', 'and it is clamped again');
    });

    // Non-technical reviewers forget what a panel means, packagers forget the comment syntax
    await t.test('each panel explains itself in a dialog', async t => {
      const dialog = page.locator('.help-modal.show');
      const panels = [
        ['#review-information', 'Why this needs review', /Diff to closest match 573150\s+New licenses/],
        [
          '#spec-legal-review-notices',
          'Legal review notices from packagers',
          /legal-docs\.spec\s+# Legal-Review-Notice: /
        ],
        ['#legal-documents', 'Legal documents', /LICENSE\s+21 lines\s+NOTICE\s+8 of 14 lines/],
        ['#copied-files', 'Copied files', /legal-docs\.spec\s+%files\s+%license COPYING/],
        ['#report-license', 'License', /legal-docs\.spec\s+License: {2}GPL-2\.0-or-later\s+%package -n libfoo1/]
      ];
      for (const [id, title, example] of panels) {
        await page.locator(`${id} .cavil-notice-help-button`).click();
        await dialog.waitFor();
        t.equal(await dialog.locator('.help-modal-title').innerText(), title, `${title} opens its help`);
        t.match(await dialog.locator('.modal-body').innerText(), example, 'with an example');
        await dialog.locator('.btn-close').click();
        await dialog.waitFor({state: 'detached'});
        await page.locator('.modal-backdrop').waitFor({state: 'detached'});
        const focused = await page.evaluate(
          sel => document.activeElement.matches(sel),
          `${id} .cavil-notice-help-button`
        );
        t.ok(focused, 'and hands focus back to its button');
      }
    });

    // Indexing records a file only once something matched in it, so the document whose licence nobody has
    // a pattern for has no file id at all - and that is exactly where a reviewer has to start one.
    await t.test('a file nothing matched in can be picked line by line', async t => {
      await page.goto(`${url}/reviews/file_view/1/legal-docs.spec`);
      const table = page.locator('table.snippet');
      await table.waitFor();
      const rows = table.locator('tbody tr');

      const gutter = rows.nth(2).locator('.select-line-btn');
      t.equal(await gutter.getAttribute('title'), 'Start a selection here', 'the gutter says what it does');

      // Anchor, then let the pointer propose the rest: the range follows it, in either direction
      await gutter.click();
      t.equal(await table.locator('tr.line-anchor').count(), 1, 'the first click anchors one line');
      await rows.nth(5).hover();
      t.equal(await table.locator('tr.line-preview').count(), 4, 'the preview reaches the hovered line');
      await rows.nth(0).hover();
      t.equal(await table.locator('tr.line-preview').count(), 3, 'and back the other way, above the anchor');
      t.equal(await table.locator('tr.line-selected').count(), 0, 'nothing is decided until the second click');

      await rows.nth(5).hover();
      await rows.nth(5).locator('.select-line-btn').click();
      t.equal(await table.locator('tr.line-selected').count(), 4, 'the second click commits what was shown');
      t.equal(await table.locator('tr.line-preview').count(), 0, 'and the preview is done');

      // The gutter is on every line in every state, so a reviewer can start over from inside a range
      await rows.nth(4).hover();
      t.equal(await rows.nth(4).locator('.select-line-btn').count(), 1, 'a selected line still offers the gutter');

      // No file id to address, so the range is named by path
      const pen = table.locator('td.quick-actions a');
      t.equal(await pen.count(), 1, 'one button acts on the range');
      t.match(await pen.getAttribute('href'), /\/snippets\/from_path\/1\/legal-docs\.spec\?.*start=3&end=6/, 'by path');

      await pen.click();
      await page.locator('#inline-snippet-editor').waitFor({timeout: 10000});
      t.pass('the editor opens on a file indexing never recorded');

      // Creating the snippet returns its checksum, so the editor has the context that gates the
      // ignore, missing-license and no-legal-text actions - previously these only appeared after a
      // reload because a picked selection reached the editor with no hash.
      await page.locator('#inline-snippet-editor [data-action="propose-missing"]').waitFor({state: 'attached'});
      t.equal(
        await page.locator('#inline-snippet-editor [data-action="propose-missing"]').count(),
        1,
        'the Missing License action is offered on a freshly picked selection'
      );
      t.equal(
        await page.locator('#inline-snippet-editor [data-action="mark-non-license"]').count(),
        1,
        'and so is No Legal Text'
      );

      await page.locator('#inline-snippet-editor [data-action="cancel"]').click();
    });

    await page.goto(`${url}/reviews/details/1`);
    await page.locator('#legal-documents').waitFor();

    await t.test('nothing grades the declared license', async t => {
      const license = page.locator('#pkg-declarations');
      t.match(await license.innerText(), /MIT/, 'the declared license is shown as the plain value');
      t.notMatch(await license.innerText(), /declared|confirming|found in the code/i, 'with no annotation');
      t.equal(await page.locator('#declaration-note').count(), 0, 'and no annotation element at all');
    });

    // Only the package as a whole is judged, a file copied through a macro Cavil cannot resolve would make any
    // per-document marking a guess
    await t.test('the copied files say when no license text is copied into the package', async t => {
      const copied = page.locator('#copied-files');
      t.match(await copied.innerText(), /%license\s+no license text copied/, 'the gap is named');
      t.match(await copied.locator('[data-no-license-text]').getAttribute('class'), /badge-info/, 'as an annotation');
      t.notMatch(await copied.getAttribute('class'), /warning/, 'while the panel itself stays calm');
      t.notMatch(await page.locator('#legal-documents').innerText(), /copied/i, 'and no document is marked');

      await page.goto(`${url}/reviews/details/2`);
      await copied.waitFor();
      t.match(await copied.innerText(), /%license\s+COPYING/, 'a package that copies one lists it');
      t.equal(await copied.locator('[data-no-license-text]').count(), 0, 'with nothing else to say');
    });

    // Reviewers look for these on every report, a slot that vanishes when empty makes them keep searching
    await t.test('what the package does not have is answered where it would be', async t => {
      let patch = {};
      await page.route('**/reviews/meta/2', async route => {
        const response = await route.fetch();
        await route.fulfill({response, json: {...(await response.json()), ...patch}});
      });
      const load = async (overrides, ready) => {
        patch = overrides;
        await page.goto(`${url}/reviews/details/2`);
        await page.locator(ready).waitFor();
      };
      const notices = page.locator('#spec-legal-review-notices');
      const documents = page.locator('#legal-documents');
      const copied = page.locator('#copied-files');
      const note = panel => panel.locator('.cavil-notice-heading-note').innerText();

      const empty = {
        legal_review_notices: [],
        legal_documents: {documents: [], dropped: 0},
        copied_files: {'%doc': [], '%license': ['COPYING']}
      };
      await load(empty, '#legal-documents');
      t.equal(await note(notices), 'None', 'no packager notice');
      t.equal(await notices.locator('.cavil-notice-list').count(), 0, 'in a single line');
      t.equal(await note(documents), 'None', 'no legal documents');
      t.equal(await documents.locator('.cavil-notice-list').count(), 0, 'in a single line too');
      t.match(await copied.innerText(), /%doc\s+none/, 'no %doc files');

      t.equal(await notices.locator('.cavil-notice-help-button').count(), 1, 'the empty slot explains itself too');

      await load({...empty, legal_documents: null}, '#copied-files');
      t.equal(await documents.count(), 0, 'documents not computed yet are not claimed to be absent');

      // Only what the format can carry has a slot, so a recipe never seems to be missing a notice or %license
      for (const format of ['kiwi', 'debian']) {
        const declarations = [{format, file: 'config', name: 'pkg', license: null, license_html: null, spdx: false}];
        await load({...empty, declarations}, '#legal-documents');
        t.equal(await notices.count(), 0, `${format} has no notices slot`);
        t.equal(await copied.count(), 0, `${format} has no copied files slot`);
        t.equal(await note(documents), 'None', `${format} still answers for legal documents`);
      }
      const declarations = [{format: 'dockerfile', file: 'Dockerfile', name: 'pkg', license: null, license_html: null}];
      await load({...empty, declarations}, '#spec-legal-review-notices');
      t.equal(await note(notices), 'None', 'a Dockerfile can carry a notice');
      t.equal(await copied.count(), 0, 'but copies no files');

      await page.unroute('**/reviews/meta/2');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    await ui.teardown();
    delete process.env.JS_UI_FIXTURES;
  }
});
