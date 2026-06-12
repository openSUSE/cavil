#!/usr/bin/env node
import {UserAgent} from '@mojojs/core';
import ServerStarter from '@mojolicious/server-starter';
import {chromium} from 'playwright';
import t from 'tap';

// eslint-disable-next-line no-undefined
const skip = process.env.TEST_ONLINE === undefined ? {skip: 'set TEST_ONLINE to enable this test'} : {};

async function waitForInlineSnippetEditor(page) {
  await page.waitForSelector('#inline-snippet-editor');
  await page.waitForFunction(() => {
    const root = document.querySelector('#inline-snippet-editor');
    const editor = root?.querySelector('.cm-editor');
    return editor?.cmView && root.querySelector('input[name=license]') && root.querySelector('select[name="risk"]');
  });
}

async function waitForInlineSnippetEditorClosed(page) {
  await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
}

async function expandFileDetails(page, fileId) {
  if (!(await page.isVisible(`#file-details-${fileId}`))) {
    await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).click();
  }
  await page.waitForSelector(`#file-details-${fileId} table.snippet`);
}

async function openCreatePatternEditor(page, fileId, options = {}) {
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

async function fillInlinePatternBasics(page, licenseName, risk = '3') {
  await page.locator('#inline-snippet-editor input[name=license]').fill(licenseName);
  await page.locator('#inline-snippet-editor select[name="risk"]').selectOption(risk);
}

async function inlineEditorDoc(page) {
  return page.evaluate(() => document.querySelector('#inline-snippet-editor .cm-editor').cmView.state.doc.toString());
}

async function replaceInlineEditorDoc(page, text) {
  await page.evaluate(value => {
    const view = document.querySelector('#inline-snippet-editor .cm-editor').cmView;
    view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: value}});
  }, text);
}

async function openAccountMenu(page) {
  await page.locator('#cavil-menubar .cavil-user-menu > .nav-link').click();
}

// Wrapper script with fixtures can be found in "t/wrappers/ui.pl"
t.test('Test cavil ui', skip, async t => {
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

  // GitHub actions can be a bit flaky, so better wait for the server
  const ua = new UserAgent();
  await ua.get(url).catch(error => console.warn(error));

  await t.test('Public', async t => {
    await t.test('Navigation', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Open Reviews');
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Recently Reviewed');
      t.equal(await page.innerText('title'), 'List recent reviews');
      await page.click('text=Products');
      t.equal(await page.innerText('title'), 'List products');
    });

    await t.test('Open reviews (priority 2+)', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.waitForSelector('#open-reviews tbody > tr:nth-child(10)');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), /Artistic/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(2)'), 'mojo#2');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(5)'), /GPL-1\.0/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(2)'), 'obs#123456');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(4)'), 'harbor-helm');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(5)'), /Unknown/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(4) > td:nth-child(2)'), 'test#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(4) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(4) > td:nth-child(4)'), 'perl-UI-Test1');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(4) > td:nth-child(5)'), 'not yet imported');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(2)'), 'test#6');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(4)'), 'perl-UI-Test6');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(5)'), 'not yet imported');

      await page.click('text=Next');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'test#7');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-UI-Test7');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'not yet imported');

      await page.click('text=Previous');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), /Artistic/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(2)'), 'mojo#2');
    });

    await t.test('Open reviews (with priority 1)', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.selectOption('select.cavil-pkg-priority', '1');
      await page.waitForSelector('#open-reviews tbody > tr:nth-child(10)');

      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), /Artistic/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(2)'), 'mojo#2');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(5)'), /GPL-1\.0/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(2)'), 'obs#123456');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(4)'), 'harbor-helm');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(5)'), /Unknown/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(4) > td:nth-child(2)'), 'test#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(4) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(4) > td:nth-child(4)'), 'perl-UI-Test1');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(4) > td:nth-child(5)'), 'not yet imported');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(2)'), 'test#6');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(4)'), 'perl-UI-Test6');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(5)'), 'not yet imported');

      await page.click('text=Next');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'test#7');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-UI-Test7');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'not yet imported');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(2)'), 'test#17');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(4)'), 'perl-UI-Test17');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(10) > td:nth-child(5)'), 'not yet imported');

      await page.click('text=Next');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'test#18');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-UI-Test18');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'not yet imported');

      await page.click('text=Previous');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'test#7');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-UI-Test7');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'not yet imported');

      await page.click('text=Previous');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), /Artistic/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(2) > td:nth-child(2)'), 'mojo#2');
    });

    await t.test('Search', async t => {
      await page.goto(url);
      await page.click('text=perl-Mojolicious');
      await page.waitForSelector('#review-search tbody > tr:nth-child(1)');
      t.equal(await page.innerText('title'), 'Search Results');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /perl-Mojolicious/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(6)'), /GPL/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(5)'), /perl-Mojolicious/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(6)'), /Artistic/);
    });
  });

  await t.test('Admin', async t => {
    await t.test('Login', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Login');
      t.equal(await page.innerText('title'), 'List open reviews');
      await openAccountMenu(page);
      await page.click('text=Logout');
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Login');
      t.equal(await page.innerText('title'), 'List open reviews');
    });

    await t.test('Minion dashboard', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text="Minion Dashboard"');
      t.match(await page.innerText('title'), /Minion/);
      await page.click('text=Back to Site');
      t.equal(await page.innerText('title'), 'List open reviews');
    });

    await t.test('Reports', async t => {
      await page.goto(url);
      await page.click('text=Unknown');
      t.equal(await page.innerText('title'), 'Report for harbor-helm');
      await page.click('text=Open Reviews');
      t.equal(await page.innerText('title'), 'List open reviews');

      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
    });

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

    await t.test('Navigation (logged in)', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Open Reviews');
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Recently Reviewed');
      t.equal(await page.innerText('title'), 'List recent reviews');
      await page.click('text=Products');
      t.equal(await page.innerText('title'), 'List products');
      await page.click('text=Licenses');
      t.equal(await page.innerText('title'), 'List licenses');
    });

    await t.test('Open reviews (logged in)', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.waitForSelector('#open-reviews tbody > tr:nth-child(10)');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), /Artistic/);

      await page.click('text=Next');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'test#7');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-UI-Test7');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'not yet imported');

      await page.click('text=Previous');
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(2)'), 'mojo#1');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(3)'), /ago/);
      t.equal(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(4)'), 'perl-Mojolicious');
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), /Artistic/);
    });

    await t.test('Licenses', async t => {
      await page.goto(url);
      await page.click('text=Licenses');
      t.equal(await page.innerText('title'), 'List licenses');
      await page.click('text=Artistic-2.0');
      t.equal(await page.innerText('title'), 'License details of Artistic-2.0');
      await page.waitForSelector('#license-details .license-pattern-card');
      t.match(await page.innerText('#license-details .license-details-header'), /Artistic-2.0/);
      t.match(await page.innerText('#license-details .license-details-header'), /patterns/);
      t.ok(
        (await page.locator('#license-details button[data-action="edit-pattern-inline"]').count()) > 0,
        'admin sees inline edit buttons'
      );

      const initialCards = await page.locator('#license-details .license-pattern-card').count();
      t.ok(initialCards > 0, 'license detail has pattern cards');
      await page.locator('#license-details input[placeholder="Filter patterns"]').fill('this-filter-matches-nothing');
      await page.waitForSelector('#license-details .license-empty-state');
      t.equal(await page.locator('#license-details .license-pattern-card').count(), 0, 'filter can hide all cards');
      await page.locator('#license-details input[placeholder="Filter patterns"]').fill('');
      await page.waitForFunction(
        count => document.querySelectorAll('#license-details .license-pattern-card').length === count,
        initialCards
      );

      const spdx = await page.locator('#license-details input[name="spdx"]').inputValue();
      await page.locator('#license-details input[name="spdx"]').fill(spdx);
      await page.locator('#license-details .license-spdx-form button[type="submit"]').click();
      await page.waitForSelector('#license-details .toast-item.toast-success');
      t.match(await page.innerText('#license-details .toast-item'), /patterns updated/);
    });

    await t.test('Search (logged in)', async t => {
      await page.goto(url);
      await page.locator('[placeholder="Search packages"]').click();
      await page.locator('[placeholder="Search packages"]').fill('perl-Mojolicious');
      await page.locator('[placeholder="Search packages"]').press('Enter');
      await page.waitForURL(`${url}/search?q=perl-Mojolicious`);
      t.equal(await page.innerText('title'), 'Search Results');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /perl-Mojolicious/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(6)'), /GPL/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(5)'), /perl-Mojolicious/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(6)'), /Artistic/);
    });

    await t.test('Expand hidden file (and open it in a new tab)', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // File 6 lives in the Apache-2.0 risk-5 bucket. With the inflated
      // fixture the bucket holds many files so its file list starts collapsed —
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

      // Click a missed-file link (file 7 is auto-expanded as a risk-9 file) —
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
      // fixture the bucket holds many files so its file list starts collapsed —
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

      // Shortcut must not fire while typing into an editor input — open the
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

    await t.test('File list cap per license (min_files_short_report)', async t => {
      // The Apache-2.0 bucket has been inflated to 102 unique files by the test
      // fixture. The in-bucket file list must be capped to
      // min_files_short_report + 1 = 21 to keep huge reports navigable.
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const apache = page.locator('#risk-5 > li').filter({hasText: 'Apache-2.0'}).first();
      t.match(await apache.innerText(), /102 files/);
      t.equal(await apache.locator('a.file-link').count(), 21);
      t.match(await apache.textContent(), /81 more/);
    });

    await t.test('Large unresolved report omits inline preview indicator', async t => {
      // mojo#1 has only a handful of unresolved matches, well under the
      // max_expanded_files cap — the indicator must stay out of the DOM.
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      t.equal(
        await page.locator('#hidden-previews-notice').count(),
        0,
        'no indicator when missed-file count is under the cap'
      );

      // synthetic-many-unresolved is a fixture package with 110 files, each
      // containing one unresolved keyword match (real index pipeline, real
      // sources). Navigate via the priority-1 open-reviews page → row link
      // so we cover the actual user flow, not just the report URL. The
      // report has no license matches, so there's no #license-chart to wait
      // on — wait for the unmatched-files block to confirm the report loaded.
      await page.goto(url);
      await page.selectOption('select.cavil-pkg-priority', '1');
      await page.locator('#cavil-pkg-filter input[placeholder="Filter"]').fill('synth');
      const synthRow = page.locator('#open-reviews tbody > tr').filter({hasText: 'zzz_synth#1'}).first();
      await synthRow.waitFor();
      await synthRow.locator('a[href^="/reviews/details/"]').click();
      t.equal(await page.innerText('title'), 'Report for synthetic-many-unresolved');
      await page.waitForSelector('#unmatched-files');
      t.match(await page.innerText('#unmatched-files'), /110 files/);
      t.equal(await page.locator('#hidden-previews-notice').count(), 0, 'inline preview indicator is not shown');
    });

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

      // The auto-scroll must put the file roughly into view (top of viewport or
      // already visible). Allow some slack because smooth-scroll is async.
      await page.waitForFunction(
        id => {
          const el = document.getElementById(`file-details-${id}`);
          if (!el) return false;
          const r = el.getBoundingClientRect();
          return r.bottom >= 0 && r.top <= window.innerHeight;
        },
        targetFileId,
        {timeout: 5000}
      );
      t.pass(`file-${targetFileId} scrolled into the viewport`);
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

      // Verify the pending indicator (the badge inside the file source) is in view
      await page
        .waitForFunction(
          id => {
            const el = document.getElementById(`pending-indicator-${id}`);
            if (!el) return false;
            const r = el.getBoundingClientRect();
            return r.top >= -50 && r.top <= window.innerHeight;
          },
          Number(fileId) === Number(fileId) ? 1 : 0,
          {timeout: 5000}
        )
        .catch(() => {
          // The exact action ID isn't stable enough to query precisely, so just
          // assert that *some* pending-indicator landed in view.
        });
      const indicatorInView = await page.evaluate(() => {
        const indicators = document.querySelectorAll('[id^="pending-indicator-"]');
        for (const el of indicators) {
          const r = el.getBoundingClientRect();
          if (r.top >= -50 && r.top <= window.innerHeight) return true;
        }
        return false;
      });
      t.ok(indicatorInView, 'pending indicator is scrolled into view');

      // Clean up so any later subtest starts with an empty queue
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      await page.locator('#pending-actions-widget button[title="Clear all"]').click();
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
      t.notEqual(trimmedText, originalText, 'doc changed after smart edit');
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

      // Wait for the reindex POST to complete before triggering job processing —
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

    await t.test('Propose missing license → page → dismiss', async t => {
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

      // Error path: submit with the license field empty - server returns 400 and
      // EditSnippet.vue should surface the message in the alert-danger banner
      // without navigating away.
      const [errResp] = await Promise.all([
        editorPage.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        editorPage.locator('#edit-snippet button[data-action="create-pattern"]').click()
      ]);
      t.equal(errResp.status(), 400);
      await editorPage.waitForSelector('#edit-snippet .alert-danger');
      t.match(await editorPage.innerText('#edit-snippet .alert-danger'), /Missing required field: license/);
      t.match(editorPage.url(), /\/snippet\/edit\/\d+/, 'still on the editor page after error');

      // Success path: fill the form and append a unique marker into the
      // CodeMirror editor so the resulting pattern doesn't md5-collide with one
      // created by the prior batch subtests. Then retry - EditSnippet.vue
      // redirects to the new pattern's edit page on success.
      await editorPage.locator('#edit-snippet input[name=license]').fill('Page-Editor-License-1.0');
      await editorPage.locator('#edit-snippet select[name="risk"]').selectOption('2');
      await editorPage.locator('#edit-snippet .cm-editor .cm-content').click();
      await editorPage.keyboard.press('Control+End');
      await editorPage.keyboard.type('\nunique-page-mode-test-marker');
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

    await t.test('Missing Licenses', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Missing Licenses');
      t.equal(await page.innerText('title'), 'Missing Licenses');
      await page.waitForSelector('#missing-licenses > div > div:nth-child(2)');
      t.equal(
        await page.innerText('#missing-licenses > div > div:nth-child(2)'),
        'There are currently no missing licenses.'
      );
    });

    await t.test('Change Proposals', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Change Proposals');
      t.equal(await page.innerText('title'), 'Change Proposals');
      await page.waitForSelector('#proposed-patterns > div > div:nth-child(3)');
      t.equal(
        await page.innerText('#proposed-patterns > div > div:nth-child(3)'),
        'There are currently no proposed changes.'
      );
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

    await t.test('Statistics', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=Statistics');
      t.equal(await page.innerText('title'), 'Statistics');
      await page.waitForSelector('#statistics .stats-body');
      t.equal(await page.innerText('#statistics .stats-body'), '25');
    });

    await t.test('API Keys', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('text=API Keys');
      t.equal(await page.innerText('title'), 'API Keys');
      await page.waitForSelector('#api-keys tbody > tr:nth-child(1)');
      t.equal(await page.innerText('#api-keys tbody > tr:nth-child(1) > td:nth-child(1)'), 'No API keys found.');
    });

    await t.test('Notes tab (admin)', async t => {
      // Earlier subtests resolved/reindexed mojo#1 (id=1) but never deleted
      // its name, so the 25 seed notes on package_name=perl-Mojolicious
      // are still visible from both review #1 and review #2.
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

    await t.test('Obsolete package without legal report still opens Notes tab', async t => {
      await page.goto(`${url}/test/obsolete_without_report/2`);
      t.equal(await page.locator('body').innerText(), 'ok');

      await page.goto(`${url}/reviews/details/2`);
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#report-tabs');
      await page.waitForSelector('[data-obsolete-report-notice]');
      await page.waitForSelector('[data-report-unavailable]');
      t.match(
        await page.locator('[data-report-unavailable]').innerText(),
        /no longer available/,
        'missing obsolete report is terminal instead of a spinner'
      );
      t.equal(await page.locator('#ajax-status').count(), 0, 'report pane is not left polling forever');

      await page.click('[data-tab="notes"]');
      await page.waitForSelector('#report-notes-pane.is-active .report-note');
      t.ok(await page.locator('#report-notes-pane.is-active .report-note').count(), 'notes load for obsolete package');

      await page.goto(`${url}/test/restore_obsolete_without_report/2`);
      t.equal(await page.locator('body').innerText(), 'ok');
    });

    await t.test('Recent Notes page (admin)', async t => {
      await page.goto(url);
      await openAccountMenu(page);
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
  });

  await t.test('Contributor', async t => {
    await t.test('Snippet editor action layout', async t => {
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

    await t.test('Notes tab hides lawyer-only data from contributors', async t => {
      // The Notes admin subtest left 25 visible notes on
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
  });

  t.test('Console errors', t => {
    // The batch "error surfaces per action" test intentionally drives the
    // server to return 400 - the browser logs that as a console error.
    const unexpected = errorLogs.filter(msg => !/status of 400 \(Bad Request\)/.test(msg));
    t.same(unexpected, []);
    t.end();
  });

  await context.close();
  await browser.close();
  await server.close();
});
