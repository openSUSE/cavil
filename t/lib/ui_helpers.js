// Shared helpers for the UI test files (t/ui_*.t.js).
//
// Every UI file launches a fresh Mojolicious daemon via t/wrappers/ui.pl
// (which seeds the standard ui_fixtures), opens a Chromium page, and tears
// it all back down at the end. launchUi() handles that boilerplate so the
// test files stay focused on their actual subject.
//
// The DOM helpers below are the ones that previously lived at the top of
// t/ui.t.js. They are reused across the inline-snippet-editor flows (create
// pattern, propose pattern, propose missing, ignore, ...).

import {UserAgent} from '@mojojs/core';
import ServerStarter from '@mojolicious/server-starter';
import {chromium} from 'playwright';

export async function waitForInlineSnippetEditor(page) {
  await page.waitForSelector('#inline-snippet-editor');
  await page.waitForFunction(() => {
    const root = document.querySelector('#inline-snippet-editor');
    const editor = root?.querySelector('.cm-editor');
    return editor?.cmView && root.querySelector('input[name=license]') && root.querySelector('select[name="risk"]');
  });
}

export async function waitForInlineSnippetEditorClosed(page) {
  await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
}

export async function expandFileDetails(page, fileId) {
  if (!(await page.isVisible(`#file-details-${fileId}`))) {
    await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).click();
  }
  await page.waitForSelector(`#file-details-${fileId} table.snippet`);
}

export async function openCreatePatternEditor(page, fileId, options = {}) {
  await waitForInlineSnippetEditorClosed(page);
  await page.waitForSelector(`#file-details-${fileId} table.snippet`);

  if (options.triggerSelector) {
    await page.locator(options.triggerSelector).click();
    await page
      .locator(`#file-details-${fileId} .dropdown-menu.show a.dropdown-item`)
      .filter({hasText: 'Create Pattern from selection'})
      .first()
      .click();
    await waitForInlineSnippetEditor(page);
    return;
  }

  await page.evaluate(id => {
    const root = document.getElementById(`file-details-${id}`);
    if (!root) throw new Error(`No #file-details-${id}`);
    const items = [...root.querySelectorAll('.dropdown-menu a.dropdown-item')];
    const item = items.find(el => el.textContent.trim() === 'Create Pattern from selection');
    if (!item) throw new Error(`No "Create Pattern from selection" item in #file-details-${id}`);
    item.click();
  }, fileId);
  await waitForInlineSnippetEditor(page);
}

export async function fillInlinePatternBasics(page, licenseName, risk = '3') {
  await page.locator('#inline-snippet-editor input[name=license]').fill(licenseName);
  await page.locator('#inline-snippet-editor select[name="risk"]').selectOption(risk);
}

export async function inlineEditorDoc(page) {
  return page.evaluate(() => document.querySelector('#inline-snippet-editor .cm-editor').cmView.state.doc.toString());
}

export async function replaceInlineEditorDoc(page, text) {
  await page.evaluate(value => {
    const view = document.querySelector('#inline-snippet-editor .cm-editor').cmView;
    view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: value}});
  }, text);
}

export async function openAccountMenu(page) {
  await page.locator('#cavil-menubar .cavil-user-menu > .nav-link').click();
}

// Skip helper for tests guarded by TEST_ONLINE.
// eslint-disable-next-line no-undefined
export const skipUnlessOnline =
  process.env.TEST_ONLINE === undefined ? {skip: 'set TEST_ONLINE to enable this test'} : {};

// Spawn a Mojolicious daemon (via t/wrappers/ui.pl) bound to its own
// Postgres schema, plus a Chromium page wired up to collect console errors.
// The returned `teardown` MUST be awaited (typically from a finally block)
// so a failed test still releases the schema and the browser.
export async function launchUi(schema) {
  // The wrapper reads $ENV{JS_UI_SCHEMA}; setting it on process.env is fine
  // because each .t.js file is its own node process.
  process.env.JS_UI_SCHEMA = schema;

  const server = await ServerStarter.newServer();
  await server.launch('perl', ['t/wrappers/ui.pl']);

  const browser = await chromium.launch(process.env.TEST_HEADLESS === '0' ? {headless: false, slowMo: 500} : {});
  const context = await browser.newContext();
  const page = await context.newPage();
  const url = server.url();
  const performJobs = `${url}/perform_jobs`;

  const errorLogs = [];
  page.on('console', message => {
    if (message.type() === 'error') {
      errorLogs.push(message.text());
    }
  });

  // GitHub Actions can be a bit flaky, so wait for the server to respond.
  const ua = new UserAgent();
  await ua.get(url).catch(error => console.warn(error));

  const teardown = async () => {
    await context.close();
    await browser.close();
    await server.close();
  };

  return {server, browser, context, page, url, performJobs, errorLogs, teardown};
}

// Assert that the only console errors collected are the harmless 400-from-
// expected-failure ones. Every t/ui_*.t.js file calls this once at the end.
export function assertNoUnexpectedConsoleErrors(t, errorLogs) {
  // Some subtests intentionally drive the server to return 400 - the browser
  // logs that as a console error.
  const unexpected = errorLogs.filter(msg => !/status of 400 \(Bad Request\)/.test(msg));
  for (const message of unexpected) {
    t.comment(`Unexpected console error: ${message.replace(/\s+/g, ' ')}`);
  }
  t.equal(unexpected.length, 0, 'no unexpected console errors');
}
