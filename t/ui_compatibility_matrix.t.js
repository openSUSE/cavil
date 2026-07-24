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
      t.equal(await matrix.locator('.license-matrix-legend-item').count(), 5, 'legend lists the verdict kinds');

      // Apache-2.0 and GPL-2.0-only are "No" in both directions, so their cells get the mutual tile.
      t.ok(
        (await matrix.locator('td.license-matrix-cell.cell-no.is-mutual').count()) > 0,
        'both-direction conflicts are marked as mutual (filled tile)'
      );
    });

    await t.test('hovering a flagged cell shows an in-place license mapping tooltip', async t => {
      const flaggedCell = matrix.locator('td.license-matrix-cell.cell-no').first();
      await flaggedCell.hover();

      const tooltip = matrix.locator('.license-matrix-tooltip');
      await tooltip.waitFor();
      const tipText = await tooltip.innerText();
      t.match(tipText, /Incompatible/, 'tooltip shows the verdict');
      t.match(tipText, /Using/, 'tooltip explains the inbound license role');
      t.match(tipText, /Under/, 'tooltip explains the outbound license role');
      t.match(tipText, /Apache-2\.0/, 'tooltip names Apache-2.0');
      t.match(tipText, /GPL-2\.0-only/, 'tooltip names GPL-2.0-only');

      const cellBox = await flaggedCell.boundingBox();
      const tipBox = await tooltip.boundingBox();
      t.ok(tipBox.y < cellBox.y, 'tooltip appears above the hovered matrix cell');
    });

    await t.test('clicking a flagged cell docks the verbatim OSADL explanation', async t => {
      t.equal(await matrix.locator('.license-matrix-detail').count(), 0, 'no explanation panel before selecting');

      const flaggedCell = matrix.locator('td.license-matrix-cell.cell-no').first();
      await flaggedCell.click();
      const detail = matrix.locator('.license-matrix-detail');
      await detail.waitFor();

      t.equal(await matrix.locator('.license-matrix-rowhead.is-selected.axis-no').count(), 1, 'selected row label is emphasized');
      t.equal(await matrix.locator('.license-matrix-colhead.is-selected.axis-no').count(), 1, 'selected column number is emphasized');

      const bar = await detail.locator('.license-matrix-detail-bar').innerText();
      t.match(bar, /Apache-2\.0/, 'title bar names Apache-2.0');
      t.match(bar, /GPL-2\.0-only/, 'title bar names GPL-2.0-only');
      t.match(bar, /Incompatible/, 'title bar shows the verdict');

      const body = await detail.locator('.license-matrix-detail-body').innerText();
      t.ok(body.length > 20, 'explanation text is present');
      t.notMatch(body, /&quot;/, 'explanation HTML entities are decoded');

      await flaggedCell.click();
      t.equal(await matrix.locator('.license-matrix-detail').count(), 0, 'clicking the selected cell again closes it');
    });

    assertNoUnexpectedConsoleErrors(t, errorLogs);
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
