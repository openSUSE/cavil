#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// The license compatibility matrix is a first-class report widget: a grid of the licenses present in
// the package, each cell coloured with OSADL's verdict, and a docked explanation panel that opens when
// a flagged cell is clicked. The "compatibility" fixture builds a package pairing Apache-2.0 with
// GPL-2.0-only, which OSADL marks incompatible in both directions.
await t.test('Cavil UI - license compatibility matrix', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'compatibility';
  const ui = await launchUi('js_ui_compatibility');
  const {page, url, errorLogs} = ui;

  try {
    await page.goto(url);
    await page.click('text=Login');

    await page.goto(`${url}/reviews/details/1`);
    const matrix = page.locator('#license-compatibility');
    await matrix.waitFor();

    await t.test('renders as a card with both licenses on the axes', async t => {
      t.match(await matrix.locator('.license-matrix-header').innerText(), /License compatibility/, 'card title');

      const names = await matrix.locator('.license-matrix-rowhead-name').allInnerTexts();
      t.ok(names.includes('Apache-2.0'), 'Apache-2.0 is on the axis');
      t.ok(names.includes('GPL-2.0-only'), 'GPL-2.0-only is on the axis');

      t.ok((await matrix.locator('td.license-matrix-cell.cell-no').count()) > 0, 'grid has at least one "No" cell');
      t.equal(await matrix.locator('.license-matrix-legend-item').count(), 4, 'legend lists the four verdict kinds');
    });

    await t.test('clicking a flagged cell docks the verbatim OSADL explanation', async t => {
      t.equal(await matrix.locator('.license-matrix-detail').count(), 0, 'no explanation panel before selecting');

      await matrix.locator('td.license-matrix-cell.cell-no').first().click();
      const detail = matrix.locator('.license-matrix-detail');
      await detail.waitFor();

      const bar = await detail.locator('.license-matrix-detail-bar').innerText();
      t.match(bar, /Apache-2\.0/, 'title bar names Apache-2.0');
      t.match(bar, /GPL-2\.0-only/, 'title bar names GPL-2.0-only');
      t.match(bar, /Incompatible/, 'title bar shows the verdict');

      const body = await detail.locator('.license-matrix-detail-body').innerText();
      t.ok(body.length > 20, 'explanation text is present');
      t.notMatch(body, /&quot;/, 'explanation HTML entities are decoded');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
