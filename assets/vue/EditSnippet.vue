<template>
  <div>
    <div v-if="error" class="alert alert-danger" role="alert">{{ error }}</div>
    <SnippetEditor
      :snippet-id="currentSnippet"
      :hash="hash"
      :from="from"
      :has-contributor-role="hasContributorRole"
      :has-admin-role="hasAdminRole"
      mode="page"
      @submit="onSubmit"
    />
  </div>
</template>

<script>
import SnippetEditor from './components/SnippetEditor.vue';
import {getParams} from './helpers/params.js';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'EditSnippet',
  components: {SnippetEditor},
  data() {
    const params = getParams();
    return {
      error: null,
      from: params.from === '' ? null : (params.from ?? null),
      hash: params.hash === '' ? null : (params.hash ?? null)
    };
  },
  methods: {
    async onSubmit(payload) {
      this.error = null;
      const ua = new UserAgent({baseURL: window.location.href});
      const body = {
        actions: [{kind: payload.action, snippetId: this.currentSnippet, formData: payload.formData}]
      };
      const res = await ua.post('/snippet/batch_decision', {
        json: body,
        headers: {Accept: 'application/json'}
      });
      let data = null;
      try {
        data = await res.json();
      } catch (e) {
        // ignore parse errors, handled below
      }
      if (res.isSuccess && data && data.ok) {
        const result = data.results[0];
        if (result.kind === 'pattern' && result.id) {
          window.location.href = `/licenses/edit_pattern/${result.id}`;
          return;
        }
        window.location.href = '/snippets';
        return;
      }
      const result = data && data.results && data.results[0];
      this.error = (result && result.error) || (data && data.error) || `Request failed (HTTP ${res.statusCode})`;
    }
  }
};
</script>
