#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Code search: paste a snippet, get the reviewed open source content it resembles, ranked by
// containment with a risk badge and an inline excerpt of the matched region. The fixture indexes
// itself (codesearch config on, so the normal unpack/analyze pipeline fingerprints its files), and
// the snippet below is a verbatim function from the perl-Mojolicious fixture, so it must match.
const SNIPPET = `sub element_count_is {
  my ($self, $selector, $count, $desc) = @_;
  $desc = _desc($desc, qq{element count for selector "$selector"});
  my $size = $self->tx->res->dom->find($selector)->size;
  return $self->_test('is', $size, $count, $desc);
}`;

t.test('Cavil UI - code search', skipUnlessOnline, async t => {
  process.env.JS_UI_FIXTURES = 'codesearch';
  const ui = await launchUi('js_ui_code_search');
  const {page, url, errorLogs} = ui;

  try {
    // Dummy auth picks up the admin "tester"; the page lives behind login.
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Paste a snippet and find its source', async t => {
      await page.goto(`${url}/code-search`);
      t.equal(await page.innerText('title'), 'Code Search');

      t.equal(await page.locator('.code-search-query').count(), 1, 'query workspace is framed as a dedicated tool');
      t.equal(await page.locator('label[for="code-search-snippet"]').innerText(), 'Code snippet');

      // The paste box reuses the CodeMirror editor (no line-number gutter, unlike the pattern editor).
      await page.waitForSelector('.code-search .pattern-codemirror-host .cm-content');
      t.equal(await page.locator('.code-search .cm-gutters').count(), 0, 'no line-number gutter on the paste box');

      await page.locator('.code-search .cm-content').click();
      await page.keyboard.insertText(SNIPPET);
      await page.click('button[type=submit]');

      // A ranked result card resolves back to the perl-Mojolicious source that carries the function.
      await page.waitForSelector('.code-search-result');
      t.match(await page.innerText('.cavil-list-title'), /match/, 'a match count is shown');
      t.match(await page.innerText('.code-search-result'), /perl-Mojolicious/, 'resolves to the source package');
      t.match(await page.innerText('.code-search-result'), /Test\/Mojo\.pm/, 'names the file');
      t.equal(await page.locator('.code-search-result-path').getAttribute('target'), '_blank', 'source opens in a new tab');
      t.match(await page.innerText('.code-search-result'), /of snippet/, 'shows containment');
      t.match(await page.innerText('.code-search-coverage'), /<1%\s+of file/, 'does not round a small overlap to zero');
      t.match(await page.innerText('.code-search-result-risk'), /risk/i, 'labels the match risk explicitly');

      // The matched region is highlighted inline, so the reviewer sees the code without a round trip.
      await page.waitForSelector('.code-search-result .source tr.cavil-cs-match');
      t.match(
        await page.innerText('.code-search-result .source tr.cavil-cs-match'),
        /element_count_is|find\(\$selector\)/,
        'the matched line is the pasted code'
      );

      const otherLocations = page.locator('details.code-search-result-locations');
      t.equal(await otherLocations.count(), 1, 'secondary locations use a disclosure');
      t.notOk(await otherLocations.locator('a').first().isVisible(), 'secondary file links start collapsed');
      await otherLocations.locator('summary').click();
      const secondaryFile = otherLocations.locator('a').first();
      t.ok(await secondaryFile.isVisible(), 'secondary file links are available on demand');
      t.equal(await secondaryFile.getAttribute('target'), '_blank', 'secondary source opens in a new tab');
      t.equal(
        await secondaryFile.evaluate(element => getComputedStyle(element).textDecorationLine),
        'none',
        'secondary links do not add persistent underline noise'
      );

      const resultBottom = await page
        .locator('.code-search-results-panel')
        .evaluate(element => element.getBoundingClientRect().bottom);
      const footerTop = await page.locator('.cavil-footer').evaluate(element => element.getBoundingClientRect().top);
      t.ok(footerTop - resultBottom >= 48, 'the result panel leaves breathing room above the page footer');
    });

    await t.test('Unrelated code finds nothing', async t => {
      await page.goto(`${url}/code-search`);
      await page.locator('.code-search .cm-content').click();
      await page.keyboard.insertText(
        [...Array(40).keys()].map(i => `zzqx_${i} wibble_${i} frobnicate_${i}`).join('\n')
      );
      await page.click('button[type=submit]');
      await page.waitForSelector('.code-search-empty:has-text("No matching open source code found")');
      t.equal(await page.locator('.code-search-result').count(), 0, 'no false-positive results');
      t.match(
        await page.innerText('.code-search-empty'),
        /submitted fragment did not overlap.*at least 20 words, identifiers, or numbers/is,
        'explains both no overlap and the configured minimum searchable length'
      );
    });

    await t.test('File browser shows cross-package provenance', async t => {
      // perl-Mojolicious is indexed twice from the same sources, so its files are byte-identical across
      // both packages and the browser surfaces that as content provenance.
      await page.goto(`${url}/reviews/file_view/1/Mojolicious-7.25/lib/Test/Mojo.pm`);
      await page.waitForSelector('.file-browser-provenance', {timeout: 8000});
      t.match(await page.innerText('.file-browser-provenance'), /Identical to code in/, 'provenance strip is shown');
      t.match(await page.innerText('.file-browser-provenance a'), /perl-Mojolicious/, 'links the other carrier');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    delete process.env.JS_UI_FIXTURES;
    await ui.teardown();
  }
});
