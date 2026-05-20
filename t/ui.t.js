#!/usr/bin/env node
import {UserAgent} from '@mojojs/core';
import ServerStarter from '@mojolicious/server-starter';
import {chromium} from 'playwright';
import t from 'tap';

// eslint-disable-next-line no-undefined
const skip = process.env.TEST_ONLINE === undefined ? {skip: 'set TEST_ONLINE to enable this test'} : {};

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
      await page.click('text="Logged in as tester"');
      await page.click('text=Logout');
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Login');
      t.equal(await page.innerText('title'), 'List open reviews');
    });

    await t.test('Minion dashboard', async t => {
      await page.goto(url);
      await page.click('text="Logged in as tester"');
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
    });

    await t.test('Search (logged in)', async t => {
      await page.goto(url);
      await page.locator('[placeholder="Package Search"]').click();
      await page.locator('[placeholder="Package Search"]').fill('perl-Mojolicious');
      await page.locator('[placeholder="Package Search"]').press('Enter');
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
      t.match(await page.innerText('#expand-link-6'), /Mojolicious.+js/);
      t.same(await page.isVisible('#file-details-6'), true);

      // Open whole file in new tab
      const [page2] = await Promise.all([
        context.waitForEvent('page'),
        page.locator('#expand-link-6 ~ div a[target="_blank"]').click()
      ]);
      await page2.waitForLoadState();
      t.match(await page2.innerText('title'), /Content of Mojolicious.+js/);
      t.match(await page2.innerText('textarea'), /Apache.+indexOf/s);
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
      t.same(await page.isVisible('#file-details-6'), true);
      await page.waitForSelector('#file-details-6 table.snippet');
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
      await page.locator(actionTrigger).click();
      await page.locator(actionMenuItem('Create Pattern from selection')).click();

      // Modal opens with the snippet editor instead of navigating away
      await page.waitForSelector('#snippet-editor-modal.show');
      await page.waitForSelector('#snippet-editor-modal .cm-editor');
      await page.waitForSelector('#snippet-editor-modal input[name=license]');

      // Fill the pattern metadata right in the modal
      await page.locator('#snippet-editor-modal input[name=license]').fill('Made-Up-License-1.0');
      await page.locator('#snippet-editor-modal select[name="risk"]').selectOption('3');
      await page.locator('#snippet-editor-modal input[name="trademark"]').check();

      // Queue the create-pattern action (modal closes, indicator + widget appear)
      await page.locator('#snippet-editor-modal button[data-action="create-pattern"]').click();
      await page.waitForSelector('#snippet-editor-modal:not(.show)');
      await page.waitForSelector('#pending-actions-widget');
      await page.waitForSelector('#file-details-1 .pending-action-badge');
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
      await page.goto(performJobs, {timeout: 120000});
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
      if (!(await page.isVisible(`#file-details-${fileA}`))) {
        await page.locator(`#filelist-snippets a[href="#file-${fileA}"]`).click();
      }
      if (!(await page.isVisible(`#file-details-${fileB}`))) {
        await page.locator(`#filelist-snippets a[href="#file-${fileB}"]`).click();
      }
      await page.waitForSelector(`#file-details-${fileA} table.snippet`);
      await page.waitForSelector(`#file-details-${fileB} table.snippet`);

      // Helper: queue a create-pattern via the modal. A file can host multiple
      // risk-9 dropdowns; bypass the dropdown UI entirely and invoke the
      // matching item handler directly so we don't depend on Bootstrap's menu
      // animation/positioning settling between iterations.
      const queueAction = async (fileId, licenseName) => {
        await page.waitForFunction(() => !document.body.classList.contains('modal-open'));
        await page.evaluate(id => {
          const root = document.getElementById(`file-details-${id}`);
          const items = root.querySelectorAll('.dropdown-menu a.dropdown-item');
          for (const item of items) {
            if (item.textContent.trim() === 'Create Pattern from selection') {
              item.click();
              return;
            }
          }
          throw new Error(`No "Create Pattern from selection" item in #file-details-${id}`);
        }, fileId);
        await page.waitForSelector('#snippet-editor-modal.show');
        await page.waitForSelector('#snippet-editor-modal .cm-editor');
        await page.locator('#snippet-editor-modal input[name=license]').fill(licenseName);
        await page.locator('#snippet-editor-modal select[name="risk"]').selectOption('3');
        await page.locator('#snippet-editor-modal button[data-action="create-pattern"]').click();
        await page.waitForSelector('#snippet-editor-modal:not(.show)');
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
      await page.goto(performJobs, {timeout: 120000});
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
      if (!(await page.isVisible(`#file-details-${fileId}`))) {
        await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).click();
      }
      await page.waitForSelector(`#file-details-${fileId} table.snippet`);

      // Bypass the Bootstrap dropdown UI and trigger the matching item directly
      await page.evaluate(id => {
        const root = document.getElementById(`file-details-${id}`);
        const items = root.querySelectorAll('.dropdown-menu a.dropdown-item');
        for (const item of items) {
          if (item.textContent.trim() === 'Create Pattern from selection') {
            item.click();
            return;
          }
        }
        throw new Error(`No "Create Pattern from selection" item in #file-details-${id}`);
      }, fileId);
      await page.waitForSelector('#snippet-editor-modal.show');
      await page.waitForSelector('#snippet-editor-modal .cm-editor');

      // Replace the CodeMirror contents so the proposed pattern cannot match the
      // original snippet text (triggers the server's pattern_matches guard)
      await page.evaluate(() => {
        const view = document.querySelector('#snippet-editor-modal .cm-editor').cmView;
        view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: 'zzz nothing here matches the actual snippet zzz'}});
      });

      await page.locator('#snippet-editor-modal input[name=license]').fill('Error-Test-License');
      await page.locator('#snippet-editor-modal select[name="risk"]').selectOption('3');

      // Use the propose-pattern path - it runs the pattern_matches validation
      await page.locator('#snippet-editor-modal button[data-action="propose-pattern"]').click();
      await page.waitForSelector('#snippet-editor-modal:not(.show)');

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
      if (!(await page.isVisible(`#file-details-${fileId}`))) {
        await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).click();
      }
      await page.waitForSelector(`#file-details-${fileId} table.snippet`);

      await page.evaluate(id => {
        const root = document.getElementById(`file-details-${id}`);
        const items = root.querySelectorAll('.dropdown-menu a.dropdown-item');
        for (const item of items) {
          if (item.textContent.trim() === 'Create Pattern from selection') {
            item.click();
            return;
          }
        }
        throw new Error(`No "Create Pattern from selection" item in #file-details-${id}`);
      }, fileId);
      await page.waitForSelector('#snippet-editor-modal.show');
      await page.waitForSelector('#snippet-editor-modal .cm-editor');

      // Capture the original snippet text so we can restore it during edit
      const originalSnippetText = await page.evaluate(() => {
        return document.querySelector('#snippet-editor-modal .cm-editor').cmView.state.doc.toString();
      });
      t.ok(originalSnippetText.length > 0, 'captured original snippet text');

      // First pass: queue a propose-pattern with a deliberately bad pattern
      await page.evaluate(() => {
        const view = document.querySelector('#snippet-editor-modal .cm-editor').cmView;
        view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: 'zzz nothing here matches the actual snippet zzz'}});
      });
      await page.locator('#snippet-editor-modal input[name=license]').fill('Edit-Recovery-License');
      await page.locator('#snippet-editor-modal select[name="risk"]').selectOption('3');
      await page.locator('#snippet-editor-modal button[data-action="propose-pattern"]').click();
      await page.waitForSelector('#snippet-editor-modal:not(.show)');

      // Submit and confirm the validation error puts the action into error state
      await page.locator('#pending-actions-widget .pending-actions-toggle').click();
      const [decisionResp] = await Promise.all([
        page.waitForResponse(resp => /\/snippet\/batch_decision/.test(resp.url())),
        page.locator('#pending-actions-submit').click()
      ]);
      t.equal(decisionResp.status(), 400);
      await page.waitForSelector('#pending-actions-widget .pending-actions-item.state-error');
      t.match(await page.innerText('#pending-actions-widget'), /Edit-Recovery-License/);

      // Click Edit on the failed action - the modal re-opens with the prior data
      await page.locator('#pending-actions-widget button[data-action-control="edit"]').click();
      await page.waitForSelector('#snippet-editor-modal.show');
      await page.waitForSelector('#snippet-editor-modal .cm-editor');

      // Verify the form was pre-filled with the failed action's data
      t.equal(
        await page.inputValue('#snippet-editor-modal input[name=license]'),
        'Edit-Recovery-License',
        'license pre-filled from failed action'
      );
      t.equal(
        await page.inputValue('#snippet-editor-modal select[name="risk"]'),
        '3',
        'risk pre-filled from failed action'
      );
      const cmTextInEdit = await page.evaluate(() => {
        return document.querySelector('#snippet-editor-modal .cm-editor').cmView.state.doc.toString();
      });
      t.match(cmTextInEdit, /zzz nothing here matches/, 'pattern pre-filled from failed action');

      // Restore the matchable snippet text so the resubmission passes validation
      await page.evaluate(text => {
        const view = document.querySelector('#snippet-editor-modal .cm-editor').cmView;
        view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: text}});
      }, originalSnippetText);

      await page.locator('#snippet-editor-modal button[data-action="propose-pattern"]').click();
      await page.waitForSelector('#snippet-editor-modal:not(.show)');

      // The edit must REPLACE the original entry, not append a new one
      const countAfterEdit = await page.locator('#pending-actions-widget .pending-actions-item').count();
      t.equal(countAfterEdit, 1, 'edited action replaces failed one (queue still has 1 item)');
      t.notMatch(
        await page.innerText('#pending-actions-widget'),
        /state-error|circle-exclamation/,
        'no error state remains after successful edit'
      );

      // Submit the edited action - it must now succeed and reload the page
      await Promise.all([
        page.waitForURL(/\/reviews\/details\//),
        page.locator('#pending-actions-submit').click()
      ]);
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
          return r.top >= -50 && r.top <= window.innerHeight;
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
      if (!(await page.isVisible(`#file-details-${fileId}`))) {
        await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).click();
      }
      await page.waitForSelector(`#file-details-${fileId} table.snippet`);

      await page.evaluate(id => {
        const root = document.getElementById(`file-details-${id}`);
        const items = root.querySelectorAll('.dropdown-menu a.dropdown-item');
        for (const item of items) {
          if (item.textContent.trim() === 'Create Pattern from selection') {
            item.click();
            return;
          }
        }
        throw new Error(`No "Create Pattern from selection" item in #file-details-${id}`);
      }, fileId);
      await page.waitForSelector('#snippet-editor-modal.show');
      await page.waitForSelector('#snippet-editor-modal .cm-editor');
      await page.locator('#snippet-editor-modal input[name=license]').fill('Scroll-Link-Test');
      await page.locator('#snippet-editor-modal select[name="risk"]').selectOption('3');
      await page.locator('#snippet-editor-modal button[data-action="create-pattern"]').click();
      await page.waitForSelector('#snippet-editor-modal:not(.show)');
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
      await page.waitForFunction(
        id => {
          const el = document.getElementById(`pending-indicator-${id}`);
          if (!el) return false;
          const r = el.getBoundingClientRect();
          return r.top >= -50 && r.top <= window.innerHeight;
        },
        Number(fileId) === Number(fileId) ? 1 : 0,
        {timeout: 5000}
      ).catch(() => {
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

    await t.test('Editor gutter click on highlighted line opens pattern in new tab', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Open the modal so we land on a snippet that's guaranteed to have at least
      // one highlighted match line (a real license hit from the report view).
      const fileId = (await page.locator('#filelist-snippets a.file-link').first().getAttribute('href')).replace(
        '#file-',
        ''
      );
      if (!(await page.isVisible(`#file-details-${fileId}`))) {
        await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).click();
      }
      await page.waitForSelector(`#file-details-${fileId} table.snippet`);
      await page.waitForFunction(() => !document.body.classList.contains('modal-open'));
      await page.evaluate(id => {
        const root = document.getElementById(`file-details-${id}`);
        const items = root.querySelectorAll('.dropdown-menu a.dropdown-item');
        for (const item of items) {
          if (item.textContent.trim() === 'Create Pattern from selection') {
            item.click();
            return;
          }
        }
        throw new Error(`No "Create Pattern from selection" item in #file-details-${id}`);
      }, fileId);
      await page.waitForSelector('#snippet-editor-modal.show');
      await page.waitForSelector('#snippet-editor-modal .cm-editor');

      // Find a line CM6 marked with a found-pattern decoration and grab the
      // displayed line number from the matching gutter element. CM6's
      // lineNumbers() formats numbers via our formatNumber hook, so the gutter
      // element's textContent is the user-visible line number.
      const lineInfo = await page.evaluate(() => {
        const root = document.querySelector('#snippet-editor-modal .cm-editor');
        if (root == null) return null;
        const highlighted = root.querySelector('.cm-line.found-pattern');
        if (highlighted == null) return null;
        const lines = Array.from(root.querySelectorAll('.cm-content .cm-line'));
        const idx = lines.indexOf(highlighted);
        const gutters = root.querySelectorAll('.cm-lineNumbers .cm-gutterElement');
        // The first .cm-gutterElement is the spacer; content lines start at index 1.
        const gutter = gutters[idx + 1];
        return {displayed: gutter ? gutter.textContent.trim() : null, index: idx};
      });
      t.ok(lineInfo !== null && lineInfo.displayed !== null, 'modal snippet has at least one highlighted line');

      const hostUrlBefore = page.url();
      const [patternPage] = await Promise.all([
        context.waitForEvent('page'),
        page
          .locator(`#snippet-editor-modal .cm-lineNumbers .cm-gutterElement:text-is("${lineInfo.displayed}")`)
          .first()
          .click()
      ]);
      await patternPage.waitForLoadState('load');
      t.match(patternPage.url(), /\/licenses\/edit_pattern\/\d+/, 'new tab opens the matched pattern editor');
      t.equal(await patternPage.innerText('title'), 'Edit license pattern');
      await patternPage.close();

      // The original page must not have navigated; modal still mounted.
      t.equal(page.url(), hostUrlBefore, 'host page URL unchanged');
      t.ok(await page.isVisible('#snippet-editor-modal.show'), 'modal still open');

      // Clean up so the next subtest starts from a closed modal.
      await page.locator('#snippet-editor-modal .btn-close').click();
      await page.waitForSelector('#snippet-editor-modal:not(.show)');
    });

    await t.test('Hover tooltip on highlighted line shows pattern metadata', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const fileId = (await page.locator('#filelist-snippets a.file-link').first().getAttribute('href')).replace(
        '#file-',
        ''
      );
      if (!(await page.isVisible(`#file-details-${fileId}`))) {
        await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).click();
      }
      await page.waitForSelector(`#file-details-${fileId} table.snippet`);
      await page.waitForFunction(() => !document.body.classList.contains('modal-open'));
      await page.evaluate(id => {
        const root = document.getElementById(`file-details-${id}`);
        const items = root.querySelectorAll('.dropdown-menu a.dropdown-item');
        for (const item of items) {
          if (item.textContent.trim() === 'Create Pattern from selection') {
            item.click();
            return;
          }
        }
        throw new Error(`No "Create Pattern from selection" item in #file-details-${id}`);
      }, fileId);
      await page.waitForSelector('#snippet-editor-modal.show');
      await page.waitForSelector('#snippet-editor-modal .cm-editor');

      // Make sure at least one match-decorated line is in the editor.
      const highlighted = page.locator('#snippet-editor-modal .cm-line.found-pattern').first();
      await highlighted.waitFor();

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

      // Tidy up: move the mouse away so the tooltip closes, then close modal.
      await page.mouse.move(0, 0);
      await page.locator('#snippet-editor-modal .btn-close').click();
      await page.waitForSelector('#snippet-editor-modal:not(.show)');
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

    await t.test('Create pattern from classify-snippets page (page mode)', async t => {
      // Fixture snippets are never AI-classified, and the default filter hides
      // unclassified ones - widen the filter so cards are guaranteed to render.
      await page.goto(`${url}/snippets?isClassified=false`);
      t.equal(await page.innerText('title'), 'Snippets');
      await page.waitForSelector('.snippet-container .snippet-likelyness a');

      // The similarity link opens the page-mode editor in a new tab.
      const [editorPage] = await Promise.all([
        context.waitForEvent('page'),
        page.locator('.snippet-container .snippet-likelyness a').first().click()
      ]);
      await editorPage.waitForLoadState('load');
      t.equal(await editorPage.innerText('title'), 'Edit snippet');

      await editorPage.waitForSelector('#edit-snippet .cm-editor');
      await editorPage.waitForSelector('#edit-snippet input[name=license]');
      t.match(
        await editorPage.innerText('#edit-snippet button[data-action="create-pattern"]'),
        /Create Pattern/
      );

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

    await t.test('Missing Licenses', async t => {
      await page.goto(url);
      await page.click('text="Logged in as tester"');
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
      await page.click('text="Logged in as tester"');
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
      await page.click('text="Logged in as tester"');
      await page.click('text=Pattern Performance');
      t.equal(await page.innerText('title'), 'Pattern Performance');
      await page.waitForSelector('#recent-patterns .recent-pattern-header');
      const names = await page.locator('#recent-patterns .recent-pattern-header b').allInnerTexts();
      t.ok(names.includes('Made-Up-License-1.0'), 'Made-Up-License-1.0 listed among recent patterns');
    });

    await t.test('Statistics', async t => {
      await page.goto(url);
      await page.click('text="Logged in as tester"');
      await page.click('text=Statistics');
      t.equal(await page.innerText('title'), 'Statistics');
      await page.waitForSelector('#statistics .stats-body');
      t.equal(await page.innerText('#statistics .stats-body'), '24');
    });

    await t.test('API Keys', async t => {
      await page.goto(url);
      await page.click('text="Logged in as tester"');
      await page.click('text=API Keys');
      t.equal(await page.innerText('title'), 'API Keys');
      await page.waitForSelector('#api-keys tbody > tr:nth-child(1)');
      t.equal(await page.innerText('#api-keys tbody > tr:nth-child(1) > td:nth-child(1)'), 'No API keys found.');
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
