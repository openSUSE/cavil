<template>
  <div>
    <div class="row mt-3">
      <cavil-notice-panel intro class="col-12">
        Snippets Cavil could not identify. Some have been researched and come with a proposed license you can approve
        directly; the rest are flagged for you to assess.
      </cavil-notice-panel>
    </div>
    <div v-if="changes !== null && changes.length > 0">
      <transition-group name="row" tag="div" @before-leave="onBeforeLeave" @leave="onLeave">
        <div v-for="change in changes" :key="change.id" class="row change-container">
          <div v-if="change.state === 'proposed'" class="col-12 change-file-container">
            <div class="change-header">
              <div class="change-title">
                <span v-if="change.action === 'missing_license'">
                  Missing license reported by <b>{{ change.login }}</b>
                  <span class="cavil-meta-badges change-meta-badges">
                    <span class="cavil-meta-badge cavil-meta-badge-danger">missing license</span>
                    <span v-if="change.data.ai_assisted" class="cavil-meta-badge cavil-meta-badge-info">
                      <i class="fa-solid fa-robot"></i> AI assisted
                    </span>
                    <a :href="change.editUrl" target="_blank" class="cavil-meta-badge cavil-meta-badge-muted">
                      snippet
                    </a>
                    <a
                      v-if="change.package !== null"
                      :href="change.package.pkgUrl"
                      target="_blank"
                      class="cavil-meta-badge cavil-meta-badge-muted"
                    >
                      {{ change.package.name }}
                    </a>
                  </span>
                </span>
                <span v-else-if="change.action === 'new_license'">
                  Proposed license by <b>{{ change.login }}</b>
                  <span class="cavil-meta-badges change-meta-badges">
                    <span class="cavil-meta-badge cavil-meta-badge-success">{{ change.data.license }}</span>
                    <span class="cavil-meta-badge cavil-meta-badge-warning">risk {{ change.data.risk }}</span>
                    <span v-if="change.data.ai_assisted" class="cavil-meta-badge cavil-meta-badge-info">
                      <i class="fa-solid fa-robot"></i> AI assisted
                    </span>
                    <a :href="change.editUrl" target="_blank" class="cavil-meta-badge cavil-meta-badge-muted">
                      snippet
                    </a>
                    <a
                      v-if="change.package !== null"
                      :href="change.package.pkgUrl"
                      target="_blank"
                      class="cavil-meta-badge cavil-meta-badge-muted"
                    >
                      {{ change.package.name }}
                    </a>
                  </span>
                </span>
              </div>
              <div v-if="currentUser === change.login" class="change-actions">
                <button
                  @click="dismissProposal(change)"
                  type="button"
                  class="cavil-icon-action cavil-icon-action-danger"
                  title="Dismiss proposal"
                  aria-label="Dismiss proposal"
                >
                  <i class="fa-solid fa-xmark"></i>
                </button>
              </div>
            </div>
            <div class="change-source">
              <table>
                <tbody>
                  <tr v-for="line in change.lines" :key="line.num" :class="getClassForLine(line)">
                    <td class="linenumber">{{ line.num }}</td>
                    <td class="code">{{ line.text }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div
              v-if="change.action === 'new_license' && change.reason_html"
              class="change-band change-rationale markdown-body"
              v-html="change.reason_html"
            ></div>
            <div
              v-else-if="change.action === 'missing_license' && change.data.reason"
              class="change-band change-reason"
            >
              <label class="form-label">Reason</label>
              <textarea v-model="change.data.reason" class="form-control" disabled="disabled" rows="3"></textarea>
            </div>

            <div v-if="hasAdminRole && editingId !== change.id" class="change-band change-actions-bar">
              <template v-if="change.action === 'new_license'">
                <button @click="approveProposal(change)" type="button" class="btn btn-success">Approve</button>
                <button @click="toggleEditor(change)" type="button" class="btn btn-outline-primary btn-sm">Edit</button>
                <button @click="dismissProposal(change)" type="button" class="btn btn-outline-danger btn-sm">
                  Dismiss
                </button>
              </template>
              <template v-else>
                <button @click="toggleEditor(change)" type="button" class="btn btn-primary">Edit Pattern</button>
                <button @click="dismissProposal(change)" type="button" class="btn btn-danger btn-sm">Dismiss</button>
              </template>
            </div>

            <div v-if="editingId === change.id" id="inline-snippet-editor" class="change-band change-editor">
              <SnippetEditor
                :key="`missing-editor-${change.id}-${editorVersion}`"
                :snippet-id="Number(change.data.snippet)"
                :hash="change.token_hexsum"
                :from="change.data.from"
                :has-admin-role="hasAdminRole"
                :has-contributor-role="hasContributorRole"
                :allowed-actions="['create-pattern']"
                :initial="editorInitial(change)"
                mode="inline"
                @submit="onEditorSubmit(change, $event)"
                @cancel="editingId = null"
              />
            </div>
            <div v-if="change.action === 'missing_license'" class="change-footer">
              <div v-if="change.closest !== null">
                <a :href="change.closest.licenseUrl" target="_blank">
                  <b>{{ change.closest.similarity }}%</b> similarity to
                  <b>{{ change.closest.license_name === '' ? 'Keyword Pattern' : change.closest.license_name }}</b
                  >, estimated risk
                  {{ change.closest.risk }}
                </a>
              </div>
              <div v-else>No similarity to any known licenses</div>
            </div>
          </div>
          <div v-else-if="change.state === 'updating'" class="col-12">
            <div class="change-confirmation"><i class="fa-solid fa-rotate fa-spin"></i> Updating proposal</div>
          </div>
        </div>
      </transition-group>
      <div v-if="loadingMore" class="text-center text-muted my-3">
        <LegalLoading message="Loading more missing licenses" size="small" />
      </div>
      <BackToTop />
    </div>
    <div v-else-if="changes === null"><LegalLoading message="Loading missing licenses" /></div>
    <EmptyState v-else message="No missing licenses have been flagged. Nice work keeping the queue clear." />
    <ToastNotifier ref="toaster" />
  </div>
</template>

<script>
import BackToTop from './components/BackToTop.vue';
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import EmptyState from './components/EmptyState.vue';
import LegalLoading from './components/LegalLoading.vue';
import SnippetEditor from './components/SnippetEditor.vue';
import ToastNotifier from './components/ToastNotifier.vue';
import UserAgent from '@mojojs/user-agent';

// Per-license flags carried on a new_license proposal, stored as JSON 0/1.
const PROPOSAL_FLAGS = ['patent', 'trademark', 'export_restricted', 'cla', 'eula'];

export default {
  name: 'MissingLicenses',
  components: {BackToTop, CavilNoticePanel, EmptyState, LegalLoading, SnippetEditor, ToastNotifier},
  data() {
    return {
      ignoreForPackage: true,
      params: {before: 0},
      changes: null,
      changeUrl: '/licenses/proposed/meta?action=missing_license&action=new_license',
      total: null,
      loadingMore: false,
      editingId: null,
      editorVersion: 0
    };
  },
  mounted() {
    window.addEventListener('scroll', this.handleScroll);
    this.getChanges();
  },
  beforeDestroy() {
    window.removeEventListener('scroll', this.handleScroll);
  },
  methods: {
    async getChanges() {
      const query = this.params;
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.get(this.changeUrl, {query});
      const data = await res.json();

      const changes = data.changes;
      if (this.total === null || this.total < data.total) this.total = data.total;

      for (const change of changes) {
        change.state = 'proposed';
        change.editUrl = `/snippet/edit/${change.data.snippet}?hash=${change.token_hexsum}&from=${change.data.from}`;
        change.removeUrl = `/licenses/proposed/remove/${change.token_hexsum}`;

        if (change.package !== null) change.package.pkgUrl = `/reviews/details/${change.package.id}`;
        if (change.closest !== null) change.closest.licenseUrl = `/licenses/edit_pattern/${change.closest.id}`;

        if (change.data.ai_assisted !== undefined) change.data.ai_assisted = change.data.ai_assisted == 1;

        const highlightedKeywords = change.data.highlighted_keywords ?? [];
        const highlightedLicenses = change.data.highlighted_licenses ?? [];
        let num = 0;
        const lines = [];
        for (const text of change.data.pattern.split('\n')) {
          const isKeyword = highlightedKeywords.includes(num.toString());
          const isLicense = highlightedLicenses.includes(num.toString());
          const highlighted = isLicense ? 'license' : isKeyword ? 'keyword' : null;
          lines.push({num: ++num, text, highlighted});
        }
        change.lines = lines;

        query.before = change.id;
      }

      if (this.changes === null) this.changes = [];
      this.changes.push(...changes);
    },
    getClassForLine(line) {
      return {
        'change-keyword-line': line.highlighted === 'keyword',
        'change-license-line': line.highlighted === 'license'
      };
    },
    handleScroll() {
      if (window.innerHeight + Math.ceil(window.scrollY) >= document.documentElement.scrollHeight) {
        this.loadMore();
      }
    },
    async loadMore() {
      if (this.loadingMore) return;
      if (this.changes !== null && this.total !== null && this.changes.length >= this.total) return;
      this.loadingMore = true;
      try {
        await this.getChanges();
      } finally {
        this.loadingMore = false;
      }
    },
    async dismissProposal(change) {
      const wasProposal = change.action === 'new_license';
      change.state = 'updating';
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(change.removeUrl);
      this.removeChange(change);
      this.$refs.toaster?.notify('Proposal dismissed', 'danger');

      // Dismissing a new-license proposal un-hides the missing-license report it was covering (the report
      // is kept, only the proposal is removed). Reload so that report re-appears immediately instead of
      // only on the next page load - otherwise the card just vanishes and looks like the report was lost.
      if (wasProposal) await this.reloadChanges();
    },
    async reloadChanges() {
      this.changes = null;
      this.total = null;
      this.params.before = 0;
      await this.getChanges();
    },
    toggleEditor(change) {
      this.editingId = this.editingId === change.id ? null : change.id;
      this.editorVersion++;
    },
    async onEditorSubmit(change, payload) {
      const formData = {...payload.formData};

      // Creating a real pattern from the snippet should also clear the report. The create-pattern handler
      // removes the proposal when given its checksum (the proposal's token_hexsum).
      if (payload.action === 'create-pattern') formData.checksum = change.token_hexsum;

      await this.submitPattern(change, formData);
    },

    // Ratify a researched new-license proposal as-is: replay the stored pattern/license/risk through the
    // same create-pattern path the inline editor uses, so Approve is just Edit without the editing step.
    async approveProposal(change) {
      const d = change.data;
      const formData = {pattern: d.pattern, license: d.license, risk: String(d.risk), checksum: change.token_hexsum};
      for (const flag of PROPOSAL_FLAGS) {
        if (Number(d[flag])) formData[flag] = '1';
      }
      if (d.from) formData.from = d.from;
      if (change.package !== null) formData.package = change.package.id;
      await this.submitPattern(change, formData);
    },

    async submitPattern(change, formData) {
      const ua = new UserAgent({baseURL: window.location.href});
      const body = {actions: [{kind: 'create-pattern', snippetId: change.data.snippet, formData}]};
      const res = await ua.post('/snippet/batch_decision', {json: body, headers: {Accept: 'application/json'}});

      let data = null;
      try {
        data = await res.json();
      } catch (e) {
        // handled below
      }

      if (res.isSuccess && data && data.ok) {
        this.editingId = null;
        this.removeChange(change);
        this.$refs.toaster?.notify('Pattern created, reindexing related packages in 10 minutes if necessary');
        return;
      }

      const result = data && data.results && data.results[0];
      const message = (result && result.error) || (data && data.error) || `Request failed (HTTP ${res.statusCode})`;
      this.$refs.toaster?.notify(message, 'danger', 5000);
    },

    // Pre-fill the inline editor with the researched values when a lawyer wants to adjust before approving.
    editorInitial(change) {
      if (change.action !== 'new_license') return null;
      const d = change.data;
      // SnippetEditor.applyInitial expects booleans; the flags are stored as JSON 0/1, so coerce here.
      const initial = {pattern: d.pattern, license: d.license, risk: d.risk};
      for (const flag of PROPOSAL_FLAGS) initial[flag] = !!Number(d[flag]);
      return initial;
    },
    removeChange(change) {
      const i = this.changes.indexOf(change);
      if (i !== -1) this.changes.splice(i, 1);
    },
    onBeforeLeave(el) {
      el.style.maxHeight = el.scrollHeight + 'px';
      el.style.overflow = 'hidden';
    },
    onLeave(el) {
      void el.offsetHeight;
      el.style.maxHeight = '0';
      el.style.marginTop = '0';
      el.style.marginBottom = '0';
      el.style.opacity = '0';
    }
  }
};
</script>

<style scoped>
.change-confirmation {
  background-color: rgb(246, 248, 250);
  border: 1px solid rgb(208, 215, 222);
  border-radius: 0.25rem;
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.change-container {
  margin-bottom: 4rem;
  margin-top: 1rem;
}
.row-leave-active {
  transition:
    max-height 0.35s ease,
    opacity 0.25s ease,
    margin 0.35s ease;
}
.row-move {
  transition: transform 0.3s ease;
}
.change-header {
  align-items: center;
  background-color: rgb(246, 248, 250);
  border-bottom: 1px solid rgb(208, 215, 222);
  display: flex;
  font-size: 13px;
  gap: 0.75rem;
  justify-content: space-between;
  line-height: 20px;
  padding: 10px;
}
.change-title {
  min-width: 0;
}
.change-title > span {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
}
.change-meta-badges {
  margin-left: 0.25rem;
}
.change-actions {
  align-items: center;
  display: flex;
  flex: 0 0 auto;
  gap: 0.4rem;
}
.change-header a,
.change-file a,
.change-footer a {
  color: #212529;
  text-decoration: none;
}
.change-header a:hover b,
.change-file a:hover,
.change-footer a:hover {
  text-decoration: underline;
}
.change-file-container {
  border: 1px solid rgb(208, 215, 222);
  border-radius: 6px;
  overflow: hidden;
  padding: 0;
}
/* The card is a stack of full-width bands separated by hairlines - no nested boxes with their own borders
   or padding. Same edge-to-edge treatment as the report view and file browser (FileSource.vue). */
.change-band {
  border-top: 1px solid rgb(208, 215, 222);
  padding: 12px 16px;
}
.change-reason {
  background-color: rgb(246, 248, 250);
}
.change-actions-bar {
  align-items: center;
  background-color: #fff;
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
}
/* The inline editor is a flush band, not a boxed-in card: white like the source view, its own hairline
   above, and no rounded inner border. The editor's own top margin is dropped so it sits against the rule. */
.change-editor {
  background: #fff;
}
.change-editor :deep(.snippet-editor) {
  margin-top: 0;
}
/* The rationale is server-rendered markdown (same pipeline as notes), so style its elements via :deep -
   scoped rules do not reach v-html content. Mirrors the note body treatment for a consistent look. */
/* The rationale sits between the white snippet source and the white actions bar; give it a tinted
   background so each divide is a colour change, not just a hairline (two white bands read as one). */
.change-rationale {
  background: rgb(246, 248, 250);
  color: #1f2328;
  font-size: 14px;
  line-height: 1.5;
}
.change-rationale :deep(h1),
.change-rationale :deep(h2),
.change-rationale :deep(h3),
.change-rationale :deep(h4) {
  font-size: 15px;
  font-weight: 600;
  margin: 16px 0 8px;
}
.change-rationale :deep(h1:first-child),
.change-rationale :deep(h2:first-child),
.change-rationale :deep(h3:first-child) {
  margin-top: 0;
}
.change-rationale :deep(p) {
  margin-bottom: 12px;
}
.change-rationale :deep(p:last-child) {
  margin-bottom: 0;
}
.change-rationale :deep(ul),
.change-rationale :deep(ol) {
  margin-bottom: 12px;
  padding-left: 22px;
}
.change-rationale :deep(li + li) {
  margin-top: 4px;
}
.change-rationale :deep(code) {
  background: rgba(175, 184, 193, 0.2);
  border-radius: 4px;
  font-size: 85%;
  padding: 0.2em 0.4em;
}
.change-rationale :deep(pre) {
  background: #fff;
  border: 1px solid rgb(208, 215, 222);
  border-radius: 6px;
  font-size: 12px;
  overflow: auto;
  padding: 12px;
}
.change-rationale :deep(pre code) {
  background: transparent;
  padding: 0;
}
.change-rationale :deep(a) {
  color: #0969da;
}
.change-footer {
  background-color: rgb(246, 248, 250);
  border-top: 1px solid rgb(208, 215, 222);
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.change-source {
  background: #fff;
  overflow: auto;
}
.change-source td.linenumber,
.change-source td.code {
  font-family: monospace;
  padding: 0;
  margin: 0;
  font-size: 12px;
  line-height: 20px;
  color: rgba(27, 31, 35, 0.3);
  border: 0 !important;
}
.change-source td.code {
  padding-left: 0.75rem;
  padding-right: 0.75rem;
  color: #24292e;
  margin-left: 0.5em;
  white-space: -moz-pre-wrap;
  white-space: -o-pre-wrap;
  white-space: pre-wrap;
  word-wrap: break-word;
  word-break: break-all;
}
.change-source td.linenumber {
  border-right: 1px solid #ddd;
  padding: 0 0.5em;
  margin-right: 0.5em;
  text-align: right;
  width: 1%;
  min-width: 25px;
  color: rgba(27, 31, 35, 0.3);
  user-select: none;
}
.change-license-line td {
  background-color: rgba(31, 136, 61, 0.12);
}
.change-license-line td:first-child {
  box-shadow: inset 3px 0 0 #1f883d;
}
.change-keyword-line td {
  background-color: rgba(191, 135, 0, 0.14);
}
.change-keyword-line td:first-child {
  box-shadow: inset 3px 0 0 #bf8700;
}
</style>
