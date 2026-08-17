#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Each license in the report's license list can carry a collapsed panel of external classification
// data, credited to the sources it came from. The toggle word says how complete that data is:
// "Obligations" when OSADL publishes an actual checklist (what a reviewer must do to ship the license,
// grouped by delivery use case), "Details" when all we have is SPDX's OSI / FSF classification. The
// "obligations" fixture builds a package covering both, plus expressions and a WITH-exception license.
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
      t.match(
        await apacheItem.locator('.license-obligations-toggle').innerText(),
        /Obligations/,
        'a license with an OSADL checklist advertises "Obligations"'
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
      t.ok(
        attrs.some(a => /OSI approved[\s\S]*Yes/i.test(a)),
        'the SPDX OSI flag is shown alongside the OSADL classifications'
      );
      t.ok(
        attrs.some(a => /FSF libre[\s\S]*Yes/i.test(a)),
        'the SPDX FSF flag is shown'
      );

      const source = await body.locator('.lob-source').innerText();
      t.match(source, /OSADL/, 'the panel is attributed to OSADL');
      t.match(source, /SPDX/, 'and to SPDX, since both contributed here');

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

    await t.test('an expression whose constituents have different coverage names each one', async t => {
      // "BSD-2-Clause AND Beerware": both are SPDX-known, but only BSD-2-Clause has an OSADL checklist.
      // Each constituent gets its own named section, so the obligations are unambiguously attributed to
      // BSD-2-Clause and Beerware is visibly the one with nothing more than flags.
      const partialItem = page.locator('.risk-license-item', {hasText: 'BSD-2-Clause AND Beerware'});
      await partialItem.locator('.license-obligations-toggle').click();
      const body = partialItem.locator('.license-obligations-body');
      await body.waitFor();

      const names = await body.locator('.lob-license-name').allInnerTexts();
      t.equal(names.length, 2, 'both constituents are named');
      t.match(names[0], /BSD-2-Clause/, 'the OSADL-known constituent comes first, in expression order');
      t.match(names[1], /Beerware/, 'the SPDX-only constituent is named too');

      const sections = body.locator('.lob-license');
      t.ok((await sections.nth(0).locator('.lob-must').count()) > 0, 'BSD-2-Clause shows its obligations');
      t.equal(await sections.nth(1).locator('.lob-must').count(), 0, 'Beerware has no obligations to show');
      t.match(
        await sections.nth(1).locator('.lob-none').innerText(),
        /No obligation checklist/i,
        'and says so rather than leaving the section blank'
      );
    });

    await t.test('a license with no OSADL checklist shows SPDX details instead', async t => {
      // CC-BY-4.0 has no OSADL checklist, so the toggle promises "Details" rather than "Obligations" -
      // the panel can only classify the license, not tell you what to do.
      const detailsItem = page.locator('.risk-license-item', {hasText: 'CC-BY-4.0'});
      const toggle = detailsItem.locator('.license-obligations-toggle');
      t.match(await toggle.innerText(), /Details/, 'the toggle says "Details", not "Obligations"');

      await toggle.click();
      const body = detailsItem.locator('.license-obligations-body');
      await body.waitFor();

      const attrs = await body.locator('.lob-attr').allInnerTexts();
      t.ok(
        attrs.some(a => /OSI approved[\s\S]*No/i.test(a)),
        'CC-BY-4.0 is shown as not OSI approved'
      );
      t.ok(
        attrs.some(a => /FSF libre[\s\S]*Yes/i.test(a)),
        'and as FSF libre'
      );
      t.equal(await body.locator('.lob-source').innerText(), 'SPDX', 'only SPDX is credited');
      t.equal(await body.locator('.lob-usecase').count(), 0, 'no use cases are invented');
    });

    await t.test('a license the FSF never ruled on shows no FSF row at all', async t => {
      // SPDX omits isFsfLibre for licenses the FSF has not ruled on. That is not a "not free" verdict, so
      // the row must be absent rather than rendered as a third state or flattened into "No".
      const noFsfItem = page.locator('.risk-license-item', {hasText: 'MPL-1.0'});
      await noFsfItem.locator('.license-obligations-toggle').click();
      const body = noFsfItem.locator('.license-obligations-body');
      await body.waitFor();

      const attrs = await body.locator('.lob-attr').allInnerTexts();
      t.ok(
        attrs.some(a => /OSI approved[\s\S]*Yes/i.test(a)),
        'MPL-1.0 is shown as OSI approved'
      );
      t.notOk(
        attrs.some(a => /FSF/i.test(a)),
        'but there is no FSF row, because there is no ruling'
      );
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

    await t.test('an SPDX identifier opens the license text overlay', async t => {
      const link = apacheItem.locator('.spdx-link', {hasText: 'Apache-2.0'}).first();
      t.equal(await link.getAttribute('data-spdx'), 'Apache-2.0', 'the identifier travels on the control');

      const modal = page.locator('.spdx-license-modal');
      await link.click();
      const text = modal.locator('[data-spdx-text]');
      await text.waitFor();
      // Bootstrap only hands the overlay focus once its show transition ends, and Escape is ignored
      // until then
      await page.waitForFunction(() => document.activeElement.classList.contains('modal-body'));
      t.match(page.url(), /\/reviews\/details\/1$/, 'the report page was not navigated away from');
      t.equal(await modal.locator('.spdx-license-id').innerText(), 'Apache-2.0', 'the overlay names the license');
      t.match(await text.innerText(), /Grant of Copyright License/, 'the license text is rendered');

      t.equal(
        await text.evaluate(el => getComputedStyle(el).whiteSpace),
        'pre-wrap',
        'authored blank lines and clause indents survive'
      );
      t.equal(
        await modal.locator('.spdx-license-source').getAttribute('target'),
        '_blank',
        'spdx.org is one click away'
      );

      await page.keyboard.press('Escape');
      await modal.waitFor({state: 'hidden'});
      t.ok(await apacheItem.isVisible(), 'and the reviewer is back where they were');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
