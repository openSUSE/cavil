#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

// Code search: paste a snippet, get the reviewed open source content it resembles, ranked by
// containment with a risk badge and an inline excerpt of the matched region. The fixture indexes
// itself (codesearch config on, so the normal unpack/analyze pipeline fingerprints its files). The block
// below is verbatim from the perl-Mojolicious fixture and long enough to winnow to enough fingerprints to
// be searchable (a shorter paste is legitimately reported as too short - see the dedicated subtest).
const SNIPPET = `sub element_count_is {
  my ($self, $selector, $count, $desc) = @_;
  my $size = $self->tx->res->dom->find($selector)->size;
  return $self->_test('is', $size, $count,
    _desc($desc, qq{element count for selector "$selector"}));
}

sub element_exists {
  my ($self, $selector, $desc) = @_;
  $desc = _desc($desc, qq{element for selector "$selector" exists});
  return $self->_test('ok', $self->tx->res->dom->at($selector), $desc);
}

sub element_exists_not {
  my ($self, $selector, $desc) = @_;
  $desc = _desc($desc, qq{no element for selector "$selector"});
  return $self->_test('ok', !$self->tx->res->dom->at($selector), $desc);
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
      t.match(await page.innerText('.code-search-coverage'), /File coverage\s+\d+%/, 'labels file coverage explicitly');

      // Match evidence: a verbatim block aligns fully, so every marker in the compact map is aligned.
      const first = page.locator('.code-search-result').first();
      t.equal(
        await first.locator('.code-search-result-measurements > .code-search-match-evidence').count(),
        1,
        'keeps fingerprint evidence in the measurement row'
      );
      t.same(
        await first.locator('.code-search-result-header').evaluate(element =>
          [...element.children].map(child => child.className)
        ),
        ['code-search-result-identity', 'code-search-result-tags', 'code-search-result-measurements'],
        'orders identity, categorical badges, then measurements'
      );
      const evidence = first.locator('.code-search-match-evidence');
      await evidence.locator('.code-search-match-map').waitFor();
      t.equal(
        await first.locator('.code-search-match-kind').innerText(),
        'Fully aligned',
        'labels full alignment clearly'
      );
      t.match(await evidence.locator('.code-search-match-count').innerText(), /\d+ of \d+ fingerprints aligned/, 'shows the fingerprint alignment count');
      t.equal(await evidence.locator('.code-search-match-cell').count(), 10, 'the match meter stays at ten blocks');
      t.same(
        await evidence.locator('.code-search-match-cell').first().evaluate(element => {
          const box = element.getBoundingClientRect();
          return {width: box.width, height: box.height, gap: getComputedStyle(element.parentElement).gap};
        }),
        {width: 8, height: 8, gap: '2px'},
        'uses the report coverage-square geometry'
      );
      t.equal(await evidence.locator('.code-search-match-cell:not(.is-on)').count(), 0, 'a verbatim block aligns every marker');

      // The matched region is highlighted inline, so the reviewer sees the code without a round trip.
      await page.waitForSelector('.code-search-result .source tr.cavil-cs-match');
      t.match(
        await page.innerText('.code-search-result .source tr.cavil-cs-match'),
        /element_|selector|_test/,
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

    await t.test('A partly-aligned snippet is flagged partial', async t => {
      // The same block, prefixed with lines absent from the source: the copied part aligns, the added lines
      // do not, so the match is only partially aligned with dark cells.
      const noise = [...Array(12).keys()].map(i => `zzqx_${i} wibble_${i} frobnicate_${i} grumble_${i}`).join('\n');
      await page.goto(`${url}/code-search`);
      await page.locator('.code-search .cm-content').click();
      await page.keyboard.insertText(`${noise}\n${SNIPPET}`);
      await page.click('button[type=submit]');
      await page.waitForSelector('.code-search-result');
      const first = page.locator('.code-search-result').first();
      t.equal(await first.locator('.code-search-match-kind').innerText(), 'Partially aligned', 'flagged partial');
      t.ok((await first.locator('.code-search-match-cell:not(.is-on)').count()) > 0, 'the match map shows differences');
    });

    await t.test('A large fingerprint set stays compact', async t => {
      const queryUrl = '**/code-search/query';
      await page.route(queryUrl, route =>
        route.fulfill({
          contentType: 'application/json',
          body: JSON.stringify({
            total: 1,
            matches: [
              {
                hash: 'large-match',
                containment_of: 0.12,
                aligned: 198,
                total: 220,
                exact: false,
                marks: [],
                licenses: [],
                risk: null,
                files: [{package: 1, name: 'large-package', filename: 'src/large.c'}],
                excerpt: []
              }
            ]
          })
        })
      );
      try {
        await page.goto(`${url}/code-search`);
        await page.locator('.code-search .cm-content').click();
        await page.keyboard.insertText(SNIPPET);
        await page.click('button[type=submit]');
        await page.waitForSelector('.code-search-result');
        const meter = page.locator('.code-search-match-map');
        t.match(await page.innerText('.code-search-match-count'), /198 of 220/, 'keeps the precise count');
        t.equal(await meter.locator('.code-search-match-cell').count(), 10, 'caps the visual meter at ten blocks');
        t.equal(await meter.locator('.code-search-match-cell.is-on').count(), 9, 'summarises 90% alignment without a green blob');
      } finally {
        await page.unroute(queryUrl);
      }
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
    });

    await t.test('A too-short or repetitive snippet is not searched', async t => {
      await page.goto(`${url}/code-search`);
      await page.locator('.code-search .cm-content').click();
      await page.keyboard.insertText('int a;\nint b;\nint c;\nint d;\nint e;');
      await page.click('button[type=submit]');
      await page.waitForSelector('.code-search-empty:has-text("too short or too repetitive")');
      t.equal(await page.locator('.code-search-result').count(), 0, 'no noisy matches for a weak snippet');
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
