#!/usr/bin/env node
import {
  assertNoUnexpectedConsoleErrors,
  launchUi,
  skipUnlessOnline,
  waitForInlineSnippetEditor,
  waitForInlineSnippetEditorClosed
} from './lib/ui_helpers.js';
import t from 'tap';

// Interactions around the inline snippet editor on a report's match rows:
// the ▲/▼ extend buttons (with cursor-sticky scroll compensation so rapid
// clicks don't force the user to re-aim), Reset selection in the pulldown,
// and the editor button itself surviving across extensions.
t.test('Cavil UI - inline editor on match rows', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_inline_editor');
  const {page, errorLogs, url} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');
    await page.goto(url);
    await page.click('text=Artistic');
    await page.waitForSelector('#license-chart');

    // Wait until at least one auto-expanded risk-9 file has rendered a
    // match-start row. That's where the new ▲ button attaches.
    await page.waitForFunction(() => document.querySelector('.file-container:not(.d-none) tr.match-start'), {
      timeout: 10000
    });

    // Pick the first auto-expanded risk-9 file. Both subtests below operate
    // on the same match-start so the "+" subtest sees a range that has been
    // extended in both directions.
    const fileId = await page.evaluate(() => {
      const row = document.querySelector('.file-container:not(.d-none) tr.match-start');
      return Number(row.id.match(/^line-(\d+)-/)[1]);
    });
    t.ok(fileId, `found auto-expanded risk-9 file: file-${fileId}`);

    await page.locator(`#file-details-${fileId} tr.match-start`).first().scrollIntoViewIfNeeded();

    const readStartLine = () =>
      page.evaluate(
        fid => Number(document.querySelector(`#file-details-${fid} tr.match-start`).id.match(/-(\d+)$/)[1]),
        fileId
      );
    const readEndLine = () =>
      page.evaluate(fid => {
        const btn = document.querySelector(`#file-details-${fid} [id^="extend-down-${fid}-"]`);
        return btn ? Number(btn.id.match(/-(\d+)$/)[1]) : null;
      }, fileId);
    const buttonTop = id =>
      page.evaluate(elId => {
        const el = document.getElementById(elId);
        return el ? el.getBoundingClientRect().top : null;
      }, id);

    // After a click, the source refetch is async and the scroll-compensation
    // watcher re-aligns the button across several frames (it keeps correcting
    // until the freshly laid-out rows stop shifting). A fixed rAF count races
    // that on a loaded machine, so wait for the page to actually go quiescent:
    // poll until window.scrollY holds steady for two consecutive frames.
    const waitForCompensation = () =>
      page.evaluate(
        () =>
          new Promise(resolve => {
            let prev = null;
            let stable = 0;
            let frames = 0;
            const tick = () => {
              const y = window.scrollY;
              if (prev !== null && Math.abs(y - prev) <= 0.5) stable += 1;
              else stable = 0;
              prev = y;
              if (stable >= 2 || (frames += 1) > 60) resolve();
              else requestAnimationFrame(tick);
            };
            requestAnimationFrame(tick);
          })
      );

    const start0 = await readStartLine();
    const end0 = await readEndLine();

    await t.test('Extend up multiple times — selection grows, button stays under cursor', async t => {
      t.ok(start0 > 3, `match-start at line ${start0} has room to extend three lines up`);

      let currentLine = start0;
      let referenceTop = null;

      for (let i = 0; i < 3; i++) {
        const btnId = `extend-up-${fileId}-${currentLine}`;
        const btn = page.locator(`#${btnId}`);
        await btn.hover();
        const beforeTop = await buttonTop(btnId);
        if (referenceTop === null) referenceTop = beforeTop;

        await btn.click();

        const nextLine = currentLine - 1;
        const nextId = `extend-up-${fileId}-${nextLine}`;
        await page.locator(`#${nextId}`).waitFor({state: 'attached', timeout: 5000});
        await waitForCompensation();

        const newStart = await readStartLine();
        t.equal(newStart, nextLine, `click ${i + 1}: match-start decremented to ${nextLine}`);

        const afterTop = await buttonTop(nextId);
        const drift = Math.abs(afterTop - referenceTop);
        t.ok(drift <= 5, `click ${i + 1}: cursor-stick keeps ▲ within 5px (drift ${drift.toFixed(2)}px)`);

        currentLine = nextLine;
      }

      t.equal(currentLine, start0 - 3, 'three clicks decremented the match-start by exactly 3');
    });

    await t.test('Extend down multiple times — selection grows, button stays under cursor', async t => {
      t.ok(end0, `match has a ▼ button at line ${end0}`);

      // Guarantee room below the report so the cursor-stick watcher's
      // `window.scrollBy(0, +12)` isn't clipped to zero. Without this, in CI
      // the ▼ button sits close enough to the document's scroll-max that the
      // compensation can't actually scroll, drift stays at one row height,
      // and the test fails. The match-start case above works without help
      // because it scrolls upward (room above is plentiful).
      await page.evaluate(() => {
        const spacer = document.createElement('div');
        spacer.id = 'test-extend-down-spacer';
        spacer.style.height = '2000px';
        document.body.appendChild(spacer);
      });

      let currentLine = end0;
      let referenceTop = null;

      for (let i = 0; i < 3; i++) {
        const btnId = `extend-down-${fileId}-${currentLine}`;
        const btn = page.locator(`#${btnId}`);
        await btn.hover();
        const beforeTop = await buttonTop(btnId);
        if (referenceTop === null) referenceTop = beforeTop;

        await btn.click();

        const nextLine = currentLine + 1;
        const nextId = `extend-down-${fileId}-${nextLine}`;
        await page.locator(`#${nextId}`).waitFor({state: 'attached', timeout: 5000});
        await waitForCompensation();

        const newEnd = await readEndLine();
        t.equal(newEnd, nextLine, `click ${i + 1}: match-end incremented to ${nextLine}`);

        const afterTop = await buttonTop(nextId);
        const drift = Math.abs(afterTop - referenceTop);
        t.ok(drift <= 5, `click ${i + 1}: cursor-stick keeps ▼ within 5px (drift ${drift.toFixed(2)}px)`);

        currentLine = nextLine;
      }

      t.equal(currentLine, end0 + 3, 'three clicks incremented the match-end by exactly 3');

      await page.evaluate(() => document.getElementById('test-extend-down-spacer')?.remove());
    });

    await t.test('Reset selection in the pulldown undoes the extensions', async t => {
      // After the ▲/▼ subtests above, the match has been pushed out by 3
      // lines in each direction. "Reset selection" in the pulldown should
      // snap it back to the original (start0, end0) boundaries.
      const matchStartRow = page.locator(`#file-details-${fileId} tr.match-start`).first();
      await matchStartRow.hover();
      const trigger = page.locator(`#file-details-${fileId} [id^="dropdownMenuLink-${fileId}-"]`).first();
      await trigger.click();
      const resetItem = page
        .locator(`#file-details-${fileId} .dropdown-menu.show a.dropdown-item`)
        .filter({hasText: 'Reset selection'})
        .first();
      await resetItem.waitFor({state: 'visible'});
      await resetItem.click();

      // Wait for the lines array to refresh and the ▲ button on the
      // ORIGINAL match-start line to come back. start0/end0 were captured at
      // the very top of the test file before any extending.
      const originalUpId = `extend-up-${fileId}-${start0}`;
      await page.locator(`#${originalUpId}`).waitFor({state: 'attached', timeout: 5000});
      const restoredStart = await readStartLine();
      const restoredEnd = await readEndLine();
      t.equal(restoredStart, start0, `match-start restored to ${start0}`);
      t.equal(restoredEnd, end0, `match-end restored to ${end0}`);
    });

    await t.test('Inline editor button stays clickable after extending', async t => {
      // Re-extend down once so the displayed range no longer aligns with a
      // known snippet (the previous subtest reset it). The inline editor
      // button must stay rendered (used to be gated on line[1].snippet, which
      // is dropped after extending) AND must open the editor without hanging
      // — the click handler has to coerce the server's synthetic snippet=0
      // marker to null, otherwise openEditor skips the from_file fetch and
      // mounts SnippetEditor against a non-existent snippet.
      const reExtendStartRow = page.locator(`#file-details-${fileId} tr.match-start`).first();
      await reExtendStartRow.hover();
      await page.locator(`#extend-down-${fileId}-${end0}`).click();
      await page.locator(`#extend-down-${fileId}-${end0 + 1}`).waitFor({state: 'attached', timeout: 5000});

      const matchStartRow = page.locator(`#file-details-${fileId} tr.match-start`).first();
      await matchStartRow.scrollIntoViewIfNeeded();
      await matchStartRow.hover();

      const editorBtn = matchStartRow.locator('td.quick-actions a').first();
      await editorBtn.waitFor({state: 'attached', timeout: 5000});
      t.equal(await editorBtn.count(), 1, 'inline editor button still present on the extended match-start row');

      const href = await editorBtn.getAttribute('href');
      t.match(href, /^\/snippets\/from_file\/\d+\/\d+\/\d+/, 'href targets the widened selection');

      await editorBtn.click();
      await waitForInlineSnippetEditor(page);
      t.pass('inline editor opens from the extended selection (does not hang on snippet=0)');

      const patternLine = page.locator('#inline-snippet-editor .cm-line.found-pattern').first();
      await patternLine.waitFor({state: 'visible', timeout: 5000});
      const clickPoint = await patternLine.evaluate(el => {
        const rect = el.getBoundingClientRect();
        return {x: rect.left + Math.min(40, Math.max(1, rect.width / 2)), y: rect.top + rect.height / 2};
      });
      await page.mouse.click(clickPoint.x, clickPoint.y);
      await page.locator('.cavil-pattern-tip-floating .cavil-pattern-tip-card').waitFor({state: 'visible'});
      const tooltipPlacement = await page.evaluate(point => {
        const line = document.querySelector('#inline-snippet-editor .cm-line.found-pattern');
        const tip = document.querySelector('.cavil-pattern-tip-floating');
        const lineRect = line.getBoundingClientRect();
        const tipRect = tip.getBoundingClientRect();
        const containsClick =
          point.x >= tipRect.left && point.x <= tipRect.right && point.y >= tipRect.top && point.y <= tipRect.bottom;
        const coversLine = tipRect.top < lineRect.bottom && tipRect.bottom > lineRect.top;
        return {containsClick, coversLine};
      }, clickPoint);
      t.notOk(tooltipPlacement.containsClick, 'pattern tooltip does not open under the click point');
      t.notOk(tooltipPlacement.coversLine, 'pattern tooltip does not cover the clicked editor line');

      await page.mouse.move(clickPoint.x + 20, clickPoint.y);
      await page.waitForFunction(() => document.querySelectorAll('.cavil-pattern-tip').length === 1);
      t.equal(
        await page.locator('.cavil-pattern-tip').count(),
        1,
        'hover does not duplicate the persistent pattern tooltip'
      );

      await page.locator('#inline-snippet-editor [data-action="cancel"]').click();
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
