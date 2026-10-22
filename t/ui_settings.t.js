#!/usr/bin/env node
import {assertNoUnexpectedConsoleErrors, launchUi, openAccountMenu, skipUnlessOnline} from './lib/ui_helpers.js';
import t from 'tap';

t.test('Cavil UI - settings', skipUnlessOnline, async t => {
  const ui = await launchUi('js_ui_settings');
  const {page, url, errorLogs} = ui;

  const save = async () => {
    await page.click('#settings-save');
    await page.waitForSelector('.toast-success');
    await page.waitForSelector('.toast-success', {state: 'detached'});
  };

  try {
    await page.goto(url);
    await page.click('text=Login');

    await t.test('Reachable from the account menu', async t => {
      await page.goto(url);
      await openAccountMenu(page);
      await page.click('.dropdown-item >> text=Settings');
      await page.waitForSelector('#api-keys');
      t.match(await page.title(), /Settings/, 'on the settings page');
      t.same(
        await page.locator('.cavil-settings-nav-heading').allInnerTexts(),
        ['Personal', 'Reviews', 'Integrations', 'Instance'],
        'personal and review settings are kept apart'
      );
      t.equal(await page.innerText('.cavil-settings-nav-item.active'), 'API keys', 'personal settings first');

      await page.click('.cavil-settings-nav-item >> text=Automatic acceptance');
      await page.waitForSelector('#low-risk-enabled');
      t.equal(await page.innerText('.cavil-settings-nav-item.active'), 'Automatic acceptance', 'review settings');
      t.equal(await page.isDisabled('#settings-save'), true, 'nothing to save yet');
      t.match(await page.innerText('.cavil-settings-last-change'), /Using default values/, 'no change yet');
    });

    await t.test('API keys', async t => {
      await page.click('.cavil-settings-nav-item >> text=API keys');
      await page.waitForSelector('#api-keys .empty-state');
      await page.click('[name="add-api-key"]');
      await page.waitForSelector('#api-key-description', {state: 'visible'});
      await page.fill('#api-key-description', 'Settings test key');
      t.equal(await page.locator('#api-key-can-finalize-reviews').count(), 0, 'no accept/reject for read-only keys');
      await page.selectOption('#api-key-type', 'read-write');
      await page.check('#api-key-can-finalize-reviews');
      await page.click('#apiKeyAddButton');
      await page.waitForSelector('#api-keys td >> text=Settings test key');
      await page.waitForSelector('#api-key-description', {state: 'detached'});
      t.pass('form closes after adding');
      t.match(await page.innerText('#api-keys tbody'), /read-write\s+accept\/reject/, 'accept/reject marked');
      t.match(await page.innerText('#api-keys .cavil-list-title'), /1\s+API key\b/, 'counted in the list header');

      page.once('dialog', dialog => dialog.accept());
      await page.click('[title="Delete API key"]');
      await page.waitForSelector('#api-keys .empty-state');
      t.pass('deleted');

      await page.click('.cavil-settings-nav-item >> text=Automatic acceptance');
      await page.waitForSelector('#low-risk-enabled');
    });

    await t.test('Switch the low-risk rule off and on', async t => {
      t.equal(await page.isChecked('#low-risk-enabled'), false, 'off in tests');
      t.equal(await page.locator('#auto-accept-risk').count(), 0, 'no level to pick while off');

      await page.check('#low-risk-enabled');
      await page.waitForSelector('#auto-accept-risk');
      t.equal(await page.inputValue('#auto-accept-risk'), '2', 'default level preselected');
      t.match(await page.innerText('#auto-accept-risk'), /2 - Permissive/, 'levels have names');
      t.match(await page.innerText('#auto-accept-risk'), /4 - Strong Copyleft/, 'up to the reviewed-before risk');
      t.notMatch(await page.innerText('#auto-accept-risk'), /5 - /, 'not beyond it');

      await page.selectOption('#auto-accept-risk', '1');
      await save();
      await page.reload();
      await page.waitForSelector('#auto-accept-risk');
      t.equal(await page.inputValue('#auto-accept-risk'), '1', 'saved');
      t.match(await page.innerText('.cavil-settings-last-change'), /Last changed by tester/, 'who changed it');
    });

    await t.test('Lowering the reviewed-before risk caps the low-risk rule', async t => {
      await page.selectOption('#auto-accept-risk', '3');
      await page.selectOption('#acceptable-risk', '2');
      t.equal(await page.inputValue('#auto-accept-risk'), '2', 'capped');
      await save();
      t.equal(await page.locator('[data-reset="acceptable_risk"]').count(), 1, 'changed setting can be reset');

      await page.click('[data-reset="acceptable_risk"]');
      await page.waitForSelector('[data-default="acceptable_risk"]');
      t.equal(await page.inputValue('#acceptable-risk'), '4', 'back to the default');
      t.equal(await page.inputValue('#auto-accept-risk'), '2', 'other setting kept');
    });

    await t.test('Package names', async t => {
      await page.fill('#acceptable-packages input', 'my-placeholder');
      await page.keyboard.press('Enter');
      await save();
      await page.reload();
      await page.waitForSelector('[data-note-tag-chip="my-placeholder"]');
      t.pass('new name kept');
      t.equal(await page.locator('[data-note-tag-chip="000product"]').count(), 1, 'defaults still there');
    });

    await t.test('History lands on the audit log', async t => {
      await page.click('.cavil-settings-last-change a');
      await page.waitForSelector('#audit-log-category');
      t.equal(await page.inputValue('#audit-log-category'), 'settings', 'filtered to settings');
      await page.waitForSelector('text=Settings changed');
      t.match(await page.innerText('body'), /Always accept these packages: .* → .*my-placeholder/, 'readable change');
    });

    await t.test('Excluded files', async t => {
      await page.goto(`${url}/settings/excluded-files`);
      await page.waitForSelector('text=No excluded files.');
      await page.click('#add-exclusion');
      await page.fill('#exclusion-package', 'rust*');
      await page.fill('#exclusion-file', 'r.zip');
      await page.fill('#exclusion-reason', 'Zip bomb');
      await page.click('#save-exclusion');
      await page.waitForSelector('td >> text=Zip bomb');
      t.match(await page.innerText('.cavil-settings-last-change'), /Last changed by tester/, 'who changed it');

      page.once('dialog', dialog => dialog.accept());
      await page.click('[title="Remove excluded file"]');
      await page.waitForSelector('text=No excluded files.');
      t.pass('removed');
    });

    await t.test('Bot tokens', async t => {
      await page.click('.cavil-settings-nav-item >> text=Bot tokens');
      await page.waitForSelector('#bot-tokens td >> text=test_token');
      t.match(await page.innerText('#bot-tokens .cavil-list-title'), /1\s+bot token\b/, 'the token the tests run with');

      await page.click('[name="add-bot-token"]');
      await page.fill('#bot-token-description', 'Gitea bot');
      await page.click('#save-bot-token');
      await page.waitForSelector('#bot-tokens td >> text=Gitea bot');

      await page.click('[name="add-bot-token"]');
      await page.fill('#bot-token-description', 'Pasted');
      await page.fill('#bot-token-value', 'short');
      await page.click('#save-bot-token');
      await page.waitForSelector('.toast-danger >> text=at least 16 characters');
      t.pass('short tokens are refused');
      await page.fill('#bot-token-value', 'an-existing-bot-token');
      await page.click('#save-bot-token');
      await page.waitForSelector('#bot-tokens td >> text=Pasted');
      t.match(await page.innerText('#bot-tokens .cavil-list-title'), /3\s+bot tokens/, 'generated and pasted');
      t.match(await page.innerText('.cavil-settings-last-change'), /Last changed by tester/, 'who changed it');

      page.once('dialog', dialog => dialog.accept());
      await page.locator('#bot-tokens tr', {hasText: 'Pasted'}).locator('[title="Remove bot token"]').click();
      await page.waitForSelector('#bot-tokens td >> text=Pasted', {state: 'detached'});
      t.pass('removed');
    });

    await t.test('SBOM creator', async t => {
      await page.click('.cavil-settings-nav-item >> text=SBOM');
      await page.waitForSelector('#sbom-creator-name');
      t.equal(await page.getAttribute('#sbom-creator-name', 'placeholder'), 'cavil.example.com', 'shows the fallback');
      t.equal(await page.locator('#sbom-contact-missing').count(), 1, 'warns while there is no contact');
      t.equal(await page.getAttribute('#sbom-creator-url', 'placeholder'), '', 'no made up web address');
      await page.fill('#sbom-creator-name', 'ACME Corp');
      await page.fill('#sbom-creator-email', 'sbom@acme.example');
      await save();
      await page.reload();
      await page.waitForSelector('#sbom-creator-name');
      t.equal(await page.inputValue('#sbom-creator-name'), 'ACME Corp', 'saved');
      t.equal(await page.locator('#sbom-contact-missing').count(), 0, 'warning gone with an email address');

      await page.click('[data-reset="sbom_creator_name"]');
      await page.waitForSelector('[data-default="sbom_creator_name"]');
      t.equal(await page.inputValue('#sbom-creator-name'), '', 'back to the fallback');
      t.equal(await page.inputValue('#sbom-creator-email'), 'sbom@acme.example', 'other field kept');
    });

    await t.test('Status', async t => {
      await page.click('.cavil-settings-nav-item >> text=Status');
      await page.waitForSelector('#status td.cavil-status-name');
      const names = await page.locator('#status td.cavil-status-name').allInnerTexts();
      t.same(names.slice(0, 3), ['Database', 'License patterns', 'Workers'], 'checks in order');
      t.equal(await page.locator('#status td.cavil-status-ok >> text=Database').count(), 1, 'schema is current');
      t.match(await page.innerText('#status .cavil-list-title'), /checks? needs? attention/, 'problems summarized');
    });

    t.test('Console errors', t => {
      assertNoUnexpectedConsoleErrors(t, errorLogs);
      t.end();
    });
  } finally {
    await ui.teardown();
  }
});
