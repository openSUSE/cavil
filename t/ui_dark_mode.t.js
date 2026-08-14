#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, openAccountMenu, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

const themeOf = page => page.getAttribute('html', 'data-bs-theme');
const bodyBackground = page => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
const toggle = page => page.locator('.cavil-theme-toggle');
const knobOffset = page =>
  page.evaluate(() => {
    const track = document.querySelector('.cavil-theme-toggle').getBoundingClientRect();
    const knob = document.querySelector('.cavil-theme-toggle-knob').getBoundingClientRect();
    return Math.round(knob.left - track.left);
  });

t.test('Cavil UI - dark mode', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_dark_mode');
  const {page, url, errorLogs} = ui;

  try {
    await t.test('Light is the default, with no cookie', async t => {
      await page.goto(`${url}/login_as_contributor`);
      await page.goto(url);
      t.equal(await themeOf(page), 'light', 'the server renders the light attribute');
      t.equal(await bodyBackground(page), 'rgb(255, 255, 255)', 'the page is white');
      t.notOk(
        (await page.context().cookies()).some(c => c.name === 'cavil_theme'),
        'no theme cookie until the user asks for one'
      );
    });

    await t.test('The account menu carries a switch on the Roles row', async t => {
      await openAccountMenu(page);
      await page.waitForSelector('.cavil-theme-toggle');
      t.equal(await page.innerText('.cavil-theme-row .dropdown-header'), 'Roles', 'sits on the Roles header row');
      t.equal(await toggle(page).getAttribute('role'), 'switch', 'is a switch, not a plain button');
      t.equal(await toggle(page).getAttribute('aria-checked'), 'false', 'reading as off while light');
      t.equal(await toggle(page).getAttribute('title'), 'Switch to dark mode', 'and says where it goes');
      t.ok(await page.isVisible('.cavil-theme-toggle .fa-moon'), 'the far side shows the mode on offer');
    });

    await t.test('Clicking it slides the knob and switches the page to dark', async t => {
      const before = await knobOffset(page);
      await toggle(page).click();
      t.equal(await themeOf(page), 'dark', 'the attribute flips');
      t.equal(await bodyBackground(page), 'rgb(13, 17, 23)', 'the page repaints dark');

      await page.waitForFunction(() => {
        const track = document.querySelector('.cavil-theme-toggle').getBoundingClientRect();
        const knob = document.querySelector('.cavil-theme-toggle-knob').getBoundingClientRect();
        return knob.right > track.left + track.width / 2;
      });
      t.ok((await knobOffset(page)) > before, 'the knob travels to the right-hand position');

      t.equal(await toggle(page).getAttribute('aria-checked'), 'true', 'and now reads as on');
      t.equal(await toggle(page).getAttribute('title'), 'Switch to light mode', 'with the return trip offered');
      t.ok(await page.isVisible('.cavil-user-dropdown.show'), 'the menu stays open, so it can be flipped back');
    });

    await t.test('Cavil and Bootstrap chrome agree on the dark palette', async t => {
      const [navbar, body] = await page.evaluate(() => [
        getComputedStyle(document.querySelector('nav.navbar')).backgroundColor,
        getComputedStyle(document.body).backgroundColor
      ]);
      t.equal(navbar, 'rgb(1, 4, 9)', 'the navbar is the inset canvas, not Bootstrap grey');
      t.not(navbar, body, 'and it frames the content by receding, never by sitting lighter than it');

      // Bootstrap transitions .nav-link colour over 150ms, so this is the settled value.
      await page.waitForFunction(
        () => getComputedStyle(document.querySelector('.navbar-nav .nav-link.active')).color === 'rgb(240, 246, 252)'
      );
      t.pass('the active nav link reaches the dark emphasis colour');
    });

    await t.test('The choice survives a reload, via the cookie', async t => {
      const cookie = (await page.context().cookies()).find(c => c.name === 'cavil_theme');
      t.equal(cookie.value, 'dark', 'the cookie records the choice');
      t.equal(cookie.path, '/', 'for the whole site');

      await page.goto(url);
      t.equal(await themeOf(page), 'dark', 'the server renders dark on the next request');
      t.equal(await bodyBackground(page), 'rgb(13, 17, 23)', 'with no flash of light');
    });

    await t.test('And switching back restores light exactly', async t => {
      await openAccountMenu(page);
      await toggle(page).click();
      t.equal(await themeOf(page), 'light', 'back to light');
      t.equal(await bodyBackground(page), 'rgb(255, 255, 255)', 'white again');
      t.equal(await toggle(page).getAttribute('aria-checked'), 'false', 'the switch returns to off');

      await page.goto(url);
      t.equal(await themeOf(page), 'light', 'and it sticks across a reload');
      t.equal(
        (await page.context().cookies()).find(c => c.name === 'cavil_theme').value,
        'light',
        'the cookie was rewritten rather than dropped'
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
