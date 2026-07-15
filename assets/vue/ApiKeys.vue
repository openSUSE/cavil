<template>
  <div>
    <div class="row mt-3">
      <cavil-notice-panel intro class="col-12">
        These API keys can be used to authenticate API requests. See
        <a target="_blank" href="https://github.com/openSUSE/cavil/blob/master/docs/UserAPI.md">API documentation</a>
        for more details.
        <button name="add-api-key" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#apiKeyModal">
          Add API Key
        </button>
      </cavil-notice-panel>
    </div>
    <div>
      <div class="row">
        <div class="col-12">
          <table class="table table-striped table-bordered">
            <thead>
              <tr>
                <th>API Key</th>
                <th>Type</th>
                <th>Description</th>
                <th>Expires</th>
                <th></th>
              </tr>
            </thead>
            <tbody v-if="apiKeys === null">
              <tr>
                <td id="all-done" colspan="4"><LegalLoading message="Loading API keys..." size="small" /></td>
              </tr>
            </tbody>
            <tbody v-else-if="apiKeys.length > 0">
              <tr v-for="key in apiKeys" :key="key.id">
                <td>
                  <copyable-text
                    :value="key.apiKey"
                    class="api-key"
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
                <td>{{ key.expires }}</td>
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
                <td id="all-done" colspan="5">No API keys found.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    <div class="modal fade" id="apiKeyModal" tabindex="-1" aria-labelledby="apiKeyModalLabel" aria-hidden="true">
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title" id="apiKeyModalLabel">Add API Key</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body">
            <form>
              <div class="mb-3">
                <label for="api-key-description" class="col-form-label">Description</label>
                <input v-model="apiKeyDescription" class="form-control" id="api-key-description" />
              </div>
              <div class="mb-3">
                <label for="api-key-type" class="col-form-label">Type</label>
                <select v-model="apiKeyType" class="form-select" id="api-key-type">
                  <option value="read-only">Read-Only</option>
                  <option value="read-write">Read-Write</option>
                </select>
              </div>
              <div v-if="apiKeyType === 'read-write'" class="mb-3 form-check">
                <input
                  v-model="apiKeyCanFinalizeReviews"
                  type="checkbox"
                  class="form-check-input"
                  id="api-key-can-finalize-reviews"
                />
                <label class="form-check-label" for="api-key-can-finalize-reviews">
                  Allow accept/reject of reviews
                </label>
                <div class="form-text">
                  Leave off unless you intend to use the <code>cavil_accept_review</code> /
                  <code>cavil_reject_review</code> MCP tools.
                </div>
              </div>
              <div class="mb-3">
                <label for="api-key-expires" class="col-form-label">Expires</label>
                <input v-model="apiKeyExpires" type="datetime-local" class="form-control" id="api-key-expires" />
              </div>
            </form>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
            <button
              @click="addApiKey()"
              type="button"
              id="apiKeyAddButton"
              class="btn btn-primary"
              data-bs-dismiss="modal"
            >
              Add
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import CopyableText from './components/CopyableText.vue';
import LegalLoading from './components/LegalLoading.vue';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'ApiKeys',
  components: {CavilNoticePanel, CopyableText, LegalLoading},
  mixins: [Refresh],
  data() {
    return {
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
      await ua.post(this.addApiKeyUrl, {form});
      this.apiKeyCanFinalizeReviews = false;
      this.doApiRefresh();
    },
    async deleteApiKey(key) {
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
#all-done {
  text-align: center;
}
.api-key .real {
  display: inline-block;
  filter: blur(6px);
  transition: filter 0.15s ease;
  user-select: none;
}
.api-key:hover .real,
.api-key:focus .real {
  filter: none;
  user-select: text;
}
</style>
