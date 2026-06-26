<template>
  <div>
    <div class="row mt-3">
      <cavil-notice-panel intro class="col-12">
        These are license pattern changes proposed by contributors. New patterns are guaranted to match the snippet they
        were created for, and can only use an existing license and risk combination.
      </cavil-notice-panel>
    </div>
    <div class="row g-4">
      <div class="col-9">
        <form>
          <div class="row g-4">
            <div class="col-lg-3">
              <div class="form-check">
                <input
                  v-model="params.createPattern"
                  @change="refreshPage()"
                  type="checkbox"
                  class="form-check-input"
                />
                <label class="form-check-label" for="snippet-not-legal">License patterns</label>
              </div>
              <div class="form-check">
                <input v-model="params.createIgnore" @change="refreshPage()" type="checkbox" class="form-check-input" />
                <label class="form-check-label" for="snippet-is-legal">Ignore patterns</label>
              </div>
            </div>
            <div class="col-lg-3">
              <div class="form-check">
                <input v-model="params.createGlob" @change="refreshPage()" type="checkbox" class="form-check-input" />
                <label class="form-check-label" for="snippet-glob">Ignore globs</label>
              </div>
            </div>
          </div>
        </form>
      </div>
      <div class="col-lg-3">
        <form @submit.prevent="refreshPage()">
          <div class="form-floating">
            <input v-model="params.filter" type="text" class="form-control" placeholder="Filter" />
            <label class="form-label">Filter</label>
          </div>
        </form>
      </div>
    </div>
    <div v-if="changes !== null && changes.length > 0">
      <transition-group name="row" tag="div" @before-leave="onBeforeLeave" @leave="onLeave">
        <div v-for="change in changes" :key="change.id" class="row change-container">
          <div v-if="change.state === 'proposed'" class="col-12 change-file-container">
            <div class="change-header">
              <div class="change-title">
                <span v-if="change.action === 'create_pattern'">
                  Proposed by <b>{{ change.login }}</b>
                  <span class="cavil-meta-badges change-meta-badges">
                    <span class="cavil-meta-badge cavil-meta-badge-info">license pattern</span>
                    <a :href="change.editUrl" target="_blank" class="cavil-meta-badge cavil-meta-badge-muted">
                      {{ change.data.edited === true ? 'edited snippet' : 'unedited snippet' }}
                    </a>
                    <span v-if="change.data.ai_assisted" class="cavil-meta-badge cavil-meta-badge-info">
                      <i class="fa-solid fa-robot"></i> AI assisted
                    </span>
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
                <span v-else-if="change.action === 'create_ignore'">
                  Proposed by <b>{{ change.login }}</b>
                  <span class="cavil-meta-badges change-meta-badges">
                    <span class="cavil-meta-badge cavil-meta-badge-warning">ignore pattern</span>
                    <a :href="change.editUrl" target="_blank" class="cavil-meta-badge cavil-meta-badge-muted">
                      snippet
                    </a>
                    <span v-if="change.data.ai_assisted" class="cavil-meta-badge cavil-meta-badge-info">
                      <i class="fa-solid fa-robot"></i> AI assisted
                    </span>
                  </span>
                </span>
                <span v-else-if="change.action === 'create_glob'">
                  Proposed by <b>{{ change.login }}</b>
                  <span class="cavil-meta-badges change-meta-badges">
                    <span class="cavil-meta-badge cavil-meta-badge-warning">ignore glob</span>
                    <span v-if="change.data.ai_assisted" class="cavil-meta-badge cavil-meta-badge-info">
                      <i class="fa-solid fa-robot"></i> AI assisted
                    </span>
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
                  @click="rejectProposal(change)"
                  type="button"
                  class="cavil-icon-action cavil-icon-action-danger"
                  title="Reject proposal"
                  aria-label="Reject proposal"
                >
                  <i class="fa-solid fa-xmark"></i>
                </button>
              </div>
            </div>
            <div v-if="change.lines" class="change-source">
              <table :class="getClassForCode(change)">
                <tbody>
                  <tr v-for="line in change.lines" :key="line.num">
                    <td class="linenumber">{{ line.num }}</td>
                    <td :class="getClassForLine(line)">{{ line.text }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="change-form" :class="{'change-form-flush': !change.lines}">
              <div v-if="change.action === 'create_pattern'">
                <div class="row">
                  <div class="col mb-3">
                    <label class="fomr-label" for="license">License</label>
                    <input v-model="change.data.license" type="text" class="form-control" />
                  </div>
                </div>
                <div class="row">
                  <div class="col-lg-2 mb-3">
                    <div class="form-floating">
                      <select v-model="change.data.risk" class="form-control">
                        <option>0</option>
                        <option>1</option>
                        <option>2</option>
                        <option>3</option>
                        <option>4</option>
                        <option>5</option>
                        <option>6</option>
                        <option>7</option>
                        <option>8</option>
                        <option>9</option>
                      </select>
                      <label for="risk" class="form-label">Risk</label>
                    </div>
                  </div>
                  <div class="col-lg-2">
                    <div class="form-check">
                      <input v-model="change.data.patent" type="checkbox" class="form-check-input" />
                      <label class="form-check-label" for="patent">Patent</label>
                    </div>
                    <div class="form-check">
                      <input v-model="change.data.trademark" type="checkbox" class="form-check-input" />
                      <label class="form-check-label" for="trademark">Trademark</label>
                    </div>
                  </div>
                  <div class="col-lg-2">
                    <div class="form-check">
                      <input v-model="change.data.cla" type="checkbox" class="form-check-input" />
                      <label class="form-check-label" for="cla">CLA</label>
                    </div>
                    <div class="form-check">
                      <input v-model="change.data.eula" type="checkbox" class="form-check-input" />
                      <label class="form-check-label" for="eula">EULA</label>
                    </div>
                  </div>
                  <div class="col-lg-2">
                    <div class="form-check">
                      <input v-model="change.data.export_restricted" type="checkbox" class="form-check-input" />
                      <label class="form-check-label" for="export_restricted">Export Restricted</label>
                    </div>
                  </div>
                </div>
              </div>
              <div v-else-if="change.action === 'create_ignore'">
                <div class="row">
                  <div class="col mb-3">
                    <label class="form-label" for="license">Package</label>
                    <div class="d-flex form-check align-items-center form-check">
                      <input
                        class="form-check-input"
                        id="ignore-one"
                        type="checkbox"
                        name="ignore-for"
                        value="one"
                        v-model="ignoreForPackage"
                      />
                      <input
                        v-model="change.data.from"
                        type="text"
                        class="form-control ms-2"
                        :disabled="!ignoreForPackage"
                      />
                    </div>
                  </div>
                </div>
              </div>
              <div v-else-if="change.action === 'create_glob'">
                <div class="row">
                  <div class="col mb-3">
                    <label class="form-label" for="glob">Glob</label>
                    <input v-model="change.data.glob" type="text" class="form-control change-glob-input" />
                  </div>
                </div>
              </div>
              <div v-if="change.data.reason" class="row">
                <div class="col mb-3">
                  <label class="form-label" for="reason">Reason</label>
                  <textarea v-model="change.data.reason" class="form-control" disabled="disabled" rows="3"></textarea>
                </div>
              </div>
              <span v-if="hasAdminRole">
                <button @click="acceptProposal(change)" class="btn btn-success mb-2">Accept</button>
                &nbsp;
                <button @click="rejectProposal(change)" class="btn btn-danger btn-sm mb-2">Reject</button>
              </span>
            </div>
            <div v-if="change.action !== 'create_glob'" class="change-footer">
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
        <i class="fa-solid fa-rotate fa-spin"></i> Loading more changes
      </div>
      <BackToTop />
    </div>
    <div v-else-if="changes === null"><i class="fa-solid fa-rotate fa-spin"></i> Loading changes</div>
    <EmptyState v-else message="No proposed changes are waiting for review. Nice work keeping the queue clear." />
    <ToastNotifier ref="toaster" />
  </div>
</template>

<script>
import BackToTop from './components/BackToTop.vue';
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import EmptyState from './components/EmptyState.vue';
import ToastNotifier from './components/ToastNotifier.vue';
import {genParamWatchers, getParams} from './helpers/params.js';
import UserAgent from '@mojojs/user-agent';

// Accept/reject removes changes from the top without firing a scroll event, so refill the
// buffer proactively once it drops below this many remaining changes.
const REFILL_THRESHOLD = 5;

export default {
  name: 'ProposedPatterns',
  components: {BackToTop, CavilNoticePanel, EmptyState, ToastNotifier},
  data() {
    const params = getParams({createIgnore: true, createPattern: true, createGlob: true, filter: ''});

    return {
      changes: null,
      changeUrl: '/licenses/proposed/meta',
      ignoreForPackage: true,
      params: {...params, before: 0},
      total: null,
      loadingMore: false
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
    async acceptProposal(change) {
      change.state = 'updating';

      const ua = new UserAgent({baseURL: window.location.href});
      const formData = {...change.data};
      formData.contributor = change.login;
      formData.delay = 600;
      let kind = null;
      if (change.action === 'create_pattern') {
        for (const key of ['patent', 'trademark', 'export_restricted', 'cla', 'eula']) {
          formData[key] = change.data[key] === true ? '1' : '0';
        }
        formData.checksum = change.token_hexsum;
        kind = 'create-pattern';
      } else if (change.action === 'create_ignore') {
        formData.hash = change.token_hexsum;
        if (this.ignoreForPackage === true) {
          formData.from = change.data.from;
          kind = 'create-ignore';
        } else {
          kind = 'mark-non-license';
        }
      } else if (change.action === 'create_glob') {
        formData.checksum = change.token_hexsum;
        formData.glob = change.data.glob;
        formData.from = change.data.from;
        formData.package = change.data.package;
        kind = 'create-glob';
      }
      const body = {actions: [{kind, snippetId: change.data.snippet ?? null, formData}]};
      await ua.post('/snippet/batch_decision', {json: body, headers: {Accept: 'application/json'}});

      this.removeChange(change);
      this.$refs.toaster?.notify(
        'Proposal accepted, reindexing related packages in 10 minutes if necessary',
        'success'
      );
    },
    async getChanges() {
      const url = new URL(this.changeUrl, window.location.href);
      const query = this.params;
      if (query.createPattern === true || query.createPattern === 'true')
        url.searchParams.append('action', 'create_pattern');
      if (query.createIgnore === true || query.createIgnore === 'true')
        url.searchParams.append('action', 'create_ignore');
      if (query.createGlob === true || query.createGlob === 'true') url.searchParams.append('action', 'create_glob');

      const ua = new UserAgent();
      const res = await ua.get(url, {query});
      const data = await res.json();

      const changes = data.changes;
      if (this.total === null || this.total < data.total) this.total = data.total;

      for (const change of changes) {
        change.state = 'proposed';
        change.editUrl = `/snippet/edit/${change.data.snippet}`;
        change.removeUrl = `/licenses/proposed/remove/${change.token_hexsum}`;

        if (change.package !== null) change.package.pkgUrl = `/reviews/details/${change.package.id}`;
        if (change.closest !== null) change.closest.licenseUrl = `/licenses/edit_pattern/${change.closest.id}`;

        if (change.action === 'create_pattern') {
          for (const key of ['edited', 'patent', 'trademark', 'export_restricted', 'cla', 'eula']) {
            change.data[key] = change.data[key] === '1' ? true : false;
          }
        } else if (change.action === 'create_ignore') {
          change.editUrl = `${change.editUrl}?hash=${change.token_hexsum}&from=${change.data.from}`;
        }

        if (change.data.ai_assisted !== undefined) change.data.ai_assisted = change.data.ai_assisted == 1;

        // Glob proposals have no snippet pattern, so there is no source preview to render.
        if (typeof change.data.pattern === 'string') {
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
        } else {
          change.lines = null;
        }

        query.before = change.id;
      }

      if (this.changes === null) this.changes = [];
      this.changes.push(...changes);
    },
    getClassForLine(line) {
      return {
        'change-keyword-line code': line.highlighted === 'keyword',
        'change-license-line code': line.highlighted === 'license',
        code: line.highlighted === null
      };
    },
    getClassForCode(change) {
      return {
        'change-code-ignore': change.action === 'create_ignore',
        'change-code-pattern': change.action === 'create_pattern'
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
    async rejectProposal(change) {
      change.state = 'updating';
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(change.removeUrl);
      this.removeChange(change);
      this.$refs.toaster?.notify('Proposal removed', 'danger');
    },
    removeChange(change) {
      const i = this.changes.indexOf(change);
      if (i !== -1) this.changes.splice(i, 1);
      if (this.total !== null && this.total > 0) this.total--;
      this.refillBuffer();
    },
    refillBuffer() {
      // The list shrinks from the top as proposals are accepted/rejected, which does not trigger
      // the scroll handler. Pull in the next page before the user runs out of changes to act on.
      if (this.changes !== null && this.changes.length < REFILL_THRESHOLD) this.loadMore();
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
    },
    refreshPage() {
      this.total = null;
      this.changes = null;
      this.params.before = 0;
      this.getChanges();
    }
  },
  watch: {...genParamWatchers('createIgnore', 'createPattern', 'createGlob', 'filter')}
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
.change-form {
  background-color: rgb(246, 248, 250);
  border-top: 1px solid rgb(208, 215, 222);
  padding: 10px;
}
/* Glob proposals have no source preview, so the header's bottom border and the form's top border
   would sit directly on top of each other and read as a double-thick rule. Drop the duplicate. */
.change-form-flush {
  border-top: 0;
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
.change-license-line {
  background-color: rgba(31, 136, 61, 0.12);
  box-shadow: inset 3px 0 0 #1f883d;
}
.change-keyword-line {
  background-color: rgba(191, 135, 0, 0.14);
  box-shadow: inset 3px 0 0 #bf8700;
}
.change-code-ignore {
  background: repeating-linear-gradient(-45deg, #ffebe9, #ffebe9 1px, #fff 1px, #fff 5px);
}
</style>
