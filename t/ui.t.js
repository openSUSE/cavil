#!/usr/bin/env node
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

  const errorLogs = [];
  page.on('console', message => {
    if (message.type() === 'error') {
      errorLogs.push(message.text());
    }
  });

  await t.test('Navigation', async t => {
    await page.goto(url);
    t.equal(await page.innerText('title'), 'List open reviews');
  });

  t.same(errorLogs, []);

  await context.close();
  await browser.close();
  await server.close();
});
