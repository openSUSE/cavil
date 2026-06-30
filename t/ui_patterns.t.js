#!/usr/bin/env node
import {
  assertNoUnexpectedConsoleErrors,
  expandFileDetails,
  fillInlinePatternBasics,
  inlineEditorDoc,
  launchUi,
  openAccountMenu,
  openCreatePatternEditor,
  replaceInlineEditorDoc,
  skipUnlessOnline,
  waitForInlineSnippetEditor,
  waitForInlineSnippetEditorClosed
} from './lib/ui_helpers.js';
import t from 'tap';

// Pattern + snippet workflows: every interaction that mutates pattern state
// (create, propose, batch queue/dismiss/edit, ignore, accept review, manual
// reindex, classify-snippets page, Vue pattern editor pages, license inline
// editor, pattern performance). The contributor-role snippet editor layout
// check rounds off the file because it exercises the same inline editor UI
// from a different angle.
t.test('Cavil UI - pattern workflows', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_patterns');
  const {page, context, url, performJobs, errorLogs} = ui;

  try {
    // Establish the admin session (dummy auth picks up "tester" on first login).
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Create pattern from report match', async t => {
      await page.goto(url);
      await page.waitForSelector('#open-reviews tbody > tr:nth-child(2)');
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Use menu to select a pattern (the action line shifts after each extend, so
      // use a position-stable selector rooted at the file's source container).
      const actionTrigger = '#file-details-1 a[data-bs-toggle="dropdown"]';
      const actionMenuItem = label => `#file-details-1 .dropdown-menu :has-text("${label}")`;
      await page.locator(actionTrigger).click();
      await page.locator(actionMenuItem('Extend one line above')).click();
      await page.locator(actionTrigger).click();
      await page.locator(actionMenuItem('Extend one line below')).click();
      await openCreatePatternEditor(page, 1, {triggerSelector: actionTrigger});

      // Modal opens with the snippet editor instead of navigating away
      await waitForInlineSnippetEditor(page);
      // Inline editor hides the source-file/package origin line (only the page version shows it).
      t.notMatch(await page.innerText('#inline-snippet-editor'), /The example shown here is from the file/);

      // Fill the pattern metadata right in the inline editor
      await fillInlinePatternBasics(page, 'Made-Up-License-1.0');
      await page.locator('#inline-snippet-editor input[name="trademark"]').check();
      await page.locator('#inline-snippet-editor input[name="cla"]').check();
      await page.locator('#inline-snippet-editor input[name="eula"]').check();

      // Queue the create-pattern action (editor closes, indicator + widget appear)
      await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').click();
      await waitForInlineSnippetEditorClosed(page);
      await page.waitForSelector('#pending-actions-widget');
      t.match(await page.innerText('#pending-actions-widget'), /Pending changes/);

      // Expand the widget and submit the batch
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      t.match(await page.innerText('#pending-actions-widget'), /Made-Up-License-1.0/);
      const [decisionResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#pending-actions-submit').click()
      ]);
      t.equal(decisionResp.status(), 200);

      // Reload triggers automatically after success; then run reindex
      await page.waitForLoadState('load');
      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      t.match(await page.innerText('ul#risk-3 li'), /Made-Up-License-1.0/);

      // Standalone pattern edit page still works (page-mode SnippetEditor)
      await page.click('text=Licenses');
      t.equal(await page.innerText('title'), 'List licenses');
      await page.click('text=Made-Up-License-1.0');
      t.equal(await page.innerText('title'), 'License details of Made-Up-License-1.0');

      // Flags ticked in the inline editor are persisted and rendered as chips
      await page.waitForSelector('#license-details .license-pattern-card .license-chip-flag');
      const flagChips = await page.locator('.license-chip-flag').allInnerTexts();
      t.ok(flagChips.includes('Trademark'), 'Trademark flag chip rendered');
      t.ok(flagChips.includes('CLA'), 'CLA flag chip rendered');
      t.ok(flagChips.includes('EULA'), 'EULA flag chip rendered');
    });

    await t.test('Propose pattern: CLA/EULA flow through proposals page to accepted pattern', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const href = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = href.replace('#file-', '');
      await expandFileDetails(page, fileId);

      // Propose a pattern (Made-Up-License-1.0 at risk 3 was registered in the previous
      // subtest, satisfying propose-pattern's license+risk existence requirement)
      await openCreatePatternEditor(page, fileId);
      await fillInlinePatternBasics(page, 'Made-Up-License-1.0');
      await page.locator('#inline-snippet-editor input[name="cla"]').check();
      await page.locator('#inline-snippet-editor input[name="eula"]').check();
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-pattern"]').click();
      await waitForInlineSnippetEditorClosed(page);

      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      const [proposeResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#pending-actions-submit').click()
      ]);
      t.equal(proposeResp.status(), 200, 'propose-pattern submission succeeds');

      // Proposal arrives on the change proposals page with CLA/EULA pre-checked
      await page.goto(`${url}/licenses/proposed`);
      t.equal(await page.innerText('title'), 'Change Proposals');
      await page.waitForSelector('#proposed-patterns .change-container');
      const proposal = page.locator('#proposed-patterns .change-container').first();
      const claCheckbox = proposal.locator('.form-check', {hasText: 'CLA'}).locator('input[type=checkbox]');
      const eulaCheckbox = proposal.locator('.form-check', {hasText: 'EULA'}).locator('input[type=checkbox]');
      t.equal(await claCheckbox.isChecked(), true, 'CLA checkbox pre-checked in proposal row');
      t.equal(await eulaCheckbox.isChecked(), true, 'EULA checkbox pre-checked in proposal row');

      // Accept the proposal and capture the resulting pattern id
      const [acceptResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        proposal.locator('button.btn-success', {hasText: 'Accept'}).click()
      ]);
      t.equal(acceptResp.status(), 200, 'accept request succeeds');
      const acceptBody = await acceptResp.json();
      const patternId = acceptBody?.results?.[0]?.id;
      t.ok(patternId, 'accept response carries the new pattern id');

      // Drain the reindex jobs the accept queued so later subtests see a settled report
      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();

      // The created pattern's own editor page must show CLA/EULA as set
      await page.goto(`${url}/licenses/edit_pattern/${patternId}`);
      await page.waitForSelector('#edit-pattern input[name=cla]');
      t.equal(await page.locator('#edit-pattern input[name=cla]').isChecked(), true, 'CLA checked on pattern editor');
      t.equal(await page.locator('#edit-pattern input[name=eula]').isChecked(), true, 'EULA checked on pattern editor');
    });

    await t.test('Batch: queue multiple actions, dismiss one, submit the rest', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Find two unresolved-match files from the missed-files list
      const hrefs = await page
        .locator('#filelist-snippets a.file-link')
        .evaluateAll(els => els.slice(0, 2).map(e => e.getAttribute('href')));
      t.equal(hrefs.length, 2, 'have at least two unresolved-match files');
      const fileA = hrefs[0].replace('#file-', '');
      const fileB = hrefs[1].replace('#file-', '');

      // Make sure both files are expanded (some are auto-expanded as risk-9 already)
      await expandFileDetails(page, fileA);
      await expandFileDetails(page, fileB);

      // Helper: queue a create-pattern via the inline editor. A file can host multiple
      // risk-9 dropdowns; bypass the dropdown UI entirely and invoke the
      // matching item handler directly so we don't depend on Bootstrap's menu
      // animation/positioning settling between iterations.
      const queueAction = async (fileId, licenseName) => {
        await openCreatePatternEditor(page, fileId);
        await fillInlinePatternBasics(page, licenseName);
        await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').click();
        await waitForInlineSnippetEditorClosed(page);
      };

      // Names start with "Z" so they sort after Made-Up-License-1.0 in alphabetised
      // risk lists - downstream tests assert against the first li.
      await queueAction(fileA, 'Zzz-Batch-License-A');
      await queueAction(fileB, 'Zzz-Batch-License-B');

      // Widget shows both queued actions
      await page.waitForSelector('#pending-actions-widget');
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      t.equal(await page.locator('#pending-actions-widget .pending-actions-item').count(), 2);
      t.match(await page.innerText('#pending-actions-widget'), /Zzz-Batch-License-A/);
      t.match(await page.innerText('#pending-actions-widget'), /Zzz-Batch-License-B/);

      // Dismiss the first action via its trash button
      await page
        .locator('#pending-actions-widget .pending-actions-item')
        .first()
        .locator('button[title="Remove from batch"]')
        .click();
      t.equal(await page.locator('#pending-actions-widget .pending-actions-item').count(), 1);
      t.notMatch(await page.innerText('#pending-actions-widget'), /Zzz-Batch-License-A/);

      // Submit the remaining action
      const [decisionResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#pending-actions-submit').click()
      ]);
      t.equal(decisionResp.status(), 200);

      // Reload + reindex; only the surviving license should show up
      await page.waitForLoadState('load');
      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();
      await page.goto(url);
      await page.click('text=Artistic');
      await page.waitForSelector('#license-chart');
      const risk3 = await page.innerText('ul#risk-3');
      t.match(risk3, /Zzz-Batch-License-B/);
      t.notMatch(risk3, /Zzz-Batch-License-A/);
    });

    await t.test('Batch: server-side error surfaces per action', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Take the first remaining unresolved match
      const href = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = href.replace('#file-', '');
      await expandFileDetails(page, fileId);

      // Bypass the Bootstrap dropdown UI and trigger the matching item directly
      await openCreatePatternEditor(page, fileId);

      // Replace the CodeMirror contents so the proposed pattern cannot match the
      // original snippet text (triggers the server's pattern_matches guard)
      await replaceInlineEditorDoc(page, 'zzz nothing here matches the actual snippet zzz');

      await fillInlinePatternBasics(page, 'Error-Test-License');

      // Use the propose-pattern path - it runs the pattern_matches validation.
      // For admin+contributor users, propose-pattern lives in the shared
      // More actions dropdown.
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-pattern"]').click();
      await waitForInlineSnippetEditorClosed(page);

      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      const [decisionResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#pending-actions-submit').click()
      ]);
      t.equal(decisionResp.status(), 400);

      // Action stays queued in the error state with the server's message
      await page.waitForSelector('#pending-actions-widget .pending-actions-item.state-error');
      t.match(await page.innerText('#pending-actions-widget'), /License pattern does not match/);
      // Page must not have reloaded (widget still mounted, action still present)
      t.equal(await page.locator('#pending-actions-widget .pending-actions-item').count(), 1);

      // Clean up so the next test starts with an empty queue
      await page.locator('#pending-actions-widget button[title="Clear all"]').click();
    });

    await t.test('Batch: edit a failed action and resubmit', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const href = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = href.replace('#file-', '');
      await expandFileDetails(page, fileId);

      await openCreatePatternEditor(page, fileId);

      // Capture the original snippet text so we can restore it during edit
      const originalSnippetText = await inlineEditorDoc(page);
      t.ok(originalSnippetText.length > 0, 'captured original snippet text');

      // First pass: queue a propose-pattern with a deliberately bad pattern
      await replaceInlineEditorDoc(page, 'zzz nothing here matches the actual snippet zzz');
      await fillInlinePatternBasics(page, 'Edit-Recovery-License');
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-pattern"]').click();
      await waitForInlineSnippetEditorClosed(page);

      // Submit and confirm the validation error puts the action into error state
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      const [decisionResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#pending-actions-submit').click()
      ]);
      t.equal(decisionResp.status(), 400);
      await page.waitForSelector('#pending-actions-widget .pending-actions-item.state-error');
      t.match(await page.innerText('#pending-actions-widget'), /Edit-Recovery-License/);

      // Click Edit on the failed action - the inline editor re-opens with the prior data
      await page.locator('#pending-actions-widget button[data-action-control="edit"]').click();
      await waitForInlineSnippetEditor(page);

      // Verify the form was pre-filled with the failed action's data
      t.equal(
        await page.inputValue('#inline-snippet-editor input[name=license]'),
        'Edit-Recovery-License',
        'license pre-filled from failed action'
      );
      t.equal(
        await page.inputValue('#inline-snippet-editor select[name="risk"]'),
        '3',
        'risk pre-filled from failed action'
      );
      const cmTextInEdit = await inlineEditorDoc(page);
      t.match(cmTextInEdit, /zzz nothing here matches/, 'pattern pre-filled from failed action');

      // Restore the matchable snippet text so the resubmission passes validation
      await replaceInlineEditorDoc(page, originalSnippetText);

      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-pattern"]').click();
      await waitForInlineSnippetEditorClosed(page);

      // The edit must REPLACE the original entry, not append a new one
      const countAfterEdit = await page.locator('#pending-actions-widget .pending-actions-item').count();
      t.equal(countAfterEdit, 1, 'edited action replaces failed one (queue still has 1 item)');
      t.notMatch(
        await page.innerText('#pending-actions-widget'),
        /state-error|circle-exclamation/,
        'no error state remains after successful edit'
      );

      // Submit the edited action - it must now succeed and reload the page
      await Promise.all([page.waitForURL(/\/reviews\/details\//), page.locator('#pending-actions-submit').click()]);
      await page.waitForSelector('#license-chart');

      // Make sure the queue is empty for any later subtests
      if (await page.isVisible('#pending-actions-widget button[title="Clear all"]')) {
        await page.locator('#pending-actions-widget button[title="Clear all"]').click();
      }
    });

    await t.test('Pending widget meta link scrolls to and expands target file', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Queue an action on the first unresolved-match file
      const href = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = href.replace('#file-', '');
      await expandFileDetails(page, fileId);

      await openCreatePatternEditor(page, fileId);
      await fillInlinePatternBasics(page, 'Scroll-Link-Test');
      await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').click();
      await waitForInlineSnippetEditorClosed(page);
      await page.waitForSelector('#pending-actions-widget');

      // Collapse the file again so we can verify the widget link re-expands it
      await page.locator(`#expand-link-${fileId}`).click();
      t.same(await page.isVisible(`#file-details-${fileId}`), false, 'file collapsed before jump');

      // Expand widget and click the location link
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      await page.waitForSelector('#pending-actions-widget .pending-actions-item-link');
      await page.locator('#pending-actions-widget .pending-actions-item-link').first().click();

      // Clicking the link must re-expand the target file and collapse the widget panel
      await page.waitForSelector(`#file-details-${fileId} table.snippet`, {timeout: 10000});
      t.same(await page.isVisible(`#file-details-${fileId}`), true, 'file re-expanded by widget link');
      t.same(
        await page.isVisible('#pending-actions-widget .pending-actions-panel'),
        false,
        'widget collapses back to toggle button after jump'
      );

      // Verify the pending indicator (the badge inside the file source) is in view.
      // The exact action ID isn't stable enough to query precisely, so wait for
      // *any* pending-indicator to land in viewport (giving the scroll a chance
      // to settle) and then assert via evaluate.
      await page
        .waitForFunction(
          () => {
            for (const el of document.querySelectorAll('[id^="pending-indicator-"]')) {
              const r = el.getBoundingClientRect();
              if (r.top >= -50 && r.top <= window.innerHeight) return true;
            }
            return false;
          },
          {timeout: 5000}
        )
        .catch(() => {});
      const indicatorInView = await page.evaluate(() => {
        const indicators = document.querySelectorAll('[id^="pending-indicator-"]');
        for (const el of indicators) {
          const r = el.getBoundingClientRect();
          if (r.top >= -50 && r.top <= window.innerHeight) return true;
        }
        return false;
      });
      t.ok(indicatorInView, 'pending indicator is scrolled into view');

      await page.locator('[id^="pending-indicator-"] .pending-action-edit').first().click();
      await waitForInlineSnippetEditor(page);
      t.match(
        await page.innerText('#inline-snippet-editor'),
        /Scroll-Link-Test/,
        'pending indicator label reopens editor'
      );
      await page.locator('#inline-snippet-editor button', {hasText: 'Cancel'}).click();
      await waitForInlineSnippetEditorClosed(page);

      // Clean up so any later subtest starts with an empty queue
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      await page.locator('#pending-actions-widget button[title="Clear all"]').click();
    });

    await t.test('Smart edit button trims snippet, restore-original recovers initial text', async t => {
      // Page-mode editor exposes the same SnippetEditor component used inline.
      // Pick a snippet with keywords so smart_edit actually trims the text.
      const trimmableId = await page.evaluate(async () => {
        for (let id = 1; id <= 50; id++) {
          const r = await fetch(`/snippet/smart_edit/${id}`);
          if (!r.ok) continue;
          const j = await r.json();
          if (j.changed) return id;
        }
        return null;
      });
      t.ok(trimmableId !== null, `found a fixture snippet that smart_edit trims (id=${trimmableId})`);

      await page.goto(`${url}/snippet/edit/${trimmableId}`);
      t.equal(await page.innerText('title'), 'Edit snippet');
      await page.waitForSelector('#edit-snippet .cm-editor');

      const smartBtn = page.locator('#edit-snippet button[data-action="smart-edit"]');
      const restoreBtn = page.locator('#edit-snippet button[data-action="restore-original"]');
      await smartBtn.waitFor();
      await restoreBtn.waitFor();
      t.equal(await restoreBtn.isDisabled(), true, 'restore-original is disabled before any edits');

      const docText = () =>
        page.evaluate(() => document.querySelector('#edit-snippet .cm-editor').cmView.state.doc.toString());
      const highlightCount = () => page.locator('#edit-snippet .cm-line.found-pattern').count();

      const originalText = await docText();
      const originalHighlights = await highlightCount();

      const [smartResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/smart_edit\//.test(resp.url())),
        smartBtn.click()
      ]);
      t.equal(smartResp.status(), 200, 'smart edit endpoint returns 200');

      await page.waitForFunction(
        orig => document.querySelector('#edit-snippet .cm-editor').cmView.state.doc.toString() !== orig,
        originalText
      );
      const trimmedText = await docText();
      t.not(trimmedText, originalText, 'doc changed after smart edit');
      t.equal(await restoreBtn.isDisabled(), false, 'restore-original is enabled after smart edit');
      if (originalHighlights > 0) {
        t.ok((await highlightCount()) > 0, 'highlights are preserved after smart edit');
      }

      // Type a stray character on top of the trimmed text, then click restore.
      await page.locator('#edit-snippet .cm-editor .cm-content').click();
      await page.keyboard.press('End');
      await page.keyboard.type('x');
      await restoreBtn.click();
      await page.waitForFunction(
        orig => document.querySelector('#edit-snippet .cm-editor').cmView.state.doc.toString() === orig,
        originalText
      );
      t.equal(await docText(), originalText, 'doc restored to original after restore-original');
      t.equal(await highlightCount(), originalHighlights, 'highlights restored after restore-original');
      t.equal(await restoreBtn.isDisabled(), true, 'restore-original disables again once back at original');
    });

    await t.test('Accept request', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      await page.click('text="Acceptable"');
      t.equal(await page.innerText('div.alert b'), 'acceptable');

      await page.click('text=Recently Reviewed');
      t.equal(await page.innerText('title'), 'List recent reviews');
      await page.waitForSelector('#recent-reviews tbody > tr:nth-child(1)');
      t.equal(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.match(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), /ago/);
      t.equal(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'perl-Mojolicious');
      t.equal(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(6)'), 'acceptable');
      t.match(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(9)'), /Artistic/);

      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      await page.click('text="Acceptable by Lawyer"');
      await page.waitForSelector('#reviewed');
      t.equal(await page.innerText('div.alert b'), 'acceptable_by_lawyer');

      await page.click('text=Recently Reviewed');
      t.equal(await page.innerText('title'), 'List recent reviews');
      await page.waitForSelector('#recent-reviews tbody > tr:nth-child(1)');
      t.equal(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'perl-Mojolicious');
      t.equal(
        await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(6)'),
        'acceptable_by_lawyer'
      );
      t.match(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(9)'), /Artistic/);
    });

    await t.test('Manual reindexing', async t => {
      await page.goto(url);
      await page.click('text=Recently Reviewed');
      t.equal(await page.innerText('title'), 'List recent reviews');
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Wait for the reindex POST to complete before triggering job processing -
      // otherwise page2.goto(performJobs) can race ahead of the job being queued.
      const page2 = await context.newPage();
      await Promise.all([
        page.waitForResponse(resp => /reindex/.test(resp.url()) && resp.request().method() === 'POST'),
        page.click('text=Reindex')
      ]);
      await page2.goto(performJobs, {timeout: 120000});
      t.match(await page2.innerText('div'), /done/);
      await page2.close();

      await page.waitForSelector('#license-chart');
      t.match(await page.innerText('ul#risk-3 li'), /Made-Up-License-1.0/);
    });

    await t.test('Propose missing license -> page -> dismiss', async t => {
      // Use perl-Mojolicious mojo#2 (id=2) - earlier subtests resolved snippets
      // in mojo#1, but mojo#2 is untouched and still has unmatched snippets.
      await page.goto(`${url}/reviews/details/2`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Pick the first unresolved-match file from the missed-files list and
      // expand its container if needed (low-risk files start collapsed).
      const href = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = href.replace('#file-', '');
      await expandFileDetails(page, fileId);

      // Bypass Bootstrap's dropdown UI and trigger the menu item directly
      await openCreatePatternEditor(page, fileId);

      // Missing License lives in the shared More actions dropdown
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-missing"]').click();
      await waitForInlineSnippetEditorClosed(page);

      // Submit the queued proposal
      await page.waitForSelector('#pending-actions-widget');
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      t.match(await page.innerText('#pending-actions-widget'), /Propose missing license/);
      const [decisionResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#pending-actions-submit').click()
      ]);
      t.equal(decisionResp.status(), 200);
      await page.waitForLoadState('load');

      // Navigate to the Missing Licenses page from the user menu
      await openAccountMenu(page);
      await page.click('text=Missing Licenses');
      t.equal(await page.innerText('title'), 'Missing Licenses');

      await page.waitForSelector('#missing-licenses .change-container');
      const headerText = await page.innerText('#missing-licenses .change-header');
      t.match(headerText, /Missing license reported by/, 'proposal listed on the page');
      t.match(headerText, /tester/, 'reporter shown as tester');

      // Dismiss the proposal (admin sees the red Dismiss button)
      await page.locator('#missing-licenses button:has-text("Dismiss")').click();
      await page.waitForSelector('#missing-licenses .change-container', {state: 'detached'});
      t.match(
        await page.innerText('#missing-licenses .toast-item'),
        /Proposal dismissed/,
        'dismissal confirmed via toast'
      );
    });

    await t.test('Missing license -> inline editor -> create pattern -> performance page', async t => {
      // Full lawyer journey: a snippet is reported as a missing license, then an
      // admin authors the real pattern in the inline editor right on the Missing
      // Licenses page, and finally browses the new pattern on its performance page.
      const licenseName = 'Missing-Flow-License-1.0';
      const patternText = 'missing flow unique license pattern body for ui coverage';

      // 1. Proposal: report a missing license against an unresolved mojo#2 snippet.
      await page.goto(`${url}/reviews/details/2`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      const href = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = href.replace('#file-', '');
      await expandFileDetails(page, fileId);
      await openCreatePatternEditor(page, fileId);
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-missing"]').click();
      await waitForInlineSnippetEditorClosed(page);
      await page.waitForSelector('#pending-actions-widget');
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      const [proposeResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#pending-actions-submit').click()
      ]);
      t.equal(proposeResp.status(), 200);
      await page.waitForLoadState('load');

      // 2. License editing: open the inline editor on the Missing Licenses page.
      await openAccountMenu(page);
      await page.click('text=Missing Licenses');
      t.equal(await page.innerText('title'), 'Missing Licenses');
      await page.waitForSelector('#missing-licenses .change-container');
      await page.locator('#missing-licenses button:has-text("Edit Pattern")').first().click();
      await waitForInlineSnippetEditor(page);
      t.equal(
        await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').count(),
        1,
        'admin gets the Create Pattern action in the inline editor'
      );
      // The missing-licenses editor is intentionally narrowed to Create Pattern + Cancel.
      t.equal(
        await page.locator('#inline-snippet-editor button[data-action="cancel"]').count(),
        1,
        'Cancel button present'
      );
      t.equal(
        await page.locator('#inline-snippet-editor button[aria-label="More actions"]').count(),
        0,
        'no extra actions dropdown on the missing-licenses editor'
      );
      for (const action of [
        'create-ignore',
        'propose-pattern',
        'propose-ignore',
        'propose-missing',
        'mark-non-license'
      ]) {
        t.equal(
          await page.locator(`#inline-snippet-editor button[data-action="${action}"]`).count(),
          0,
          `no ${action} action on the missing-licenses editor`
        );
      }

      // Author a unique pattern so it cannot md5-collide with earlier fixtures.
      await replaceInlineEditorDoc(page, patternText);
      await fillInlinePatternBasics(page, licenseName, '3');
      const [createResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#inline-snippet-editor button[data-action="create-pattern"]').click()
      ]);
      t.equal(createResp.status(), 200);
      await page.waitForSelector('#missing-licenses .change-container', {state: 'detached'});
      t.match(
        await page.innerText('#missing-licenses .toast-item'),
        /Pattern created/,
        'pattern creation confirmed via toast and report cleared from the queue'
      );

      // Drain the reindex job queued by the new pattern so its match counts populate.
      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();

      // 3. Pattern performance: the new pattern shows on its license details page.
      await page.goto(`${url}/licenses/${licenseName}`);
      t.equal(await page.innerText('title'), `License details of ${licenseName}`);
      const card = page.locator('#license-details .license-pattern-card').first();
      await card.waitFor();
      t.match(await card.innerText(), /missing flow unique license pattern body/, 'new pattern body shown');
      t.match(await card.innerText(), /Risk 3/, 'new pattern risk shown');
    });

    await t.test('Create pattern from classify-snippets page (page mode)', async t => {
      // Fixture snippets are never AI-classified, and the default filter hides
      // unclassified ones - widen the filter so cards are guaranteed to render.
      await page.goto(`${url}/snippets?isClassified=false`);
      t.equal(await page.innerText('title'), 'Snippets');
      await page.waitForSelector('.snippet-container .snippet-likelyness a');

      // Pick a snippet card with a real file origin so the page-mode editor
      // has package context to render the "example shown here is from..." line.
      const cardWithFile = page
        .locator('.snippet-container')
        .filter({has: page.locator('.snippet-file a[href*="/reviews/file_view/"]')})
        .first();
      const [editorPage] = await Promise.all([
        context.waitForEvent('page'),
        cardWithFile.locator('.snippet-likelyness a').click()
      ]);
      await editorPage.waitForLoadState('load');
      t.equal(await editorPage.innerText('title'), 'Edit snippet');

      await editorPage.waitForSelector('#edit-snippet .cm-editor');
      await editorPage.waitForSelector('#edit-snippet input[name=license]');
      t.match(await editorPage.innerText('#edit-snippet button[data-action="create-pattern"]'), /Create Pattern/);
      // Page mode shows the source-file/package origin line (inline mode hides it).
      t.match(await editorPage.innerText('#edit-snippet'), /The example shown here is from the file/);

      const editorDoc = async () =>
        editorPage.evaluate(() => document.querySelector('#edit-snippet .cm-editor').cmView.state.doc.toString());
      const replaceEditorDoc = async text =>
        editorPage.evaluate(value => {
          const view = document.querySelector('#edit-snippet .cm-editor').cmView;
          view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: value}});
        }, text);
      const originalEditorText = await editorDoc();

      // Success path: fill the form and append a unique marker into the
      // CodeMirror editor so the resulting pattern doesn't md5-collide with one
      // created by the prior batch subtests. Then retry - EditSnippet.vue
      // redirects to the new pattern's edit page on success.
      await editorPage.locator('#edit-snippet input[name=license]').fill('Page-Editor-License-1.0');
      await editorPage.locator('#edit-snippet select[name="risk"]').selectOption('2');
      await replaceEditorDoc(`${originalEditorText}\nunique-page-mode-test-marker`);
      const [okResp] = await Promise.all([
        editorPage.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        editorPage.locator('#edit-snippet button[data-action="create-pattern"]').click()
      ]);
      t.equal(okResp.status(), 200);
      await editorPage.waitForURL(/\/licenses\/edit_pattern\/\d+/);
      t.equal(await editorPage.innerText('title'), 'Edit license pattern');
      await editorPage.close();
    });

    await t.test('Edit pattern page (Vue) - match count, editor, closest, update', async t => {
      // Pattern 1 is the Apache-2.0 fixture row ("You may obtain a copy of the
      // License at"). Visit the Vue page directly to exercise the same mount
      // that production links use.
      await page.goto(`${url}/licenses/edit_pattern/1`);
      t.equal(await page.innerText('title'), 'Edit license pattern');
      await page.waitForSelector('#edit-pattern[data-pattern]');

      // Form hydrates synchronously from the currentPattern global property.
      await page.waitForSelector('#edit-pattern input[name=license]');
      t.equal(await page.inputValue('#edit-pattern input[name=license]'), 'Apache-2.0');
      t.equal(await page.locator('#edit-pattern input#spdx').isDisabled(), true);

      // PatternCodeMirror mounts and is pre-filled with the saved pattern text.
      await page.waitForSelector('#edit-pattern .cm-editor');
      await page.waitForFunction(() => {
        const editor = document.querySelector('#edit-pattern .cm-editor');
        const view = editor && editor.cmView;
        return view && view.state.doc.toString().includes('You may obtain a copy of the License at');
      });

      // The match-count block opens in a loading state and then renders the
      // controller's count text. The spinner can resolve quickly, so just wait
      // until the loading icon is gone and assert on the final wording.
      await page.waitForFunction(() => {
        const el = document.querySelector('.edit-pattern-match-count');
        return el && !el.querySelector('i.fa-spin');
      });
      const countText = await page.innerText('.edit-pattern-match-count');
      t.match(countText, /(no matches|This pattern has)/, 'match count rendered after async load');
      t.equal(
        await page.locator('#edit-pattern .pattern-editor-tab[data-tab="edit"]').count(),
        1,
        'pattern editor shows the edit tab'
      );
      t.equal(
        await page.locator('#edit-pattern .pattern-editor-tab[data-tab="closest"]').count(),
        1,
        'pattern editor shows the closest-match tab'
      );
      t.equal(
        await page.locator('#edit-pattern .pattern-editor-tab-pane.is-active .cm-editor').count(),
        1,
        'edit form is active by default'
      );
      t.equal(
        await page.locator('#edit-pattern > .closest-container').count(),
        0,
        'closest match is not rendered below the pattern editor'
      );

      // Editing the pattern text in the CodeMirror editor must re-trigger
      // ClosestPattern's debounced fetch.
      const [refetchResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/closest/.test(resp.url())),
        page.evaluate(() => {
          const view = document.querySelector('#edit-pattern .cm-editor').cmView;
          view.dispatch({changes: {from: view.state.doc.length, insert: '\nedit-pattern-test-marker'}});
        })
      ]);
      t.equal(refetchResp.status(), 200, 'closest-match refetches after pattern edit');

      // Restore the original pattern text so the Update we're about to submit
      // doesn't drift fixture state for later tests.
      await page.evaluate(() => {
        const view = document.querySelector('#edit-pattern .cm-editor').cmView;
        const doc = view.state.doc.toString();
        view.dispatch({changes: {from: 0, to: doc.length, insert: doc.replace(/\nedit-pattern-test-marker$/, '')}});
      });

      // Dismissing the confirm dialog must leave us on the edit page (no DELETE
      // request fires).
      page.once('dialog', dialog => dialog.dismiss());
      await page.locator('#edit-pattern .del-pattern').click();
      t.match(page.url(), /\/licenses\/edit_pattern\/1/, 'cancelled delete stays on edit page');

      // Update button submits the standard form POST; the controller redirects
      // back to the same edit page with a flash message.
      await Promise.all([
        page.waitForURL(/\/licenses\/edit_pattern\/1/),
        page.locator('#edit-pattern button[type=submit]').click()
      ]);
      await page.waitForSelector('#edit-pattern[data-pattern]');
      t.equal(await page.innerText('title'), 'Edit license pattern');
    });

    await t.test('New pattern page (Vue) - create form posts to /licenses/create_pattern', async t => {
      // Drive the same Vue mount with no pattern.id so it switches to "create" mode.
      await page.goto(`${url}/licenses/new_pattern?license-name=Vue-Create-Test-License`);
      t.equal(await page.innerText('title'), 'New license pattern');
      await page.waitForSelector('#edit-pattern[data-pattern]');

      // License field is pre-filled from the license-name query parameter.
      await page.waitForSelector('#edit-pattern input[name=license]');
      t.equal(await page.inputValue('#edit-pattern input[name=license]'), 'Vue-Create-Test-License');

      // Match count block and SPDX field are hidden in create mode (no pattern id yet).
      t.equal(await page.locator('.edit-pattern-match-count').count(), 0, 'no match count in create mode');
      t.equal(await page.locator('#edit-pattern #spdx').count(), 0, 'no SPDX field in create mode');

      // Delete button is hidden; submit button reads "Create".
      t.equal(await page.locator('#edit-pattern .del-pattern').count(), 0, 'no delete button in create mode');
      t.equal(await page.innerText('#edit-pattern button[type=submit]'), 'Create');

      // Form posts to the create endpoint.
      const action = await page.locator('#edit-pattern form').getAttribute('action');
      t.match(action, /\/licenses\/create_pattern$/, 'form action targets create endpoint');

      // PatternCodeMirror mounts empty; type a unique pattern body so the create succeeds
      // without colliding with any existing fixture pattern.
      await page.waitForSelector('#edit-pattern .cm-editor');
      await page.evaluate(() => {
        const view = document.querySelector('#edit-pattern .cm-editor').cmView;
        view.dispatch({changes: {from: 0, insert: 'unique-vue-create-test-pattern-body'}});
      });

      // Submit redirects to /licenses/edit_pattern/<new-id> with a flash message.
      await Promise.all([
        page.waitForURL(/\/licenses\/edit_pattern\/\d+/),
        page.locator('#edit-pattern button[type=submit]').click()
      ]);
      t.equal(await page.innerText('title'), 'Edit license pattern');
      // Now in edit mode: SPDX field and Delete button must be present.
      await page.waitForSelector('#edit-pattern #spdx');
      await page.waitForSelector('#edit-pattern .del-pattern');
      t.equal(await page.inputValue('#edit-pattern input[name=license]'), 'Vue-Create-Test-License');
    });

    await t.test('License details page (Vue) - inline edit updates pattern card', async t => {
      await page.goto(`${url}/licenses/Vue-Create-Test-License`);
      t.equal(await page.innerText('title'), 'License details of Vue-Create-Test-License');
      const card = page.locator('#license-details .license-pattern-card').first();
      await card.waitFor();
      await card.locator('button[data-action="edit-pattern-inline"]').click();
      await page.waitForSelector('#license-details .license-inline-editor .cm-editor');
      t.equal(await card.locator('.license-pattern-code').count(), 0, 'inline editor replaces the pattern preview');
      t.equal(
        await card.locator('.license-pattern-footer').count(),
        0,
        'inline editor replaces the pattern metadata footer'
      );
      t.equal(
        await card.locator('.pattern-editor-tab[data-tab="edit"]').count(),
        1,
        'inline editor shows the edit tab'
      );
      t.equal(
        await card.locator('.pattern-editor-tab[data-tab="closest"]').count(),
        1,
        'inline editor shows the closest-match tab'
      );
      await page.locator('#license-details .license-inline-editor input[name="packname"]').fill('ui-inline-package');
      await page.locator('#license-details .license-inline-editor select[name="risk"]').selectOption('4');
      await page.locator('#license-details .license-inline-editor button[type="submit"]').click();
      await page.waitForSelector('#license-details .license-inline-editor', {state: 'detached'});
      await page.waitForSelector('#license-details .toast-item.toast-success');
      t.match(await page.innerText('#license-details'), /ui-inline-package/);
      t.match(await page.innerText('#license-details .license-pattern-card'), /Risk 4/);
    });

    await t.test('Edit pattern page (Vue) - delete redirects to /licenses', async t => {
      // Use the throwaway pattern created in the classify-snippets subtest
      // above so we can exercise the destructive DELETE path without breaking
      // later assertions (Pattern Performance only checks Made-Up-License-1.0).
      await page.goto(`${url}/licenses/Page-Editor-License-1.0`);
      t.equal(await page.innerText('title'), 'License details of Page-Editor-License-1.0');
      const patternId = await page
        .locator('#license-details .license-pattern-card')
        .first()
        .getAttribute('data-pattern-id');
      t.ok(patternId, 'license details page exposes the pattern id');

      await page.goto(`${url}/licenses/edit_pattern/${patternId}`);
      t.equal(await page.innerText('title'), 'Edit license pattern');
      await page.waitForSelector('#edit-pattern[data-pattern]');
      await page.waitForSelector('#edit-pattern .del-pattern');

      // Accept the confirm dialog so the AJAX DELETE fires; the component
      // then navigates to /licenses.
      page.once('dialog', dialog => dialog.accept());
      await Promise.all([page.waitForURL(/\/licenses\/?(\?|#|$)/), page.locator('#edit-pattern .del-pattern').click()]);
      t.equal(await page.innerText('title'), 'List licenses', 'redirected to license list after delete');
    });

    await t.test('Pattern Performance', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Pattern Performance');
      t.equal(await page.innerText('title'), 'Pattern Performance');
      await page.waitForSelector('#recent-patterns .recent-pattern-header');
      const names = await page.locator('#recent-patterns .recent-pattern-header b').allInnerTexts();
      t.ok(names.includes('Made-Up-License-1.0'), 'Made-Up-License-1.0 listed among recent patterns');
    });

    await t.test('Snippet editor action layout (contributor)', async t => {
      // Switch to a contributor-only user via the wrapper helper. The dummy
      // login always picks up the admin "tester"; this route logs in as a
      // user that only has the 'contributor' role.
      await page.goto(`${url}/login_as_contributor`);
      await page.locator('#cavil-menubar .cavil-user-name', {hasText: 'contrib_tester'}).waitFor();

      // Pattern create/delete in earlier subtests enqueues reindex jobs
      // noted as pkg_2 - drain them so /reviews/report_details/2 does not
      // 408 with "package being processed".
      const drainPage = await context.newPage();
      await drainPage.goto(performJobs, {timeout: 120000});
      await drainPage.close();

      // mojo#2 still has unresolved files - earlier subtests only *proposed*
      // against it (a non-resolving action).
      await page.goto(`${url}/reviews/details/2`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const href = await page.locator('#filelist-snippets a.file-link').first().getAttribute('href');
      const fileId = href.replace('#file-', '');
      await expandFileDetails(page, fileId);

      await openCreatePatternEditor(page, fileId);

      // No admin-only "Create Pattern" / "Ignore Pattern" buttons for contributor
      t.equal(
        await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').count(),
        0,
        'no admin Create Pattern button'
      );
      t.equal(
        await page.locator('#inline-snippet-editor button[data-action="create-ignore"]').count(),
        0,
        'no admin Ignore Pattern button'
      );

      // Primary slot: Propose Pattern (green)
      const propose = page.locator('#inline-snippet-editor button[data-action="propose-pattern"]');
      t.equal(await propose.count(), 1);
      t.match(await propose.innerText(), /Propose Pattern/);
      t.ok(await propose.evaluate(el => el.classList.contains('btn-success')), 'Propose Pattern is the green primary');

      // Secondary slot: Propose Ignore (neutral)
      const ignore = page.locator('#inline-snippet-editor button[data-action="propose-ignore"]');
      t.equal(await ignore.count(), 1);
      t.match(await ignore.innerText(), /Propose Ignore/);
      t.ok(await ignore.evaluate(el => el.classList.contains('snippet-editor-neutral')), 'Propose Ignore is neutral');

      // Shared More actions dropdown contains exactly "Missing License"
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      const items = await page.locator('#inline-snippet-editor .dropdown-menu a.dropdown-item').allInnerTexts();
      t.same(
        items.map(s => s.trim()),
        ['Missing License'],
        'contributor More actions dropdown holds just Missing License'
      );
      await page.keyboard.press('Escape');

      // Cancel closes the inline editor
      await page.locator('#inline-snippet-editor button[data-action="cancel"]').click();
      await waitForInlineSnippetEditorClosed(page);
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
