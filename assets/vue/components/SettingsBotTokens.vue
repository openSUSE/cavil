<template>
  <section id="bot-tokens">
    <div class="cavil-settings-header">
      <h3>Bot tokens</h3>
      <p>
        Tokens let bots, such as the build service and Git hosting integrations, submit packages through the
        <a target="_blank" href="https://github.com/openSUSE/cavil/blob/master/docs/BotAPI.md">bot API</a>. Every bot
        should have its own token, so one can be removed without locking out the others.
      </p>
    </div>

    <div class="cavil-settings-actions">
      <button name="add-bot-token" type="button" class="btn btn-success" @click="adding = !adding">
        Add bot token
      </button>
    </div>
    <Transition name="cavil-reveal">
      <div v-if="adding" class="cavil-reveal">
        <form class="cavil-settings-inline-form" @submit.prevent="add()">
          <div class="cavil-settings-inline-form-wide">
            <label for="bot-token-description" class="form-label">Description</label>
            <input v-model="token.description" class="form-control" id="bot-token-description" />
            <div class="form-text">Which bot uses it, so you know what stops working when it is removed.</div>
          </div>
          <div class="cavil-settings-inline-form-wide">
            <label for="bot-token-value" class="form-label">Token</label>
            <input v-model="token.token" class="form-control" id="bot-token-value" autocomplete="off" />
            <div class="form-text">Leave empty to generate one, or paste the token a bot already uses.</div>
          </div>
          <div class="cavil-settings-inline-form-buttons">
            <button type="button" class="btn btn-secondary" @click="adding = false">Cancel</button>
            <button type="submit" class="btn btn-success" id="save-bot-token">Add</button>
          </div>
        </form>
      </div>
    </Transition>

    <section class="cavil-list-panel">
      <div class="cavil-list-header">
        <div class="cavil-list-title">
          <i class="fa-solid fa-robot" aria-hidden="true"></i>
          <strong>{{ tokens === null ? 0 : tokens.length }}</strong>
          <span>{{ tokens !== null && tokens.length === 1 ? 'bot token' : 'bot tokens' }}</span>
        </div>
      </div>
      <div class="cavil-list-table-wrap">
        <table class="cavil-list-table table">
          <thead>
            <tr>
              <th>Token</th>
              <th>Description</th>
              <th>Added</th>
              <th></th>
            </tr>
          </thead>
          <tbody v-if="tokens === null">
            <tr>
              <td colspan="4" class="cavil-list-state">
                <LegalLoading message="Loading bot tokens..." size="small" />
              </td>
            </tr>
          </tbody>
          <tbody v-else-if="tokens.length > 0">
            <tr v-for="item in tokens" :key="item.id">
              <td>
                <copyable-text
                  :value="item.token"
                  class="cavil-secret"
                  title="Click to copy"
                  aria-label="Reveal bot token on hover, click to copy"
                >
                  <span class="real">{{ item.token }}</span>
                </copyable-text>
              </td>
              <td>{{ item.description }}</td>
              <td class="cavil-list-time">{{ item.login ?? 'Cavil' }}, {{ item.created }}</td>
              <td class="text-center">
                <button
                  @click="remove(item)"
                  type="button"
                  class="cavil-icon-action cavil-icon-action-danger"
                  title="Remove bot token"
                  aria-label="Remove bot token"
                >
                  <i class="fa-solid fa-trash"></i>
                </button>
              </td>
            </tr>
          </tbody>
          <tbody v-else>
            <tr>
              <td colspan="4" class="cavil-list-empty-cell">
                <EmptyState
                  title="No bot tokens yet"
                  icon="fa-robot"
                  message="The bot API refuses every request until a token is added."
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <div class="cavil-settings-footer">
      <SettingsLastChange :change="lastChange" empty="No changes recorded yet" />
    </div>
    <ToastNotifier ref="toaster" />
  </section>
</template>

<script>
import CopyableText from './CopyableText.vue';
import EmptyState from './EmptyState.vue';
import LegalLoading from './LegalLoading.vue';
import SettingsLastChange from './SettingsLastChange.vue';
import ToastNotifier from './ToastNotifier.vue';
import Refresh from '../mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'SettingsBotTokens',
  components: {CopyableText, EmptyState, LegalLoading, SettingsLastChange, ToastNotifier},
  mixins: [Refresh],
  data() {
    return {
      adding: false,
      lastChange: null,
      refreshUrl: '/settings/bot-tokens.json',
      token: {description: '', token: ''},
      tokens: null
    };
  },
  methods: {
    async add() {
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.post('/settings/bot-tokens', {form: this.token});
      if (!res.isSuccess) {
        const data = await res.json().catch(() => ({}));
        this.$refs.toaster.notify(data.error ?? 'Bot token could not be added', 'danger', 5000);
        return;
      }
      this.adding = false;
      this.token = {description: '', token: ''};
      this.$refs.toaster.notify('Bot token added.');
      this.refreshNow();
    },
    refreshData(data) {
      this.lastChange = data.last_change;
      this.tokens = data.tokens.map(item => ({...item, created: moment(item.created_epoch * 1000).fromNow()}));
    },
    refreshNow() {
      this.cancelApiRefresh();
      this.doApiRefresh();
    },
    async remove(item) {
      const name = item.description || 'this bot token';
      if (!window.confirm(`Remove ${name}? The bot using it can no longer submit anything.`)) return;
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(`/settings/bot-tokens/${item.id}`, {query: {_method: 'DELETE'}});
      this.refreshNow();
    }
  }
};
</script>
