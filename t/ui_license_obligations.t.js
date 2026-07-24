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

    await t.test('an expression with an OSADL-unknown constituent still names the known one', async t => {
      // "BSD-2-Clause AND Beerware": Beerware has no OSADL checklist, so only BSD-2-Clause resolves. The
      // panel must still name BSD-2-Clause rather than show unattributed obligations under the expression.
      const partialItem = page.locator('.risk-license-item', {hasText: 'BSD-2-Clause AND Beerware'});
      await partialItem.locator('.license-obligations-toggle').click();
      const body = partialItem.locator('.license-obligations-body');
      await body.waitFor();

      const names = await body.locator('.lob-license-name').allInnerTexts();
      t.equal(names.length, 1, 'exactly one constituent is named');
      t.match(names[0], /BSD-2-Clause/, 'the OSADL-known constituent (BSD-2-Clause) is named');
      t.ok((await body.locator('.lob-must').count()) > 0, 'its obligations are shown');
    });

    await t.test('a WITH-exception license shows base obligations with an exception caveat', async t => {
      // "GPL-2.0-or-later WITH Classpath-exception-2.0": OSADL has no exception-aware checklist, so the
      // base license's obligations are shown and the panel caveats that the exception may modify them.
      const excItem = page.locator('.risk-license-item', {hasText: 'Classpath-exception-2.0'});
      await excItem.locator('.license-obligations-toggle').click();
      const body = excItem.locator('.license-obligations-body');
      await body.waitFor();

      const caveat = await body.locator('.lob-caveat').innerText();
      t.match(caveat, /Classpath-exception-2\.0/, 'the caveat names the exception');
      t.match(caveat, /modif/iu, 'the caveat warns the obligations may be modified');
      const names = await body.locator('.lob-license-name').allInnerTexts();
      t.ok(
        names.some(n => /GPL-2\.0-or-later/.test(n)),
        'the base license GPL-2.0-or-later is named'
      );
      t.ok((await body.locator('.lob-must').count()) > 0, 'the base license obligations are shown');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
