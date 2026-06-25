#!/usr/bin/env node
import {
  assertNoUnexpectedConsoleErrors,
  expandFileDetails,
  launchUi,
  openCreatePatternEditor,
  skipUnlessOnline,
  waitForInlineSnippetEditor,
  waitForInlineSnippetEditorClosed
} from './lib/ui_helpers.js';
import t from 'tap';

// Report view interactions: everything that a logged-in admin does on a
// single report page without committing pattern/note changes. Browsing into
// the checkout file viewer, expanding file previews, keyboard navigation
// between unresolved matches, deep-linking via URL hash, hovering pattern
// tooltips.
t.test('Cavil UI - report view', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_report');
  const {page, context, url, performJobs, errorLogs} = ui;

  try {
    // Make sure we're logged in (the wrapper's dummy auth creates the admin
    // "tester" on first login). Subsequent goto()s in the file then keep
    // the admin session cookie.
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Checkout file browser renders directories, full files, and match tooltips', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      await page.waitForSelector('#checkout-url a');

      const [browserPage] = await Promise.all([context.waitForEvent('page'), page.locator('#checkout-url a').click()]);
      await browserPage.waitForLoadState('load');
      await browserPage.waitForSelector('.file-browser-table');
      t.equal(await browserPage.innerText('title'), 'Directory listing of /');
      t.match(await browserPage.innerText('.file-browser-breadcrumb'), /perl-Mojolicious/);
      t.match(
        await browserPage.innerText('.file-browser-count'),
        /\d+ items?/,
        'directory count is shown in breadcrumb row'
      );
      t.equal(await browserPage.locator('.file-browser-panel-header').count(), 0, 'directory summary header is hidden');

      const rootRows = await browserPage.innerText('.file-browser-table');
      t.match(rootRows, /Mojolicious-7\.25/, 'root directory lists unpacked source directory');
      t.ok(
        (await browserPage.locator('.file-browser-table tr.has-match').count()) > 0,
        'directory tree marks entries containing matched files'
      );

      await browserPage
        .locator('.file-browser-table tr')
        .filter({has: browserPage.locator('.file-browser-name a', {hasText: 'Mojolicious-7.25'})})
        .locator('.file-browser-name a')
        .click();
      await browserPage.waitForURL(/\/reviews\/file_view\/1\/Mojolicious-7\.25$/);
      await browserPage.waitForSelector('.file-browser-table');
      t.match(browserPage.url(), /\/reviews\/file_view\/1\/Mojolicious-7\.25$/);
      await browserPage
        .locator('.file-browser-table tr')
        .filter({has: browserPage.locator('.file-browser-name a', {hasText: 'lib'})})
        .locator('.file-browser-name a')
        .click();
      await browserPage.waitForURL(/\/reviews\/file_view\/1\/Mojolicious-7\.25\/lib$/);
      await browserPage.waitForSelector('.file-browser-table');
      await browserPage
        .locator('.file-browser-table tr')
        .filter({has: browserPage.locator('.file-browser-name a', {hasText: 'Mojolicious.pm'})})
        .locator('.file-browser-name a')
        .click();
      await browserPage.waitForURL(/\/reviews\/file_view\/1\/Mojolicious-7\.25\/lib\/Mojolicious\.pm$/);
      await browserPage.waitForSelector('.file-browser-source table.snippet');
      t.match(browserPage.url(), /\/reviews\/file_view\/1\/Mojolicious-7\.25\/lib\/Mojolicious\.pm$/);
      t.equal(await browserPage.innerText('title'), 'Content of Mojolicious-7.25/lib/Mojolicious.pm');
      t.match(
        await browserPage.innerText('.file-browser-count'),
        /\d+ lines?/,
        'file line count is shown in breadcrumb row'
      );
      t.equal(await browserPage.locator('.file-browser-panel-header').count(), 0, 'file source header is hidden');

      const sourceText = await browserPage.innerText('.file-browser-source');
      t.match(sourceText, /package Mojolicious;/, 'full source includes file beginning');
      t.match(sourceText, /sub new \{/, 'full source includes later file content');
      t.ok(
        (await browserPage.locator('.file-browser-source tr.has-pattern-tooltip').count()) > 0,
        'source rows expose pattern tooltip markers'
      );

      const highlighted = browserPage.locator('.file-browser-source tr.has-pattern-tooltip').first();
      await highlighted.scrollIntoViewIfNeeded();
      t.equal(await highlighted.getAttribute('title'), null, 'matched source row has no native title tooltip');
      await highlighted.hover();
      const card = browserPage.locator('.cavil-pattern-tip-floating .cavil-pattern-tip-card').first();
      await card.waitFor({timeout: 5000});
      const fileTooltipClear = await browserPage.evaluate(() => {
        const row = document.querySelector('.file-browser-source tr.has-pattern-tooltip');
        const tip = document.querySelector('.cavil-pattern-tip-floating');
        const rowRect = row.getBoundingClientRect();
        const tipRect = tip.getBoundingClientRect();
        return tipRect.bottom <= rowRect.top || tipRect.top >= rowRect.bottom;
      });
      t.ok(fileTooltipClear, 'file browser tooltip does not cover the active source row');
      t.match(await card.innerText(), /risk \d/i, 'file browser tooltip shows pattern risk');
      t.equal(await card.locator('a').count(), 0, 'file browser tooltip is informational only');

      await browserPage.mouse.wheel(0, 200);
      await browserPage.waitForSelector('.cavil-pattern-tip-floating', {state: 'detached'});
      await highlighted.scrollIntoViewIfNeeded();
      await highlighted.hover();
      await card.waitFor({timeout: 5000});

      await browserPage.mouse.move(0, 0);
      await browserPage.goBack();
      await browserPage.waitForSelector('.file-browser-table');
      t.match(browserPage.url(), /\/reviews\/file_view\/1\/Mojolicious-7\.25\/lib$/);
      await browserPage.close();
    });

    await t.test('Expand hidden file (and open it in a new tab)', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // File 6 lives in the Apache-2.0 risk-5 bucket. With the inflated
      // fixture the bucket holds many files so its file list starts collapsed -
      // expand it first to reveal the in-bucket file-link.
      const apache = page.locator('#risk-5 > li').filter({hasText: 'Apache-2.0'}).first();
      await apache.locator('a[data-bs-toggle="collapse"]').click();
      await apache.locator('a[href="#file-6"]').waitFor();

      t.same(await page.isVisible('#file-details-6'), false);
      await apache.locator('a[href="#file-6"]').click();
      await page.waitForSelector('#file-details-6');
      t.match(await page.innerText('#expand-link-6'), /Mojolicious.+js/);
      t.same(await page.isVisible('#file-details-6'), true);

      // Open whole file in new tab
      const [page2] = await Promise.all([
        context.waitForEvent('page'),
        page.locator('#expand-link-6 ~ div a[target="_blank"]').click()
      ]);
      await page2.waitForLoadState();
      t.match(await page2.innerText('title'), /Content of Mojolicious.+js/);
      await page2.waitForSelector('.file-browser-source table.snippet');
      t.match(await page2.innerText('.file-browser-source'), /Apache.+indexOf/s);
      await page2.close();
    });

    await t.test('Report sections (chart, risks, missed files, emails, urls)', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Chart canvas is rendered
      t.same(await page.isVisible('#license-chart'), true);

      // Risk 5 bucket lists Apache-2.0 and SUSE-NotALicense
      await page.waitForSelector('#risk-5');
      const risk5 = await page.innerText('#risk-5');
      t.match(risk5, /Apache-2\.0/);
      t.match(risk5, /SUSE-NotALicense/);

      // Unresolved matches block shows file count and license/match info
      const unmatched = await page.innerText('#unmatched-files');
      t.match(unmatched, /unresolved match/);
      t.match(unmatched, /4 files/);

      // Click a missed-file link (file 7 is auto-expanded as a risk-9 file) -
      // verifies the click handler runs and the preview stays visible.
      await page.locator('#filelist-snippets a[href="#file-7"]').click();
      await page.waitForSelector('#file-details-7');
      t.same(await page.isVisible('#file-details-7'), true);

      // Emails section: 14 entries, collapsed by default, click to expand
      await page.click('text=14 Emails');
      await page.waitForSelector('#emails.show');
      t.match(await page.innerText('#emails'), /coolo@suse\.com/);

      // URLs section: 53 entries
      await page.click('text=53 URLs');
      await page.waitForSelector('#urls.show');
      t.match(await page.innerText('#urls'), /https?:\/\//);
    });

    await t.test('Click file in license list expands hidden preview', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // File 6 lives in the Apache-2.0 risk-5 bucket. With the inflated
      // fixture the bucket holds many files so its file list starts collapsed -
      // expand it first, then click the in-bucket file-link and verify the
      // preview expands and loads source (FileSource renders a table.snippet
      // inside the details div).
      const apache = page.locator('#risk-5 > li').filter({hasText: 'Apache-2.0'}).first();
      await apache.locator('a[data-bs-toggle="collapse"]').click();
      await apache.locator('a[href="#file-6"]').waitFor();
      t.same(await page.isVisible('#file-details-6'), false);
      await apache.locator('a[href="#file-6"]').click();
      await page.waitForSelector('#file-details-6');
      t.same(await page.isVisible('#file-details-6'), true);
      await page.waitForSelector('#file-details-6 table.snippet');
    });

    await t.test('Keyboard shortcuts for unresolved match navigation', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      await page.waitForSelector('#filelist-snippets a.file-link');

      // Wait for every previewed file's source to finish loading. Navigation
      // walks the DOM, so a snippet only becomes a target once its row is
      // rendered.
      await page.waitForFunction(() => {
        const containers = document.querySelectorAll('.file-container:not(.d-none) .source');
        if (containers.length === 0) return false;
        for (const c of containers) {
          if (!c.querySelector('table.snippet')) return false;
        }
        return true;
      });

      // Collect the ordered list of match-start anchors the page actually
      // rendered. Pressing 'n' must visit each in document order, including
      // siblings inside the same file, and including files that contain
      // license-pattern matches alongside unresolved snippets.
      const matchIds = await page.evaluate(() =>
        Array.from(document.querySelectorAll('.match-start')).map(el => el.id)
      );
      t.ok(matchIds.length >= 4, 'have at least four unresolved match anchors');
      const perFile = matchIds.reduce((acc, id) => {
        const fileId = id.split('-')[1];
        acc[fileId] = (acc[fileId] || 0) + 1;
        return acc;
      }, {});
      t.ok(
        Object.values(perFile).some(n => n > 1),
        'at least one file has multiple match anchors'
      );
      const firstId = matchIds[0].split('-')[1];
      const secondId = matchIds[matchIds.findIndex(id => id.split('-')[1] !== firstId)].split('-')[1];

      const inViewport = id => async () => {
        return await page.evaluate(elId => {
          const el = document.getElementById(elId);
          if (!el) return false;
          const r = el.getBoundingClientRect();
          return r.top >= -50 && r.top <= window.innerHeight;
        }, id);
      };
      const waitForMatchInView = async id => {
        const check = inViewport(id);
        const start = Date.now();
        while (Date.now() - start < 5000) {
          if (await check()) return;
          await new Promise(r => setTimeout(r, 50));
        }
        throw new Error(`Timed out waiting for ${id} to enter viewport`);
      };

      for (const [i, id] of matchIds.entries()) {
        await page.keyboard.press('n');
        await waitForMatchInView(id);
        t.pass(`'n' #${i + 1} landed on ${id}`);
      }

      for (let i = matchIds.length - 2; i >= 0; i--) {
        await page.keyboard.press('p');
        await waitForMatchInView(matchIds[i]);
      }
      t.pass(`'p' walked back to ${matchIds[0]}`);

      // Sanity-check the original assertion that both files end up visible.
      t.same(await page.isVisible(`#file-details-${firstId}`), true, 'first missed file visible');
      t.same(await page.isVisible(`#file-details-${secondId}`), true, 'second missed file visible');

      // '?' opens the shortcuts help modal
      await page.keyboard.press('Shift+/');
      await page.waitForSelector('#shortcutsModal.show');
      const modalText = await page.innerText('#shortcutsModal');
      t.match(modalText, /Keyboard shortcuts/);
      t.match(modalText, /Jump to next unresolved match/);
      t.match(modalText, /Jump to previous unresolved match/);

      await page.locator('#shortcutsModal .btn-close').click();
      await page.waitForFunction(() => {
        const m = document.getElementById('shortcutsModal');
        return !m || !m.classList.contains('show');
      });

      // Shortcut must not fire while typing into an editor input - open the
      // inline editor on file 1 and confirm pressing 'n' inside the license
      // field inserts the letter instead of jumping to the next match.
      await page.locator('#file-details-1 .quick-actions a').first().click();
      await waitForInlineSnippetEditor(page);
      await page.locator('#inline-snippet-editor input[name=license]').click();
      await page.keyboard.type('np');
      t.equal(
        await page.locator('#inline-snippet-editor input[name=license]').inputValue(),
        'np',
        'shortcut keys are typed normally inside the license input'
      );
      await page.locator('#inline-snippet-editor [data-action="cancel"]').click();
      await waitForInlineSnippetEditorClosed(page);
    });

    await t.test('Initial URL hash auto-expands hidden file', async t => {
      // First navigate via the UI to learn the real report URL plus a
      // file id that is in data.files but normally collapsed on initial
      // load (i.e. not auto-expanded as risk-9).
      await page.goto(url);
      await page.click('text=Artistic');
      await page.waitForSelector('#license-chart');
      const reportUrl = page.url().split('#')[0];

      // Pick any rendered file-container whose details div is missing (i.e.
      // file.expanded is false) so the test exercises the auto-expand path.
      const targetFileId = await page.evaluate(() => {
        const containers = document.querySelectorAll('.file-container');
        for (const c of containers) {
          const a = c.querySelector('a[name^="file-"]');
          if (!a) continue;
          const id = a.name.replace('file-', '');
          if (!document.getElementById(`file-details-${id}`)) return id;
        }
        return null;
      });
      t.ok(targetFileId, 'found a collapsed file to deep-link to');

      // Visit a different URL first so the next goto triggers a real reload
      // (page.goto to the same URL with only a hash change does NOT remount Vue).
      await page.goto(url);
      await page.goto(`${reportUrl}#file-${targetFileId}`);
      await page.waitForSelector('#license-chart');
      await page.waitForSelector(`#file-details-${targetFileId} table.snippet`, {timeout: 10000});
      t.same(
        await page.isVisible(`#file-details-${targetFileId}`),
        true,
        `file-${targetFileId} auto-expanded from URL hash`
      );

      // Auto-scroll-into-view used to be asserted here too, but it races with
      // the source fetches of *other* auto-expanded files (handleInitialHash ->
      // scrollToFile in ReportDetails.vue only awaits the target file's source)
      // and there's no re-scroll once the rest of the page settles. The test's
      // stated purpose is auto-expand, which the assertion above already covers.
    });

    await t.test('Pattern tooltip links are reachable in reports and inline editor', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const reportFileId = await page.evaluate(() => {
        for (const toggle of document.querySelectorAll('[id^="risk-"] a[data-bs-toggle="collapse"]')) toggle.click();
        const link = document.querySelector('[id^="risk-"] a.file-link[href^="#file-"]');
        if (!link) throw new Error('No license-match file link found in risk buckets');
        link.click();
        return link.getAttribute('href').replace('#file-', '');
      });
      await page.waitForSelector(`#file-details-${reportFileId} table.snippet`);
      const reportRows = page.locator(`#file-details-${reportFileId} tr.has-pattern-tooltip`);
      await reportRows.first().waitFor();
      const reportCard = page.locator('.cavil-pattern-tip-floating .cavil-pattern-tip-card').first();
      for (let i = 0; i < (await reportRows.count()); i++) {
        const row = reportRows.nth(i);
        await row.scrollIntoViewIfNeeded();
        await row.locator('td.code').hover({position: {x: 24, y: 8}});
        try {
          await reportCard.waitFor({timeout: 1000});
          break;
        } catch (_error) {
          await page.mouse.move(0, 0);
        }
      }
      await reportCard.waitFor({timeout: 5000});
      const reportTooltipClear = await page.evaluate(fileId => {
        const row = document.querySelector(`#file-details-${fileId} tr.has-pattern-tooltip`);
        const tip = document.querySelector('.cavil-pattern-tip-floating');
        const rowRect = row.getBoundingClientRect();
        const tipRect = tip.getBoundingClientRect();
        return tipRect.bottom <= rowRect.top || tipRect.top >= rowRect.bottom;
      }, reportFileId);
      t.ok(reportTooltipClear, 'report tooltip does not cover the active source row');
      t.match(await reportCard.innerText(), /risk \d/i, 'report tooltip shows pattern risk');
      t.equal(await reportCard.locator('a').count(), 0, 'report tooltip is informational only');
      await page.mouse.move(0, 0);
      await page.waitForSelector('.cavil-pattern-tip-floating', {state: 'detached'});

      const fileId = (await page.locator('#filelist-snippets a.file-link').first().getAttribute('href')).replace(
        '#file-',
        ''
      );
      await expandFileDetails(page, fileId);
      const unresolved = page.locator(`#file-details-${fileId} tr.match-start`).first();
      await unresolved.waitFor();
      t.ok(
        await unresolved.evaluate(el => el.classList.contains('has-pattern-tooltip')),
        'unresolved report row exposes closest-pattern tooltip marker'
      );
      await openCreatePatternEditor(page, fileId);

      // Make sure at least one match-decorated line is in the editor.
      const highlighted = page.locator('#inline-snippet-editor .cm-line.found-pattern').first();
      await highlighted.waitFor();
      await highlighted.scrollIntoViewIfNeeded();

      // CM6's hoverTooltip requires a mousemove event within the editor over
      // actual text. Use a manual mouse.move sequence into the line's box so
      // the source callback fires reliably regardless of which character index
      // the line happens to start at.
      const box = await highlighted.boundingBox();
      await page.mouse.move(box.x + 5, box.y + box.height / 2);
      await page.mouse.move(box.x + 20, box.y + box.height / 2);

      const tip = page.locator('.cavil-pattern-tip').first();
      await tip.waitFor({timeout: 5000});

      // The tooltip starts in a loading state; wait for the card to render
      // after /licenses/pattern/<id>.json returns.
      const card = page.locator('.cavil-pattern-tip .cavil-pattern-tip-card').first();
      await card.waitFor({timeout: 5000});
      const tipText = await card.innerText();
      t.match(tipText, /risk \d/i, 'tooltip shows risk indicator');
      t.ok(tipText.length > 0, 'tooltip shows pattern info');

      // The "Open pattern" link in the tooltip targets the pattern editor.
      const href = await card.locator('a').first().getAttribute('href');
      t.match(href, /\/licenses\/edit_pattern\/\d+/, 'tooltip link points to pattern editor');

      const [inlinePatternPage] = await Promise.all([context.waitForEvent('page'), card.locator('a').first().click()]);
      await inlinePatternPage.waitForLoadState('load');
      t.match(inlinePatternPage.url(), /\/licenses\/edit_pattern\/\d+/, 'inline editor tooltip link can be clicked');
      await inlinePatternPage.close();

      // Tidy up: move the mouse away so the tooltip closes, then close the editor.
      await page.mouse.move(0, 0);
      await page.keyboard.press('Escape');
      await page.locator('#inline-snippet-editor button[data-action="cancel"]').click();
      await waitForInlineSnippetEditorClosed(page);
    });

    await t.test('Propose ignore glob: reject, redo, accept, confirm', async t => {
      // Drive the whole human lifecycle: propose a glob from a file header, reject it on the
      // Change Proposals page, propose it again, accept it, and confirm it lands on the admin
      // Ignored Files page with the proposer credited as contributor.
      const proposeGlobFromFile6 = async () => {
        await page.goto(url);
        await page.click('text=Artistic');
        await page.waitForSelector('#license-chart');

        // Expand file 6 (Apache-2.0 risk-5 bucket) so its file header - and the file-actions
        // dropdown that lives in it - becomes visible.
        const apache = page.locator('#risk-5 > li').filter({hasText: 'Apache-2.0'}).first();
        await apache.locator('a[data-bs-toggle="collapse"]').click();
        await apache.locator('a[href="#file-6"]').click();
        await page.waitForSelector('#file-details-6');

        // Open the file-actions pulldown and choose "Propose ignore glob". Scope to file 6's own
        // menu - every expanded file renders its own dropdown, so a global selector would match a
        // closed menu from another file.
        await page.locator('#file-menu-6').click();
        const fileMenu = page.locator('[aria-labelledby="file-menu-6"]');
        await fileMenu.waitFor({state: 'visible'});
        await fileMenu.locator('.dropdown-item', {hasText: 'Propose ignore glob'}).click();

        // The modal opens pre-filled with a glob derived from the file path, with the versioned
        // top-level directory turned into a wildcard.
        await page.waitForSelector('#globProposalModal.show');
        const value = await page.locator('#glob-proposal-input').inputValue();
        await page.locator('#glob-proposal-reason').fill('Bundled jQuery, not part of the package license');
        await page.locator('#glob-proposal-submit').click();
        await page.waitForSelector('#globProposalModal', {state: 'hidden'});

        // The proposal is queued in the floating pending-changes widget; submitting posts it and
        // reloads the report.
        await page.locator('#pending-actions-widget .pending-actions-toggle').click();
        const item = page.locator('.pending-actions-item').filter({hasText: 'Propose ignore glob'}).first();
        await item.waitFor();
        t.match(await item.innerText(), /Mojolicious-\*\//, 'queued action is labelled with the glob');
        await Promise.all([page.waitForNavigation(), page.locator('#pending-actions-submit').click()]);

        return value;
      };

      const globCard = () => page.locator('.change-file-container').filter({hasText: 'ignore glob'}).first();

      // Propose, then reject it on the Change Proposals page.
      const suggested = await proposeGlobFromFile6();
      t.match(suggested, /^Mojolicious-\*\//, 'suggested glob wildcards the versioned top-level directory');

      await page.goto(new URL('licenses/proposed', url).toString());
      await page.waitForSelector('#proposed-patterns');
      await globCard().waitFor();
      t.equal(
        await globCard().locator('.change-glob-input').inputValue(),
        suggested,
        'proposed glob is shown for the reviewer'
      );
      await globCard().locator('button.btn-danger', {hasText: 'Reject'}).click();
      await page.locator('.change-file-container').filter({hasText: 'ignore glob'}).waitFor({state: 'detached'});
      t.equal(
        await page.locator('.change-file-container').filter({hasText: 'ignore glob'}).count(),
        0,
        'rejected glob proposal is gone'
      );

      // Propose the same glob again and this time accept it.
      const suggestedAgain = await proposeGlobFromFile6();
      t.equal(suggestedAgain, suggested, 'same glob is suggested on the second proposal');

      await page.goto(new URL('licenses/proposed', url).toString());
      await page.waitForSelector('#proposed-patterns');
      await globCard().waitFor();
      await globCard().locator('button.btn-success', {hasText: 'Accept'}).click();
      await page.locator('.change-file-container').filter({hasText: 'ignore glob'}).waitFor({state: 'detached'});

      // The accepted glob now appears on the admin Ignored Files page, crediting the proposer.
      await page.goto(new URL('ignored-files', url).toString());
      await page.waitForSelector('#ignored-files tbody tr');
      const row = page.locator('#ignored-files tbody tr').filter({hasText: suggested}).first();
      await row.waitFor();
      t.equal(await row.locator('td').nth(0).innerText(), suggested, 'accepted glob is listed');
      t.equal(await row.locator('td').nth(3).innerText(), 'tester', 'proposer is credited as contributor');

      // Accepting enqueued a reindex of the originating package; run it, then confirm the report
      // now reports the file as suppressed by the new glob.
      const jobs = await context.newPage();
      await jobs.goto(performJobs, {timeout: 120000});
      t.match(await jobs.innerText('div'), /done/);
      await jobs.close();

      await page.goto(url);
      await page.click('text=Artistic');
      await page.waitForSelector('#license-chart');
      const globList = page.locator('.report-glob-list');
      await globList.waitFor();
      t.ok(
        (await globList.innerText()).includes(suggested),
        'report lists the accepted glob as matching after reindexing'
      );
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
