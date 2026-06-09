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
      await page.waitForSelector('#inline-snippet-editor input[name=license]');
      await page.locator('#inline-snippet-editor input[name=license]').click();
      await page.keyboard.type('np');
      t.equal(
        await page.locator('#inline-snippet-editor input[name=license]').inputValue(),
        'np',
        'shortcut keys are typed normally inside the license input'
      );
      await page.locator('#inline-snippet-editor [data-action="cancel"]').click();
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
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

    await t.test('Hidden inline previews indicator (max_expanded_files)', async t => {
      // mojo#1 has only a handful of unresolved matches, well under the
      // max_expanded_files cap — the indicator must stay out of the DOM and
      // the backend must report 0 hidden previews alongside the cap value.
      // (The "indicator renders with a non-zero count" path is covered by
      // the Perl JSON test in t/manual_review.t — exercising it from the
      // browser would require synthetic missed_files whose source fetches
      // would 404 and trip the global Console errors check.)
      await page.goto(url);
      await page.click('text=Artistic');
      t.equal(await page.innerText('title'), 'Report for perl-Mojolicious');
      await page.waitForSelector('#license-chart');
      t.equal(
        await page.locator('#hidden-previews-notice').count(),
        0,
        'no indicator when missed-file count is under the cap'
      );

      const details = await page.evaluate(async () => {
        const res = await fetch('/reviews/report_details/1');
        return res.json();
      });
      t.equal(details.max_expanded_files, 100, 'max_expanded_files in JSON response');
      t.equal(details.hidden_inline_previews, 0, 'no hidden previews when under the cap');
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
      await page.waitForSelector('#inline-snippet-editor');
      await page.waitForSelector('#inline-snippet-editor .cm-editor');
      await page.waitForSelector('#inline-snippet-editor input[name=license]');
      // Inline editor hides the source-file/package origin line (only the page version shows it).
      t.notMatch(await page.innerText('#inline-snippet-editor'), /The example shown here is from the file/);

      // Fill the pattern metadata right in the inline editor
      await page.locator('#inline-snippet-editor input[name=license]').fill('Made-Up-License-1.0');
      await page.locator('#inline-snippet-editor select[name="risk"]').selectOption('3');
      await page.locator('#inline-snippet-editor input[name="trademark"]').check();

      // Queue the create-pattern action (editor closes, indicator + widget appear)
      await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').click();
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
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

      // Helper: queue a create-pattern via the inline editor. A file can host multiple
      // risk-9 dropdowns; bypass the dropdown UI entirely and invoke the
      // matching item handler directly so we don't depend on Bootstrap's menu
      // animation/positioning settling between iterations.
      const queueAction = async (fileId, licenseName) => {
        await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
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
        await page.waitForSelector('#inline-snippet-editor');
        await page.waitForSelector('#inline-snippet-editor .cm-editor');
        await page.locator('#inline-snippet-editor input[name=license]').fill(licenseName);
        await page.locator('#inline-snippet-editor select[name="risk"]').selectOption('3');
        await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').click();
        await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
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
      await page.waitForSelector('#inline-snippet-editor');
      await page.waitForSelector('#inline-snippet-editor .cm-editor');

      // Replace the CodeMirror contents so the proposed pattern cannot match the
      // original snippet text (triggers the server's pattern_matches guard)
      await page.evaluate(() => {
        const view = document.querySelector('#inline-snippet-editor .cm-editor').cmView;
        view.dispatch({
          changes: {from: 0, to: view.state.doc.length, insert: 'zzz nothing here matches the actual snippet zzz'}
        });
      });

      await page.locator('#inline-snippet-editor input[name=license]').fill('Error-Test-License');
      await page.locator('#inline-snippet-editor select[name="risk"]').selectOption('3');

      // Use the propose-pattern path - it runs the pattern_matches validation.
      // For admin+contributor users, propose-pattern lives in the shared
      // More actions dropdown.
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-pattern"]').click();
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});

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
      await page.waitForSelector('#inline-snippet-editor');
      await page.waitForSelector('#inline-snippet-editor .cm-editor');

      // Capture the original snippet text so we can restore it during edit
      const originalSnippetText = await page.evaluate(() => {
        return document.querySelector('#inline-snippet-editor .cm-editor').cmView.state.doc.toString();
      });
      t.ok(originalSnippetText.length > 0, 'captured original snippet text');

      // First pass: queue a propose-pattern with a deliberately bad pattern
      await page.evaluate(() => {
        const view = document.querySelector('#inline-snippet-editor .cm-editor').cmView;
        view.dispatch({
          changes: {from: 0, to: view.state.doc.length, insert: 'zzz nothing here matches the actual snippet zzz'}
        });
      });
      await page.locator('#inline-snippet-editor input[name=license]').fill('Edit-Recovery-License');
      await page.locator('#inline-snippet-editor select[name="risk"]').selectOption('3');
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-pattern"]').click();
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});

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
      await page.waitForSelector('#inline-snippet-editor');
      await page.waitForSelector('#inline-snippet-editor .cm-editor');

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
      const cmTextInEdit = await page.evaluate(() => {
        return document.querySelector('#inline-snippet-editor .cm-editor').cmView.state.doc.toString();
      });
      t.match(cmTextInEdit, /zzz nothing here matches/, 'pattern pre-filled from failed action');

      // Restore the matchable snippet text so the resubmission passes validation
      await page.evaluate(text => {
        const view = document.querySelector('#inline-snippet-editor .cm-editor').cmView;
        view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: text}});
      }, originalSnippetText);

      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-pattern"]').click();
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});

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
      await page.waitForSelector('#inline-snippet-editor');
      await page.waitForSelector('#inline-snippet-editor .cm-editor');
      await page.locator('#inline-snippet-editor input[name=license]').fill('Scroll-Link-Test');
      await page.locator('#inline-snippet-editor select[name="risk"]').selectOption('3');
      await page.locator('#inline-snippet-editor button[data-action="create-pattern"]').click();
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
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
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
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
      await page.waitForSelector('#inline-snippet-editor');
      await page.waitForSelector('#inline-snippet-editor .cm-editor');

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

      // Tidy up: move the mouse away so the tooltip closes, then close the editor.
      await page.mouse.move(0, 0);
      await page.locator('#inline-snippet-editor button[data-action="cancel"]').click();
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
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
      if (!(await page.isVisible(`#file-details-${fileId}`))) {
        await page.locator(`#filelist-snippets a[href="#file-${fileId}"]`).click();
      }
      await page.waitForSelector(`#file-details-${fileId} table.snippet`);

      // Bypass Bootstrap's dropdown UI and trigger the menu item directly
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
      await page.waitForSelector('#inline-snippet-editor');
      await page.waitForSelector('#inline-snippet-editor .cm-editor');
      await page.waitForSelector('#inline-snippet-editor input[name=license]');

      // Missing License lives in the shared More actions dropdown
      await page.locator('#inline-snippet-editor button[aria-label="More actions"]').click();
      await page.locator('#inline-snippet-editor .dropdown-menu a[data-action="propose-missing"]').click();
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});

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
      await page.click('text="Logged in as tester"');
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

    await t.test('Edit pattern page (Vue) - delete redirects to /licenses', async t => {
      // Use the throwaway pattern created in the classify-snippets subtest
      // above so we can exercise the destructive DELETE path without breaking
      // later assertions (Pattern Performance only checks Made-Up-License-1.0).
      await page.goto(`${url}/licenses/Page-Editor-License-1.0`);
      t.equal(await page.innerText('title'), 'License details of Page-Editor-License-1.0');
      const editHref = await page.locator('a[href*="/licenses/edit_pattern/"]').first().getAttribute('href');
      t.ok(editHref, 'license details page links to pattern editor');

      await page.goto(`${url}${editHref}`);
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

  await t.test('Contributor', async t => {
    await t.test('Snippet editor action layout', async t => {
      // Switch to a contributor-only user via the wrapper helper. The dummy
      // login always picks up the admin "tester"; this route logs in as a
      // user that only has the 'contributor' role.
      await page.goto(`${url}/login_as_contributor`);
      await page.waitForSelector('text="Logged in as contrib_tester"');

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
      await page.waitForSelector('#inline-snippet-editor');
      await page.waitForSelector('#inline-snippet-editor .cm-editor');
      await page.waitForSelector('#inline-snippet-editor input[name=license]');

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
      await page.waitForSelector('#inline-snippet-editor', {state: 'detached'});
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
