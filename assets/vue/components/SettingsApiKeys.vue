<template>
  <section id="api-keys">
    <div class="cavil-settings-header">
      <h3>API keys</h3>
      <p>
        Keys let scripts, command-line tools and AI assistants use Cavil on your behalf. See the
        <a target="_blank" href="https://github.com/openSUSE/cavil/blob/master/docs/UserAPI.md">API documentation</a>
        for what they can do.
      </p>
    </div>

    <div class="cavil-settings-actions">
      <button name="add-api-key" type="button" class="btn btn-success" @click="adding = !adding">Add API key</button>
    </div>
    <Transition name="cavil-reveal">
      <div v-if="adding" class="cavil-reveal">
        <form class="cavil-settings-inline-form" @submit.prevent="addApiKey()">
          <div class="cavil-settings-inline-form-wide">
            <label for="api-key-description" class="form-label">Description</label>
            <input v-model="apiKeyDescription" class="form-control" id="api-key-description" />
            <div class="form-text">What the key is for, so you recognise it later.</div>
          </div>
          <div>
            <label for="api-key-type" class="form-label">Access</label>
            <select v-model="apiKeyType" class="form-select" id="api-key-type">
              <option value="read-only">Read-only</option>
              <option value="read-write">Read-write</option>
            </select>
          </div>
          <div>
            <label for="api-key-expires" class="form-label">Expires</label>
            <input v-model="apiKeyExpires" type="datetime-local" class="form-control" id="api-key-expires" />
          </div>
          <div v-if="apiKeyType === 'read-write'" class="cavil-settings-inline-form-wide form-check">
            <input
              v-model="apiKeyCanFinalizeReviews"
              type="checkbox"
              class="form-check-input"
              id="api-key-can-finalize-reviews"
            />
            <label class="form-check-label" for="api-key-can-finalize-reviews">Allow accept/reject of reviews</label>
            <div class="form-text">
              Leave off unless you intend to use the <code>cavil_accept_review</code> /
              <code>cavil_reject_review</code> MCP tools.
            </div>
          </div>
          <div class="cavil-settings-inline-form-buttons">
            <button type="button" class="btn btn-secondary" @click="adding = false">Cancel</button>
            <button type="submit" class="btn btn-success" id="apiKeyAddButton">Add</button>
          </div>
        </form>
      </div>
    </Transition>
    <section class="cavil-list-panel">
      <div class="cavil-list-header">
        <div class="cavil-list-title">
          <i class="fa-solid fa-key" aria-hidden="true"></i>
          <strong>{{ apiKeys === null ? 0 : apiKeys.length }}</strong>
          <span>{{ apiKeys !== null && apiKeys.length === 1 ? 'API key' : 'API keys' }}</span>
        </div>
      </div>
      <div class="cavil-list-table-wrap">
        <table class="cavil-list-table table">
          <thead>
            <tr>
              <th>Key</th>
              <th>Type</th>
              <th>Description</th>
              <th>Expires</th>
              <th></th>
            </tr>
          </thead>
          <tbody v-if="apiKeys === null">
            <tr>
              <td colspan="5" class="cavil-list-state"><LegalLoading message="Loading API keys..." size="small" /></td>
            </tr>
          </tbody>
          <tbody v-else-if="apiKeys.length > 0">
            <tr v-for="key in apiKeys" :key="key.id">
              <td>
                <copyable-text
                  :value="key.apiKey"
                  class="cavil-secret"
                  title="Click to copy"
                  aria-label="Reveal API key on hover, click to copy"
                >
                  <span class="real">{{ key.apiKey }}</span>
                </copyable-text>
              </td>
              <td>
                {{ key.type }}
                <span
                  v-if="key.canFinalizeReviews"
                  class="badge bg-warning text-dark ms-1"
                  title="This key can accept or reject reviews via MCP"
                  data-can-finalize-reviews
                  >accept/reject</span
                >
              </td>
              <td>{{ key.description }}</td>
              <td class="cavil-list-time">{{ key.expires }}</td>
              <td class="text-center">
                <button
                  @click="deleteApiKey(key)"
                  type="button"
                  class="cavil-icon-action cavil-icon-action-danger"
                  title="Delete API key"
                  aria-label="Delete API key"
                >
                  <i class="fa-solid fa-trash"></i>
                </button>
              </td>
            </tr>
          </tbody>
          <tbody v-else>
            <tr>
              <td colspan="5" class="cavil-list-empty-cell">
                <EmptyState title="No API keys yet" icon="fa-key" message="No API keys found." />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    <ToastNotifier ref="toaster" />
  </section>
</template>

<script>
import CopyableText from './CopyableText.vue';
import EmptyState from './EmptyState.vue';
import LegalLoading from './LegalLoading.vue';
import ToastNotifier from './ToastNotifier.vue';
import Refresh from '../mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'SettingsApiKeys',
  components: {CopyableText, EmptyState, LegalLoading, ToastNotifier},
  mixins: [Refresh],
  data() {
    return {
      adding: false,
      addApiKeyUrl: '/api_keys',
      apiKeys: null,
      apiKeyDescription: 'User API Key',
      apiKeyType: 'read-only',
      apiKeyCanFinalizeReviews: false,
      apiKeyExpires: new moment().add(365, 'days').format('YYYY-MM-DDTHH:mm'),
      refreshUrl: '/api_keys/meta'
    };
  },
  methods: {
    async addApiKey() {
      const ua = new UserAgent({baseURL: window.location.href});
      const form = {
        description: this.apiKeyDescription,
        type: this.apiKeyType,
        expires: this.apiKeyExpires,
        can_finalize_reviews: this.apiKeyType === 'read-write' && this.apiKeyCanFinalizeReviews ? '1' : '0'
      };
      const res = await ua.post(this.addApiKeyUrl, {form});
      if (!res.isSuccess) {
        const data = await res.json().catch(() => ({}));
        this.$refs.toaster.notify(data.error ?? 'API key could not be added', 'danger', 5000);
        return;
      }
      this.adding = false;
      this.apiKeyDescription = 'User API Key';
      this.apiKeyType = 'read-only';
      this.apiKeyCanFinalizeReviews = false;
      this.$refs.toaster.notify('API key added.');
      this.doApiRefresh();
    },
    async deleteApiKey(key) {
      if (!window.confirm(`Delete the API key "${key.description}"? Anything using it stops working.`)) return;
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(key.removeUrl, {query: {_method: 'DELETE'}});
      this.doApiRefresh();
    },
    refreshData(data) {
      const apiKeys = [];
      for (const key of data.keys) {
        apiKeys.push({
          id: key.id,
          apiKey: key.api_key,
          description: key.description,
          type: key.write_access ? 'read-write' : 'read-only',
          canFinalizeReviews: !!key.can_finalize_reviews,
          expires: moment(key.expires_epoch * 1000).fromNow(),
          removeUrl: `/api_keys/${key.id}`
        });
      }
      this.apiKeys = apiKeys;
    }
  }
};
</script>

<style>
.table {
  margin-top: 1rem;
}
</style>
