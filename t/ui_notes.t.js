#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Notes tab + Recent Notes page. The admin subtests build up the note set
// (post, edit, delete) and the contributor subtests then verify that the
// same notes look right with reduced permissions. They share a single
// schema because the contributor expectations match the exact bodies that
// the admin sequence leaves behind ("Edited body with", visible count of
// 24 = 25 seeds - 1 lawyer-only).
t.test('Cavil UI - notes', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_notes');
  const {page, context, url, errorLogs} = ui;

  try {
    // Establish the admin session.
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Notes tab (admin)', async t => {
      // ui_fixtures seeds 25 notes on package_name=perl-Mojolicious, shared
      // across review #1 (mojo#1) and review #2 (mojo#2). One is lawyer-only.
      await page.goto(`${url}/reviews/details/1`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#report-tabs');

      // Badge should appear at the seed count even before the tab is clicked.
      await page.waitForFunction(() => {
        const el = document.querySelector('[data-note-count]');
        return el && Number(el.textContent) === 25;
      });
      t.equal(await page.innerText('[data-tab="notes"] [data-note-count]'), '25');
      // One seed note is lawyer-only, admin sees it - tab gets amber tint.
      t.ok(
        await page.locator('[data-tab="notes"] .report-tab-badge-lawyer').count(),
        'tab badge tinted amber when lawyer-only notes are visible'
      );

      // Switch to the Notes tab; the pane lazily mounts on first activation.
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      const initial = await page.locator('.report-note').count();
      t.equal(initial, 20, 'first page contains the default 20 newest notes');

      // Markdown is rendered server-side via CommonMark
      const newest = page.locator('.report-note').first();
      await newest.waitFor();
      t.match(await newest.locator('.report-note-body').innerText(), /Latest review notes/);
      t.ok(await newest.locator('.report-note-body ul li').count(), 'markdown list rendered as <ul><li>');
      t.ok(await newest.locator('[data-note-ai-assisted]').count(), 'AI-assisted seed note shows the badge');
      // Seed notes are authored by test_bot (role: user) - role chip renders.
      t.equal(await newest.locator('[data-note-role]').getAttribute('data-note-role'), 'user');

      // Lawyer-only seed note is the oldest (seeded first); scroll the
      // endless-scroll sentinel into view to trigger the second page so we
      // can see it.
      const sentinel = page.locator('[data-notes-sentinel]');
      await sentinel.scrollIntoViewIfNeeded();
      await page.waitForFunction(() => document.querySelectorAll('.report-note').length >= 25);
      const lawyerSeed = page.locator('.report-note-lawyer-only').first();
      await lawyerSeed.waitFor();
      t.ok(await lawyerSeed.locator('.lawyer-only-badge').count(), 'lawyer-only seed note shows the badge');

      // Sentinel disappears (or stays empty) when the list is exhausted; the
      // count should match the seed total now.
      t.equal(await page.locator('.report-note').count(), 25, 'all 25 seed notes loaded');

      // Post a new public note - it appears at the top and the badge bumps.
      await page.locator('[data-composer-input="new"]').fill('First admin reply with `code`');
      const [postResp] = await Promise.all([
        page.waitForResponse(resp => /\/reviews\/notes\/1$/.test(resp.url()) && resp.request().method() === 'POST'),
        page.locator('[data-composer-save="new"]').click()
      ]);
      t.equal(postResp.status(), 200);
      await page.waitForFunction(() => {
        const first = document.querySelector('.report-note .report-note-body');
        return first && first.textContent.includes('First admin reply');
      });
      const adminNew = page.locator('.report-note').first();
      t.match(await adminNew.locator('.report-note-body').innerText(), /First admin reply with/);
      t.equal(
        await adminNew.locator('[data-note-origin-badge]').count(),
        0,
        'originating review note has no origin badge'
      );
      t.equal(
        await adminNew.locator('[data-note-role]').getAttribute('data-note-role'),
        'admin',
        'admin author gets the admin role chip'
      );
      t.equal(await page.innerText('[data-tab="notes"] [data-note-count]'), '26');

      // Cross-version sharing: open review #2 (mojo#2 of perl-Mojolicious) -
      // same note shows there.
      await page.goto(`${url}/reviews/details/2`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForFunction(() => {
        const el = document.querySelector('[data-note-count]');
        return el && Number(el.textContent) === 26;
      });
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      const sharedNewest = page.locator('.report-note').first();
      t.match(await sharedNewest.locator('.report-note-body').innerText(), /First admin reply/);
      t.match(
        await sharedNewest.locator('[data-note-origin-badge]').innerText(),
        /from review #1/,
        'note from another review gets an origin badge'
      );
      t.equal(await sharedNewest.locator('[data-note-origin-badge]').getAttribute('href'), '/reviews/details/1');
      t.equal(
        await sharedNewest.locator('[data-note-origin-badge]').getAttribute('target'),
        '_blank',
        'originating-report link opens in a new tab'
      );
      // Permalink on the relative time stays on the current review.
      t.match(
        await sharedNewest.locator('[data-note-permalink]').getAttribute('href'),
        /^\/reviews\/details\/2#note-\d+$/,
        'permalink points at the current review with the note anchor'
      );

      // Add a lawyer-only note from review #2; verify highlight + tab tint.
      await page.locator('[data-composer-input="new"]').fill('Confidential note for lawyers only');
      await page.locator('[data-note-lawyer-only]').check();
      const [lawyerPostResp] = await Promise.all([
        page.waitForResponse(resp => /\/reviews\/notes\/2$/.test(resp.url()) && resp.request().method() === 'POST'),
        page.locator('[data-composer-save="new"]').click()
      ]);
      t.equal(lawyerPostResp.status(), 200);
      await page.waitForFunction(() => {
        const first = document.querySelector('.report-note .report-note-body');
        return first && first.textContent.includes('Confidential note');
      });
      const newLawyer = page.locator('.report-note').first();
      t.ok(
        await newLawyer.evaluate(el => el.classList.contains('report-note-lawyer-only')),
        'new lawyer-only note has the lawyer-only class'
      );
      t.ok(await newLawyer.locator('.lawyer-only-badge').count(), 'new lawyer-only note shows the badge');
      t.equal(await page.innerText('[data-tab="notes"] [data-note-count]'), '27');

      // Self-delete: remove the brand new lawyer-only note we just added.
      page.once('dialog', dialog => dialog.accept());
      const [deleteResp] = await Promise.all([
        page.waitForResponse(resp => /\/reviews\/notes\/\d+$/.test(resp.url()) && resp.request().method() === 'DELETE'),
        newLawyer.locator('.report-note-delete').click()
      ]);
      t.equal(deleteResp.status(), 200);
      await page.waitForFunction(() => {
        const first = document.querySelector('.report-note .report-note-body');
        return first && first.textContent.includes('First admin reply');
      });
      t.equal(await page.innerText('[data-tab="notes"] [data-note-count]'), '26');

      // Admin can also delete a seed note authored by test_bot. The
      // fixture seeds 24 "Seed note #N" bodies (N=1..24) plus a 25th
      // "Latest review notes" body, so any "Seed note #N" target works.
      const seedTarget = page.locator('.report-note').filter({hasText: 'Seed note #24'}).first();
      await seedTarget.waitFor();
      page.once('dialog', dialog => dialog.accept());
      await Promise.all([
        page.waitForResponse(resp => /\/reviews\/notes\/\d+$/.test(resp.url()) && resp.request().method() === 'DELETE'),
        seedTarget.locator('.report-note-delete').click()
      ]);
      await page.waitForFunction(() => {
        return !Array.from(document.querySelectorAll('.report-note-body')).some(b =>
          b.textContent.includes('Seed note #24')
        );
      });
      t.equal(await page.innerText('[data-tab="notes"] [data-note-count]'), '25');
    });

    await t.test('Edit a note via Write/Preview composer', async t => {
      // The "First admin reply" added in the Notes admin subtest is still
      // around (it sits at the top of review #2 too). Open mojo#1 fresh and
      // edit it via the new pen icon + composer flow.
      await page.goto(`${url}/reviews/details/1`);
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      const target = page.locator('.report-note').filter({hasText: 'First admin reply'}).first();
      await target.waitFor();
      const id = await target.getAttribute('data-note-id');

      await target.locator('[data-note-edit]').click();
      await page.waitForSelector(`[data-note-edit-pane] [data-composer-input="edit-${id}"]`);

      // Edit the body, switch to Preview, verify the rendered HTML comes from
      // the server endpoint and contains the new markdown.
      const editor = page.locator(`[data-composer-input="edit-${id}"]`);
      await editor.fill('Edited body with **markdown** _emphasis_.');
      const [previewResp] = await Promise.all([
        page.waitForResponse(
          resp => /\/reviews\/notes\/preview$/.test(resp.url()) && resp.request().method() === 'POST'
        ),
        page.locator(`[data-composer-tab="preview-edit-${id}"]`).click()
      ]);
      t.equal(previewResp.status(), 200);
      const previewPane = page.locator(`[data-composer-preview="edit-${id}"]`);
      await previewPane.waitFor();
      t.match(await previewPane.innerText(), /Edited body with/);
      const strong = await previewPane.locator('strong').count();
      t.ok(strong > 0, 'preview renders **markdown** as <strong>');

      // Save the edit through the PATCH path.
      const [patchResp] = await Promise.all([
        page.waitForResponse(
          resp => new RegExp(`/reviews/notes/${id}$`).test(resp.url()) && resp.request().method() === 'PATCH'
        ),
        page.locator(`[data-composer-save="edit-${id}"]`).click()
      ]);
      t.equal(patchResp.status(), 200);
      // Editor pane is gone, body has been replaced, and the "edited" marker
      // appears next to the date.
      await page.waitForSelector(`[data-note-edit-pane]`, {state: 'detached'});
      const updated = page.locator(`#note-${id}`);
      t.match(await updated.locator('.report-note-body').innerText(), /Edited body with/);
      const editedMarker = updated.locator('[data-note-edited]');
      t.equal(await editedMarker.count(), 1, 'edited marker is shown after a successful edit');
      // Marker carries a relative timestamp ("edited a few seconds ago") and
      // the exact timestamp lives in the tooltip - exercise both so neither
      // disappears in a future refactor.
      t.match(await editedMarker.innerText(), /edited\s+.+\s+ago/, 'edited marker includes a relative time');
      t.match(
        await editedMarker.getAttribute('title'),
        /^Edited \d{4}-\d{2}-\d{2}/,
        'edited tooltip carries the exact ISO date'
      );
    });

    await t.test('Note relevance cues + Only relevant filter (admin)', async t => {
      // Native notes (originated on the review being viewed) are highlighted
      // blue and carry a "this review" badge.
      await page.goto(`${url}/reviews/details/1`);
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      const firstNote = page.locator('.report-note').first();
      await firstNote.waitFor();
      t.ok(
        await firstNote.evaluate(el => el.classList.contains('report-note-relevant')),
        'native note is highlighted as relevant'
      );
      t.equal(
        await firstNote.locator('[data-note-this-review]').count(),
        1,
        'native note carries the "this review" badge'
      );

      // With every note native there is nothing to hide, so no toggle.
      t.equal(
        await page.locator('[data-notes-relevant-only]').count(),
        0,
        'relevance toggle hidden when all notes are relevant'
      );

      // Post a note from review #2 so review #1 inherits a non-relevant note
      // (the fixtures give the two reviews different/empty report checksums, so
      // it is NOT an identical-report match).
      await page.goto(`${url}/reviews/details/2`);
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      await page.locator('[data-composer-input="new"]').fill('Inherited from the version 2 review');
      const [postResp] = await Promise.all([
        page.waitForResponse(r => /\/reviews\/notes\/2$/.test(r.url()) && r.request().method() === 'POST'),
        page.locator('[data-composer-save="new"]').click()
      ]);
      t.equal(postResp.status(), 200);
      const inheritedId = (await postResp.json()).note.id;

      // On review #1 that note is inherited: grey origin badge, not relevant.
      await page.goto(`${url}/reviews/details/1`);
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      const inherited = page.locator(`#note-${inheritedId}`);
      await inherited.waitFor();
      t.notOk(
        await inherited.evaluate(el => el.classList.contains('report-note-relevant')),
        'inherited note from a different report is not marked relevant'
      );
      t.equal(
        await inherited.locator('[data-note-this-review]').count(),
        0,
        'inherited note has no "this review" badge'
      );
      const originBadge = inherited.locator('[data-note-origin-badge]');
      t.match(await originBadge.innerText(), /from review #2/, 'inherited note links back to review #2');
      t.ok(
        await originBadge.evaluate(el => el.classList.contains('origin-report-badge-other')),
        'different-report origin badge uses the muted grey variant'
      );

      // The toggle now appears; enabling it hides the inherited (grey) note.
      const toggle = page.locator('[data-notes-relevant-only]');
      await toggle.waitFor();
      await toggle.check();
      await page.waitForSelector(`#note-${inheritedId}`, {state: 'detached'});
      t.equal(
        await page.locator('.report-note:not(.report-note-relevant)').count(),
        0,
        'only relevant notes remain while the filter is on'
      );

      // Turning it off brings the inherited note back.
      await toggle.uncheck();
      await page.waitForSelector(`#note-${inheritedId}`);

      // Cleanup: delete the inherited note so downstream counts stay at 25.
      page.once('dialog', dialog => dialog.accept());
      await Promise.all([
        page.waitForResponse(
          r => new RegExp(`/reviews/notes/${inheritedId}$`).test(r.url()) && r.request().method() === 'DELETE'
        ),
        inherited.locator('.report-note-delete').click()
      ]);
      await page.waitForSelector(`#note-${inheritedId}`, {state: 'detached'});
      t.equal(await page.innerText('[data-tab="notes"] [data-note-count]'), '25', 'note count restored to 25');
    });

    await t.test('Tag chip input in the composer and edit pane (admin)', async t => {
      await page.goto(`${url}/reviews/details/1`);
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');

      // Commit one chip via Enter, post a note, and verify the saved card
      // renders the new .report-note-tag chip with the same value.
      const composerTags = page.locator('[data-note-tag-editor="new"]');
      await composerTags.locator('[data-note-tag-input]').fill('review');
      await composerTags.locator('[data-note-tag-input]').press('Enter');
      await composerTags.locator('[data-note-tag-chip="review"]').waitFor();
      t.equal(
        await composerTags.locator('[data-note-tag-input]').inputValue(),
        '',
        'tag input clears after Enter commits the chip'
      );

      await page.locator('[data-composer-input="new"]').fill('Tag chip baseline');
      const [postResp] = await Promise.all([
        page.waitForResponse(resp => /\/reviews\/notes\/1$/.test(resp.url()) && resp.request().method() === 'POST'),
        page.locator('[data-composer-save="new"]').click()
      ]);
      t.equal(postResp.status(), 200);
      await page.waitForFunction(() => {
        const first = document.querySelector('.report-note .report-note-body');
        return first && first.textContent.includes('Tag chip baseline');
      });
      const newest = page.locator('.report-note').first();
      const id = await newest.getAttribute('data-note-id');
      t.equal(
        await newest.locator('[data-note-tag="review"]').innerText(),
        'review',
        'saved note renders the review tag chip'
      );

      // Composer state resets after posting.
      t.equal(await composerTags.locator('[data-note-tag-chip]').count(), 0, 'composer chip list resets after post');

      // Multi-tag commit: comma + Enter. Then click × on one chip to remove it
      // before posting; the remaining chip should still go through.
      await composerTags.locator('[data-note-tag-input]').fill('kind-a');
      await composerTags.locator('[data-note-tag-input]').press(',');
      await composerTags.locator('[data-note-tag-input]').fill('kind-b');
      await composerTags.locator('[data-note-tag-input]').press('Enter');
      await composerTags.locator('[data-note-tag-chip="kind-b"]').waitFor();
      t.equal(await composerTags.locator('[data-note-tag-chip]').count(), 2, 'comma and Enter both commit chips');

      await composerTags.locator('[data-note-tag-remove="kind-a"]').click();
      await page.waitForFunction(() => !document.querySelector('[data-note-tag-chip="kind-a"]'));
      t.equal(
        await composerTags.locator('[data-note-tag-chip="kind-a"]').count(),
        0,
        'remove × drops the chip before submission'
      );

      // Posting from the edit pane: open the tagged note we just created,
      // add another tag, save, and confirm both chips render afterwards.
      const editTarget = page.locator(`#note-${id}`);
      await editTarget.locator('[data-note-edit]').click();
      await page.waitForSelector(`[data-note-edit-pane] [data-composer-input="edit-${id}"]`);
      const editTags = page.locator(`[data-note-tag-editor="edit-${id}"]`);
      await editTags.locator('[data-note-tag-chip="review"]').waitFor();
      await editTags.locator('[data-note-tag-input]').fill('triage');
      await editTags.locator('[data-note-tag-input]').press('Enter');
      await editTags.locator('[data-note-tag-chip="triage"]').waitFor();

      const [patchResp] = await Promise.all([
        page.waitForResponse(
          resp => new RegExp(`/reviews/notes/${id}$`).test(resp.url()) && resp.request().method() === 'PATCH'
        ),
        page.locator(`[data-composer-save="edit-${id}"]`).click()
      ]);
      t.equal(patchResp.status(), 200);
      await page.waitForSelector(`[data-note-edit-pane]`, {state: 'detached'});
      const updatedTags = page.locator(`#note-${id} [data-note-tag]`);
      const tagValues = await updatedTags.evaluateAll(els => els.map(el => el.getAttribute('data-note-tag')).sort());
      t.same(tagValues, ['review', 'triage'], 'edit-flow adds a tag without losing the existing one');

      // Cleanup: delete the test note so the contributor subtest still sees
      // exactly 25 notes (24 public + 1 lawyer-only).
      page.once('dialog', dialog => dialog.accept());
      const [deleteResp] = await Promise.all([
        page.waitForResponse(
          resp => new RegExp(`/reviews/notes/${id}$`).test(resp.url()) && resp.request().method() === 'DELETE'
        ),
        page.locator(`#note-${id} .report-note-delete`).click()
      ]);
      t.equal(deleteResp.status(), 200);
      await page.waitForSelector(`#note-${id}`, {state: 'detached'});
      t.equal(await page.innerText('[data-tab="notes"] [data-note-count]'), '25', 'note count restored to 25');
    });

    await t.test('Permalink deep-link auto-activates Notes tab and scrolls', async t => {
      // Pick the permalink of a note that lives on the *second* page
      // ("Seed note #2" was inserted second, so it's near the bottom of
      // the list and is only loaded after the endless-scroll pagination loop
      // runs). This proves the seek-to-note loop traverses pages.
      await page.goto(`${url}/reviews/details/1`);
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      await page.locator('[data-notes-sentinel]').scrollIntoViewIfNeeded();
      const targetNote = page.locator('.report-note').filter({hasText: 'Seed note #2 for'}).first();
      await targetNote.waitFor();
      const permalink = await targetNote.locator('[data-note-permalink]').getAttribute('href');
      t.match(permalink, /^\/reviews\/details\/1#note-\d+$/, 'permalink uses #note-<id>');
      const noteDomId = permalink.split('#')[1];

      // Open the permalink in a fresh page (mimicking what a user pasting the
      // link from chat would experience).
      const linkedPage = await context.newPage();
      await linkedPage.goto(`${url}${permalink}`);
      t.equal(await linkedPage.innerText('title'), 'Report for perl-Mojolicious');

      // Tab is pre-activated and the target note is mounted (paginated
      // into view) without any user interaction.
      await linkedPage.waitForSelector(`#report-notes-pane.is-active #${noteDomId}`);
      t.equal(
        await linkedPage.getAttribute('[data-tab="notes"]', 'aria-selected'),
        'true',
        'Notes tab auto-activated on deep-link load'
      );
      t.match(
        await linkedPage.locator(`#${noteDomId} .report-note-body`).innerText(),
        /Seed note #2 for/,
        'targeted note is visible after deep-link load'
      );
      // Highlight class is added briefly so the eye is drawn to the target.
      await linkedPage.waitForSelector(`#${noteDomId}.report-note-highlight`);
      await linkedPage.close();
    });

    await t.test('Recent Notes page (admin)', async t => {
      await page.goto(url);
      await page.locator('#cavil-menubar .cavil-user-menu > .nav-link').click();
      await page.click('text=Recent Notes');
      t.equal(await page.innerText('title'), 'Recent Notes');
      t.match(
        await page.locator('#recent-notes .cavil-notice-panel-intro').innerText(),
        /most recently added reviewer notes/,
        'recent notes page explains what is listed'
      );
      t.match(
        await page.locator('#recent-notes .cavil-notice-panel-intro').innerText(),
        /Lawyer-only notes are shown only to lawyers and admins/,
        'recent notes page explains lawyer-only visibility to admins'
      );
      await page.waitForSelector('#recent-notes .report-note');

      const newest = page.locator('#recent-notes .report-note').first();
      t.match(await newest.locator('.report-note-body').innerText(), /Edited body with/);
      t.equal(
        await newest.locator('.report-note-package-link').innerText(),
        'perl-Mojolicious',
        'recent note shows the package name'
      );
      t.equal(await newest.locator('.report-note-package-link').getAttribute('href'), '/reviews/details/1');
      t.match(
        await newest.locator('[data-note-permalink]').getAttribute('href'),
        /^\/reviews\/details\/1#note-\d+$/,
        'recent note permalink targets the originating report'
      );
      t.equal(await page.locator('#recent-notes [data-note-form]').count(), 0, 'recent notes page has no composer');
      t.equal(await page.locator('#recent-notes [data-note-edit]').count(), 0, 'recent notes page has no edit buttons');
      t.equal(
        await page.locator('#recent-notes [data-note-delete]').count(),
        0,
        'recent notes page has no delete buttons'
      );

      await page.locator('#recent-notes [data-notes-sentinel]').scrollIntoViewIfNeeded();
      await page.waitForFunction(() => document.querySelectorAll('#recent-notes .report-note').length >= 25);
      t.equal(
        await page.locator('#recent-notes .report-note-lawyer-only').count(),
        1,
        'admin recent notes include lawyer-only notes'
      );
    });

    await t.test('Recent Notes tag filter + autocomplete (admin)', async t => {
      // Author two tagged notes through the composer (real user flow) so the
      // filter and its autocomplete have data: both carry uitag-x, one also
      // carries uitag-y.
      await page.goto(`${url}/reviews/details/1`);
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      const composerTags = page.locator('[data-note-tag-editor="new"]');

      const postNote = async (body, tags) => {
        for (const tag of tags) {
          await composerTags.locator('[data-note-tag-input]').fill(tag);
          await composerTags.locator('[data-note-tag-input]').press('Enter');
          await composerTags.locator(`[data-note-tag-chip="${tag}"]`).waitFor();
        }
        await page.locator('[data-composer-input="new"]').fill(body);
        const [resp] = await Promise.all([
          page.waitForResponse(r => /\/reviews\/notes\/1$/.test(r.url()) && r.request().method() === 'POST'),
          page.locator('[data-composer-save="new"]').click()
        ]);
        t.equal(resp.status(), 200);
        return (await resp.json()).note.id;
      };

      const idX = await postNote('Filter fixture X only', ['uitag-x']);
      const idXY = await postNote('Filter fixture X and Y', ['uitag-x', 'uitag-y']);

      // On the Recent Notes page, typing into the filter shows autocomplete
      // suggestions sourced from the known-tags endpoint.
      await page.goto(`${url}/reviews/notes/recent`);
      await page.waitForSelector('#recent-notes .report-note');
      const filter = page.locator('[data-recent-notes-filter] [data-note-tag-editor="filter"]');
      await filter.locator('[data-note-tag-input]').fill('uitag-x');
      await page.locator('[data-tag-suggestion="uitag-x"]').click();
      await filter.locator('[data-note-tag-chip="uitag-x"]').waitFor();

      // The list narrows to the two notes carrying uitag-x and the URL records
      // the active filter so the view is shareable.
      await page.waitForFunction(() => document.querySelectorAll('#recent-notes .report-note').length === 2);
      t.match(page.url(), /[?&]tags=uitag-x/, 'selected tag is reflected in the URL');
      const bodies = await page.locator('#recent-notes .report-note-body').allInnerTexts();
      t.ok(
        bodies.some(b => b.includes('Filter fixture X only')),
        'single-tag note shown'
      );
      t.ok(
        bodies.some(b => b.includes('Filter fixture X and Y')),
        'multi-tag note shown'
      );

      // Adding a second tag applies an AND filter, narrowing to one note.
      await filter.locator('[data-note-tag-input]').fill('uitag-y');
      await page.locator('[data-tag-suggestion="uitag-y"]').click();
      await filter.locator('[data-note-tag-chip="uitag-y"]').waitFor();
      await page.waitForFunction(() => document.querySelectorAll('#recent-notes .report-note').length === 1);
      t.match(
        await page.locator('#recent-notes .report-note-body').first().innerText(),
        /Filter fixture X and Y/,
        'AND filter keeps only the note carrying both tags'
      );

      // Removing a chip broadens the result set again.
      await filter.locator('[data-note-tag-remove="uitag-y"]').click();
      await page.waitForFunction(() => document.querySelectorAll('#recent-notes .report-note').length === 2);

      // Cleanup: delete both fixtures so later subtests see the original counts.
      await page.goto(`${url}/reviews/details/1`);
      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      for (const id of [idX, idXY]) {
        page.once('dialog', dialog => dialog.accept());
        const [resp] = await Promise.all([
          page.waitForResponse(
            r => new RegExp(`/reviews/notes/${id}$`).test(r.url()) && r.request().method() === 'DELETE'
          ),
          page.locator(`#note-${id} .report-note-delete`).click()
        ]);
        t.equal(resp.status(), 200);
        await page.waitForSelector(`#note-${id}`, {state: 'detached'});
      }
      t.equal(await page.innerText('[data-tab="notes"] [data-note-count]'), '25', 'note count restored to 25');
    });

    await t.test('Notes tab hides lawyer-only data from contributors', async t => {
      // Switch to a contributor-only user; the wrapper route logs in as
      // "contrib_tester" with just the 'contributor' role.
      await page.goto(`${url}/login_as_contributor`);
      await page.locator('#cavil-menubar .cavil-user-name', {hasText: 'contrib_tester'}).waitFor();

      // The admin subtests above left 25 visible notes on
      // package_name=perl-Mojolicious. One of those (the original seed) is
      // lawyer-only; a contributor should see 24.
      await page.goto(`${url}/reviews/details/1`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForFunction(() => {
        const el = document.querySelector('[data-note-count]');
        return el && Number(el.textContent) === 24;
      });
      // No lawyer-only items in view, so no amber tint.
      t.equal(
        await page.locator('[data-tab="notes"] .report-tab-badge-lawyer').count(),
        0,
        'tab badge not amber-tinted for contributor (no lawyer-only visible)'
      );

      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      t.equal(await page.locator('.report-note-lawyer-only').count(), 0, 'no lawyer-only notes listed');
      t.equal(
        await page.locator('[data-note-lawyer-only]').count(),
        0,
        'lawyer-only checkbox is hidden from contributors'
      );

      // Contributors can post regular notes and delete their own.
      await page.locator('[data-composer-input="new"]').fill('Contributor feedback');
      const [postResp] = await Promise.all([
        page.waitForResponse(resp => /\/reviews\/notes\/1$/.test(resp.url()) && resp.request().method() === 'POST'),
        page.locator('[data-composer-save="new"]').click()
      ]);
      t.equal(postResp.status(), 200);
      await page.waitForFunction(() => {
        const first = document.querySelector('.report-note .report-note-body');
        return first && first.textContent.includes('Contributor feedback');
      });
      const own = page.locator('.report-note').first();
      t.equal(await own.locator('.report-note-delete').count(), 1, 'contributor can delete own note');

      // Other (test_bot) notes cannot be deleted by the contributor.
      const someoneElse = page.locator('.report-note').filter({hasText: 'Seed note'}).first();
      t.equal(
        await someoneElse.locator('.report-note-delete').count(),
        0,
        'contributor cannot delete someone elses note'
      );

      page.once('dialog', dialog => dialog.accept());
      await Promise.all([
        page.waitForResponse(resp => /\/reviews\/notes\/\d+$/.test(resp.url()) && resp.request().method() === 'DELETE'),
        own.locator('.report-note-delete').click()
      ]);
      await page.waitForFunction(() => {
        const first = document.querySelector('.report-note .report-note-body');
        return first && !first.textContent.includes('Contributor feedback');
      });
    });

    await t.test('Recent Notes page hides lawyer-only data from contributors', async t => {
      await page.goto(`${url}/reviews/notes/recent`);
      t.equal(await page.innerText('title'), 'Recent Notes');
      t.notMatch(
        await page.locator('#recent-notes .cavil-notice-panel-intro').innerText(),
        /Lawyer-only notes are shown only to lawyers and admins/,
        'recent notes page does not disclose lawyer-only notes to contributors'
      );
      await page.waitForSelector('#recent-notes .report-note');
      t.equal(await page.locator('#recent-notes [data-note-form]').count(), 0, 'recent notes page has no composer');

      const newest = page.locator('#recent-notes .report-note').first();
      t.match(await newest.locator('.report-note-body').innerText(), /Edited body with/);
      t.equal(await newest.locator('.report-note-package-link').innerText(), 'perl-Mojolicious');
      t.equal(
        await newest.locator('[data-note-permalink]').getAttribute('href'),
        (await newest.locator('.report-note-package-link').getAttribute('href')) + `#${await newest.getAttribute('id')}`
      );

      await page.locator('#recent-notes [data-notes-sentinel]').scrollIntoViewIfNeeded();
      await page.waitForFunction(() => document.querySelectorAll('#recent-notes .report-note').length >= 24);
      t.equal(
        await page.locator('#recent-notes .report-note-lawyer-only').count(),
        0,
        'contributor recent notes hide lawyer-only notes'
      );
      t.equal(
        await page.locator('#recent-notes .lawyer-only-badge').count(),
        0,
        'contributor recent notes do not show lawyer-only badges'
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
