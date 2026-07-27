#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The review comment box on the report page. It is a CodeMirror editor rather than a textarea, so
// everything a textarea gives away for free (undo, tabbing out of the field) has to be tested here.
t.test('Cavil UI - review comment editor', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_report_comment');
  const {page, url, errorLogs} = ui;

  const editor = '#pkg-review .comment-editor';
  const docText = () =>
    page.evaluate(sel => document.querySelector(sel).cmView.state.doc.toString(), `${editor} .cm-editor`);
  const selection = () =>
    page.evaluate(sel => {
      const range = document.querySelector(sel).cmView.state.selection.main;
      return {from: range.from, to: range.to};
    }, `${editor} .cm-editor`);
  const setDoc = text =>
    page.evaluate(
      ([sel, value]) => {
        const view = document.querySelector(sel).cmView;
        view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: value}});
        view.focus();
      },
      [`${editor} .cm-editor`, text]
    );
  // The report is found the way a reviewer finds it, but only once: reviewing a package takes it off
  // the dashboard, so later subtests reopen it by the link the dashboard gave us
  let reportUrl = null;
  const openReport = async () => {
    if (reportUrl === null) {
      await page.goto(url);
      await page.click('text=Artistic');
      await page.waitForSelector('#license-chart');
      reportUrl = page.url();
    } else {
      await page.goto(reportUrl);
      await page.waitForSelector('#license-chart');
    }
    await page.waitForSelector(`${editor} .cm-content`);
  };

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Editor replaces the textarea', async t => {
      await openReport();
      t.equal(await page.locator('#pkg-review textarea').count(), 0, 'no textarea left');
      t.ok(
        await page.evaluate(sel => Boolean(document.querySelector(sel).cmView), `${editor} .cm-editor`),
        'CodeMirror view is exposed'
      );
      t.equal(await page.innerText(`${editor} .comment-editor-label`), 'Comment', 'labelled');
      t.equal(await page.innerText(`${editor} .cm-placeholder`), 'Reviewed ok', 'empty hint preserved');
      t.equal(await page.locator(`${editor} .cm-lineNumbers`).count(), 0, 'no line numbers');
    });

    await t.test('Placeholders are highlighted and click to fill', async t => {
      await openReport();
      await page.click(`${editor} .cm-content`);
      await page.keyboard.type('Please fix [REASON] now');
      await page.waitForSelector(`${editor} .cavil-placeholder`);
      t.equal(await page.locator(`${editor} .cavil-placeholder`).count(), 1, 'exactly one placeholder');
      t.equal(await page.innerText(`${editor} .cavil-placeholder`), '[REASON]', 'the token is highlighted');
      t.match(await page.innerText(`${editor} .comment-editor-hints`), /Click a/, 'hint line appears');

      await page.click(`${editor} .cavil-placeholder`);
      t.same(await selection(), {from: 11, to: 19}, 'click selects the whole placeholder');
      await page.keyboard.type('a license conflict');
      t.equal(await docText(), 'Please fix a license conflict now', 'typing replaces the placeholder');
      t.equal(await page.locator(`${editor} .cavil-placeholder`).count(), 0, 'no placeholder left');
      t.equal(await page.locator(`${editor} .comment-editor-hints`).count(), 0, 'hint line goes away');
    });

    await t.test('Tab jumps between placeholders and then leaves the editor', async t => {
      await openReport();
      await setDoc('[ONE] and [TWO]');
      await page.evaluate(
        sel => document.querySelector(sel).cmView.dispatch({selection: {anchor: 0}}),
        `${editor} .cm-editor`
      );

      await page.keyboard.press('Tab');
      t.same(await selection(), {from: 10, to: 15}, 'Tab jumps to the next placeholder');
      await page.keyboard.press('Shift+Tab');
      t.same(await selection(), {from: 0, to: 5}, 'Shift-Tab jumps back');

      // No wrap around, otherwise a keyboard user is trapped in the editor forever
      await page.keyboard.press('Tab');
      await page.keyboard.press('Tab');
      t.notOk(
        await page.evaluate(() => document.activeElement.classList.contains('cm-content')),
        'Tab past the last placeholder leaves the editor'
      );
    });

    await t.test('Tab leaves immediately without placeholders', async t => {
      await openReport();
      await setDoc('Just a plain comment');
      await page.keyboard.press('Tab');
      t.notOk(
        await page.evaluate(() => document.activeElement.classList.contains('cm-content')),
        'Tab behaves like it would in a textarea'
      );
    });

    await t.test('Escape leaves the editor', async t => {
      await openReport();
      await setDoc('[ONE] and [TWO]');
      await page.keyboard.press('Escape');
      t.notOk(
        await page.evaluate(() => document.activeElement.classList.contains('cm-content')),
        'Escape blurs the editor'
      );
    });

    await t.test('Undo and redo work with the keyboard and the buttons', async t => {
      await openReport();
      const undoButton = page.locator(`${editor} [data-action="undo"]`);
      const redoButton = page.locator(`${editor} [data-action="redo"]`);
      t.ok(await undoButton.isDisabled(), 'undo is disabled on a pristine editor');
      t.ok(await redoButton.isDisabled(), 'redo is disabled on a pristine editor');

      await page.click(`${editor} .cm-content`);
      await page.keyboard.type('First');
      await page.waitForFunction(sel => !document.querySelector(sel).disabled, `${editor} [data-action="undo"]`);
      t.notOk(await undoButton.isDisabled(), 'undo enables after typing');
      t.ok(await redoButton.isDisabled(), 'nothing to redo yet');

      await page.keyboard.press('Control+z');
      t.equal(await docText(), '', 'Ctrl-Z undoes');
      await page.waitForFunction(sel => !document.querySelector(sel).disabled, `${editor} [data-action="redo"]`);
      await page.keyboard.press('Control+y');
      t.equal(await docText(), 'First', 'Ctrl-Y redoes');

      await undoButton.click();
      t.equal(await docText(), '', 'undo button restores the previous text');
      await redoButton.click();
      t.equal(await docText(), 'First', 'redo button puts it back');

      // Typing after an undo discards the redo history, the same as in any editor
      await undoButton.click();
      await page.keyboard.type('Second');
      await page.waitForFunction(sel => document.querySelector(sel).disabled, `${editor} [data-action="redo"]`);
      t.ok(await redoButton.isDisabled(), 'a new edit clears the redo history');
      await undoButton.click();
      t.equal(await docText(), '', 'back to an empty box for the next subtest');
    });

    await t.test('Templates are inserted from the picker', async t => {
      await openReport();
      const pick = async () => {
        await page.click('#template-picker-btn');
        await page.click('.template-picker-item:has-text("Unacceptable-File")');
      };

      await pick();
      const text = await docText();
      t.match(text, /is licensed under \[LICENSE\]/, 'template body landed in the box');
      const first = text.indexOf('[FILE]');
      t.same(await selection(), {from: first, to: first + 6}, 'first placeholder is selected, ready to type over');

      // Picking again without typing in between corrects the first pick instead of stacking on it
      await pick();
      t.equal((await docText()).match(/\[LICENSE\]/g).length, 1, 'a second pick replaces the untouched body');

      // But it must never silently overwrite something the reviewer wrote themselves
      await setDoc('Rejected outright.');
      await pick();
      t.match(await docText(), /^Rejected outright\.\n\nThis package cannot/, 'appended after a blank line');

      await page.keyboard.press('Control+End');
      await page.keyboard.type('\nThanks.');
      await pick();
      const appended = await docText();
      t.equal(appended.match(/\[LICENSE\]/g).length, 2, 'an edited template is kept and appended to');
      t.match(appended, /^Rejected outright\./, 'the reviewer text is still there');
    });

    await t.test('Unfilled placeholders are a warning, not a block', async t => {
      await openReport();
      await setDoc('Rejected because of [REASON]');

      let asked = null;
      page.once('dialog', dialog => {
        asked = dialog.message();
        dialog.dismiss();
      });
      await page.click('#unacceptable');
      await page.waitForFunction(() => true);
      t.match(asked, /REASON/, 'the unfilled token is named');
      t.equal(await page.innerText('#pkg-state'), 'new', 'dismissing does not submit');

      page.once('dialog', dialog => dialog.accept());
      await Promise.all([
        page.waitForResponse(
          res => res.url().includes('/reviews/review_package/') && res.request().method() === 'POST'
        ),
        page.click('#unacceptable')
      ]);
      await page.waitForFunction(() => document.querySelector('#pkg-state').innerText.trim() === 'unacceptable');
      t.equal(await page.innerText('#pkg-state'), 'unacceptable', 'accepting the warning submits anyway');
    });

    await t.test('Comment is submitted and shown as plain text', async t => {
      await openReport();
      await setDoc('Rejected <b>because</b> of\nthe bundled font');
      await Promise.all([
        page.waitForResponse(
          res => res.url().includes('/reviews/review_package/') && res.request().method() === 'POST'
        ),
        page.click('#unacceptable')
      ]);
      await page.waitForFunction(() => document.querySelector('#pkg-state').innerText.trim() === 'unacceptable');
      t.equal(await page.innerText('#pkg-state'), 'unacceptable', 'state badge updated in place');
      t.equal(await docText(), 'Rejected <b>because</b> of\nthe bundled font', 'comment survives the refresh');

      await page.click('text=Recently Reviewed');
      await page.waitForSelector('#recent-reviews tbody > tr:nth-child(1)');
      const comment = page.locator('#recent-reviews .cavil-list-comment-body').first();
      t.equal(
        await comment.innerText(),
        'Rejected <b>because</b> of\nthe bundled font',
        'comment renders as plain multi-line text, HTML is not interpolated'
      );
      t.equal(await comment.locator('b').count(), 0, 'no markup was injected');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
