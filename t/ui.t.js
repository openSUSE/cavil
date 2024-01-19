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
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(5)'), /Error/);
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
      t.match(await page.innerText('#open-reviews tbody > tr:nth-child(3) > td:nth-child(5)'), /Error/);
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
      t.equal(await page.innerText('title'), 'Results: perl-Mojolicious');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /GPL/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(5)'), /Artistic/);
    });

    await t.test('Reports', async t => {
      await page.goto(url);
      await page.click('text=Error');
      t.equal(await page.innerText('title'), 'Report for harbor-helm');
      await page.click('text=Open Reviews');
      t.equal(await page.innerText('title'), 'List open reviews');

      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
    });
  });

  await t.test('Admin', async t => {
    await t.test('Login', async t => {
      await page.goto(url);
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Login');
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Log out tester');
      t.equal(await page.innerText('title'), 'List open reviews');
      await page.click('text=Login');
      t.equal(await page.innerText('title'), 'List open reviews');
    });

    await t.test('Minion dashboard', async t => {
      await page.goto(url);
      await page.click('text=Minion');
      t.match(await page.innerText('title'), /Minion/);
      await page.click('text=Back to Site');
      t.equal(await page.innerText('title'), 'List open reviews');
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
      t.equal(await page.innerText('title'), 'Results: perl-Mojolicious');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(1) > td:nth-child(5)'), /GPL/);
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(1)'), /ago/);
      t.equal(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(2)'), 'new');
      t.match(await page.innerText('#review-search tbody > tr:nth-child(2) > td:nth-child(5)'), /Artistic/);
    });

    await t.test('Expand hidden file (and open it in a new tab)', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      t.same(await page.isVisible('#file-details-6'), false);
      await page.locator('a[href="#file-6"]').click();
      t.match(await page.innerText('#expand-link-6'), /Mojolicious.+js/);
      t.same(await page.isVisible('#file-details-6'), true);

      // Open whole file in new tab
      const [page2] = await Promise.all([
        context.waitForEvent('page'),
        page.locator('a[href="#file-details-6"] ~ div a[target="_blank"]').click()
      ]);
      await page2.waitForLoadState();
      t.match(await page2.innerText('title'), /Content of Mojolicious.+js/);
      t.match(await page2.innerText('textarea'), /Apache.+indexOf/s);
      await page2.close();
    });

    await t.test('Create pattern from report match', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      // Use menu to select a pattern
      await page.locator('#dropdownMenuLink-1-4 i').click();
      await page.locator('#dropdownMenuLink-1-4 ~ div :has-text("Extend one line above")').click();
      await page.locator('#dropdownMenuLink-1-4 i').click();
      await page.locator('#dropdownMenuLink-1-4 ~ div :has-text("Extend one line below")').click();
      await page.locator('#dropdownMenuLink-1-4 i').click();
      await page.locator('#dropdownMenuLink-1-4 ~ div :has-text("Create Pattern from selection")').click();
      await page.waitForURL(`${url}/snippet/edit/7`);

      // Select a few options on the creation form
      await page.locator('select[name="risk"]').selectOption('3');
      await page.locator('input[name="opinion"]').check();
      await page.locator('button:has-text("Create Pattern")').click();
      await page.waitForURL(`${url}/snippet/decision/7`);

      // Update pattern with a made up license
      t.match(await page.innerText('#content'), /Created/);
      await page.click('text=pattern');
      await page.locator('input[name=license]').click();
      await page.locator('input[name=license]').fill('Made-Up-License-1.0');
      await page.locator('input[value=Update]').click();
      t.equal(await page.innerText('select[name=risk] > option[selected]'), '3');
      t.same(await page.isVisible('input[name=opinion][checked]'), true);
      t.match(await page.innerText('div.alert'), /Pattern has been updated/);

      // License now shows up in list
      await page.click('text=Licenses');
      t.equal(await page.innerText('title'), 'List licenses');
      await page.click('text=Made-Up-License-1.0');
      t.equal(await page.innerText('title'), 'License details of Made-Up-License-1.0');

      // Wait for reindexing
      await page.goto(performJobs, {timeout: 120000});
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      t.match(await page.innerText('ul#risk-3 li'), /Made-Up-License-1.0/);
    });

    await t.test('Accept request', async t => {
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      await page.click('text=Good Enough');
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
      await page.click('text=Checked');
      t.equal(await page.innerText('div.alert b'), 'correct');

      await page.click('text=Recently Reviewed');
      t.equal(await page.innerText('title'), 'List recent reviews');
      await page.waitForSelector('#recent-reviews tbody > tr:nth-child(1)');
      t.equal(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(5)'), 'perl-Mojolicious');
      t.equal(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(6)'), 'correct');
      t.match(await page.innerText('#recent-reviews tbody > tr:nth-child(1) > td:nth-child(9)'), /Artistic/);
    });

    await t.test('Manual reindexing', async t => {
      await page.goto(url);
      await page.click('text=Recently Reviewed');
      t.equal(await page.innerText('title'), 'List recent reviews');
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');

      const page2 = await context.newPage();
      await page.click('text=Reindex');
      await page2.goto(performJobs, {timeout: 120000});
      t.match(await page2.innerText('div'), /done/);
      await page2.close();

      await page.waitForSelector('#license-chart');
      t.match(await page.innerText('ul#risk-3 li'), /Made-Up-License-1.0/);
    });
  });

  t.test('Console errors', t => {
    t.same(errorLogs, []);
    t.end();
  });

  await context.close();
  await browser.close();
  await server.close();
});
