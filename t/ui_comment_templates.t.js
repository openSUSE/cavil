#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, openAccountMenu, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The comment template admin page. The editor here is the same component as the review comment box,
// but with interactive={false}, because placeholders are authored here rather than filled in.
t.test('Cavil UI - comment templates', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_comment_templates');
  const {page, url, errorLogs} = ui;

  const editor = '.comment-template-form .comment-editor';
  const setBody = text =>
    page.evaluate(
      ([sel, value]) => {
        const view = document.querySelector(sel).cmView;
        view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: value}});
      },
      [`${editor} .cm-editor`, text]
    );
  const rowNames = () => page.locator('#comment-templates .cavil-list-token').allInnerTexts();

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Reachable from the curation menu', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Comment Templates');
      await page.waitForSelector('#comment-templates .cavil-list-table');
      t.match(await page.title(), /Comment templates/, 'on the template page');
    });

    await t.test('The template that ships with Cavil is listed', async t => {
      await page.waitForSelector('#comment-templates .cavil-list-token');
      t.same(await rowNames(), ['Unacceptable-File'], 'seeded template is there');
      const row = page.locator('#comment-templates tbody > tr').first();
      t.match(await row.innerText(), /system/, 'no author, so it is attributed to the system');
      t.match(await row.innerText(), /\[FILE\]/, 'body preview is plain text');
    });

    await t.test('Placeholders are highlighted but not clickable', async t => {
      await page.click('[name="add-template"]');
      await page.waitForSelector(`${editor} .cm-content`);
      await setBody('Please unbundle [FONT] and [ICONS]');
      await page.waitForSelector(`${editor} .cavil-placeholder`);
      t.equal(await page.locator(`${editor} .cavil-placeholder`).count(), 2, 'both placeholders highlighted');
      t.equal(
        await page.innerText('.comment-template-placeholder-count'),
        '2 placeholders',
        'the author sees their syntax parsed'
      );
      t.equal(await page.locator(`${editor} .comment-editor-hints`).count(), 0, 'no click-to-fill hint here');

      // Authoring, not filling in: a click must place an ordinary caret instead of selecting the token
      await page.click(`${editor} .cavil-placeholder`);
      const range = await page.evaluate(sel => {
        const sel2 = document.querySelector(sel).cmView.state.selection.main;
        return {from: sel2.from, to: sel2.to};
      }, `${editor} .cm-editor`);
      t.equal(range.from, range.to, 'click leaves a caret, the placeholder is not selected');
    });

    await t.test('Add, edit and delete a template', async t => {
      await page.fill('#template-name', 'Bundled font');
      await page.click('#template-save');
      await page.waitForFunction(() => document.querySelectorAll('#comment-templates .cavil-list-token').length === 2);
      t.same(await rowNames(), ['Bundled font', 'Unacceptable-File'], 'new template listed, sorted by name');

      // A duplicate name would make the picker ambiguous
      await page.click('[name="add-template"]');
      await page.waitForSelector(`${editor} .cm-content`);
      await page.fill('#template-name', 'Bundled font');
      await setBody('Something else');
      await page.click('#template-save');
      await page.waitForSelector('.toast-danger');
      t.match(await page.innerText('.toast-danger'), /already exists/, 'duplicate name is rejected');
      await page.click('#template-cancel');

      await page.locator('#comment-templates tbody > tr').first().locator('[title="Edit comment template"]').click();
      await page.waitForSelector(`${editor} .cm-content`);
      t.equal(await page.inputValue('#template-name'), 'Bundled font', 'form is prefilled');
      await setBody('Please unbundle [FONT], we cannot ship it');
      await page.click('#template-save');
      await page.waitForSelector('.comment-template-form', {state: 'detached'});
      await page.waitForFunction(() =>
        document.querySelector('#comment-templates tbody > tr').innerText.includes('we cannot ship it')
      );
      t.pass('edited body is listed');

      page.once('dialog', dialog => dialog.accept());
      await page.locator('#comment-templates tbody > tr').first().locator('[title="Delete comment template"]').click();
      await page.waitForFunction(() => document.querySelectorAll('#comment-templates .cavil-list-token').length === 1);
      t.same(await rowNames(), ['Unacceptable-File'], 'back to just the seeded template');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
