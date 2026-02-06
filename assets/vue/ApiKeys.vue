<template>
  <div>
    <div class="row">
      <div class="col-12 alert alert-primary" role="alert">
        These API keys can be used to authenticate API requests. See
        <a target="_blank" href="https://github.com/openSUSE/cavil/blob/master/docs/UserAPI.md">API documentation</a>
        for more details.
        <button
          name="add-api-key"
          class="btn btn-primary float-end"
          data-bs-toggle="modal"
          data-bs-target="#apiKeyModal"
        >
          Add API Key
        </button>
      </div>
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
                <td id="all-done" colspan="4"><i class="fas fa-sync fa-spin"></i> Loading API keys...</td>
              </tr>
            </tbody>
            <tbody v-else-if="apiKeys.length > 0">
              <tr v-for="key in apiKeys" :key="key.id">
                <td>
                  <span
                    class="api-key"
                    :class="{copied: lastCopied === key.id}"
                    tabindex="0"
                    role="button"
                    aria-label="Reveal API key on hover, click to copy"
                    title="Click to copy"
                    @click.prevent="copyApiKey(key.id, key.apiKey)"
                  >
                    <span class="real">{{ key.apiKey }}</span>
                  </span>
                </td>
                <td>{{ key.type }}</td>
                <td>{{ key.description }}</td>
                <td>{{ key.expires }}</td>
                <td class="text-center">
                  <span class="cavil-action text-center">
                    <a @click="deleteApiKey(key)" href="#"><i class="fas fa-trash"></i></a>
                  </span>
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
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'ApiKeys',
  mixins: [Refresh],
  data() {
    return {
      addApiKeyUrl: '/api_keys',
      apiKeys: null,
      apiKeyDescription: 'User API Key',
      apiKeyType: 'read-only',
      apiKeyExpires: new moment().add(365, 'days').format('YYYY-MM-DDTHH:mm'),
      lastCopied: null,
      refreshUrl: '/api_keys/meta'
    };
  },
  methods: {
    async copyApiKey(keyId, apiKey) {
      await navigator.clipboard.writeText(apiKey);
      this.lastCopied = keyId;
      setTimeout(() => {
        if (this.lastCopied === keyId) this.lastCopied = null;
      }, 2000);
    },
    async addApiKey() {
      const ua = new UserAgent({baseURL: window.location.href});
      const form = {description: this.apiKeyDescription, type: this.apiKeyType, expires: this.apiKeyExpires};
      await ua.post(this.addApiKeyUrl, {form});
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
.cavil-action a {
  color: #212529;
  text-decoration: none;
}
#all-done {
  text-align: center;
}
.api-key {
  cursor: pointer;
  display: inline-block;
}
.api-key .real {
  display: inline-block;
  filter: blur(6px);
  transition: filter 0.15s ease;
  user-select: none;
}
.api-key:hover .real {
  filter: none;
  user-select: text;
}
.api-key.copied::after {
  content: ' Copied!';
  color: #28a745;
  font-weight: 500;
  margin-left: 0.5rem;
}
</style>
