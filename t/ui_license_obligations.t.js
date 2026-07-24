#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Each license in the report's license list can carry an OSADL obligation checklist: a collapsed
// "Obligations" toggle that, when opened, shows what a reviewer must do to ship that license, grouped
// by delivery use case and attributed to OSADL. The "obligations" fixture builds a package with
// Apache-2.0 (a rich checklist) and a "MIT OR BSD-3-Clause" expression (two constituent licenses).
await t.test('Cavil UI - license obligations', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'obligations';
  const ui = await launchUi('js_ui_obligations');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await page.goto(`${url}/reviews/details/1`);
    const apacheItem = page.locator('.risk-license-item', {hasText: 'Apache-2.0'});
    await apacheItem.locator('.license-obligations-toggle').waitFor();

    await t.test('the obligation panel is collapsed by default', async t => {
      t.equal(
        await apacheItem.locator('.license-obligations-body').count(),
        0,
        'no obligation body is rendered until the toggle is opened'
      );
    });

    await t.test('opening Apache-2.0 shows use cases, obligations and attribution', async t => {
      await apacheItem.locator('.license-obligations-toggle').click();
      const body = apacheItem.locator('.license-obligations-body');
      await body.waitFor();

      const useCases = await body.locator('.lob-usecase-label').allInnerTexts();
      t.ok(
        useCases.some(l => /Source code delivery/i.test(l)),
        'a source-code delivery use case is shown'
      );
      t.ok(
        useCases.some(l => /Binary delivery/i.test(l)),
        'a binary delivery use case is shown'
      );

      const mustText = await body.locator('.lob-must').allInnerTexts();
      t.ok(
        mustText.some(m => /Provide License text/i.test(m)),
        'a YOU MUST obligation is listed'
      );

      // Apache-2.0 carries a "YOU MUST NOT" (service offerings on behalf of others).
      t.ok((await body.locator('.lob-mustnot').count()) > 0, 'a prohibition is rendered');

      const attrs = await body.locator('.lob-attr').allInnerTexts();
      t.ok(
        attrs.some(a => /Copyleft/i.test(a)),
        'the copyleft classification is shown'
      );
      t.ok(
        attrs.some(a => /Patent hints/i.test(a)),
        'the patent-hints classification is shown'
      );

      t.match(await body.locator('.lob-source').innerText(), /OSADL/, 'the panel is attributed to OSADL');

      // A single license needs no per-constituent heading.
      t.equal(await body.locator('.lob-license-name').count(), 0, 'single license has no constituent header');
    });

    await t.test('an expression shows one obligation section per constituent license', async t => {
      const exprItem = page.locator('.risk-license-item', {hasText: 'MIT OR BSD-3-Clause'});
      await exprItem.locator('.license-obligations-toggle').click();
      const body = exprItem.locator('.license-obligations-body');
      await body.waitFor();

      const names = await body.locator('.lob-license-name').allInnerTexts();
      t.ok(
        names.some(n => /\bMIT\b/.test(n)),
        'MIT has its own obligation section'
      );
      t.ok(
        names.some(n => /BSD-3-Clause/.test(n)),
        'BSD-3-Clause has its own obligation section'
      );
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
